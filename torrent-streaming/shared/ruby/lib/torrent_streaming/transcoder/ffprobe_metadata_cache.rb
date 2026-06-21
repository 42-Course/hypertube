# frozen_string_literal: true

# This file owns the shared Ruby cache for ffprobe metadata on selected torrent
# video files. It keeps duration, audio, subtitle, and probe-health state in one
# durable place so interactive playback and final VOD packaging make the same
# decisions about a media record.

require "fileutils"
require "json"
require "securerandom"
require "time"

require_relative "../domain"
require_relative "../errors"
require_relative "../state_store"
require_relative "../validation"
require_relative "ffmpeg_command_builder"

module TorrentStreaming
  module Transcoder
    # Runs ffprobe through the range server, validates the raw JSON, and updates
    # media metadata without letting transient probe failures corrupt the state
    # contract. Invalid cached probe files are quarantined instead of reused so a
    # later fresh probe can repair metadata safely.
    class FfprobeMetadataCache
      TEXT_SUBTITLE_CODECS = %w[subrip srt webvtt mov_text text].freeze
      ASS_SUBTITLE_CODECS = %w[ass ssa].freeze
      IMAGE_SUBTITLE_CODECS = %w[hdmv_pgs_subtitle dvd_subtitle dvd_subtitle_stream xsub].freeze
      SUBTITLE_EXTENSIONS = {
        ".srt" => { codec: "subrip", supported: true },
        ".vtt" => { codec: "webvtt", supported: true },
        ".ass" => { codec: "ass", supported: false, reason: "ass_ssa_unsupported" },
        ".ssa" => { codec: "ssa", supported: false, reason: "ass_ssa_unsupported" },
        ".sup" => { codec: "hdmv_pgs_subtitle", supported: false, reason: "unsupported_image_subtitle" },
        ".idx" => { codec: "dvd_subtitle", supported: false, reason: "unsupported_image_subtitle" },
        ".sub" => { codec: "dvd_subtitle", supported: false, reason: "unsupported_image_subtitle" }
      }.freeze

      attr_reader :storage_root, :media_store, :ffprobe_bin, :range_server_url,
                  :timeout_seconds, :rw_timeout_us

      def initialize(storage_root: ENV.fetch("STORAGE_ROOT", "/app/storage"),
                     ffprobe_bin: ENV.fetch("FFPROBE_BIN", "ffprobe"),
                     range_server_url: ENV.fetch("RANGE_SERVER_URL", FfmpegCommandBuilder::DEFAULT_RANGE_SERVER_URL),
                     timeout_seconds: ENV.fetch("FFPROBE_TIMEOUT_SECONDS", "10").to_f,
                     rw_timeout_us: ENV.fetch("FFMPEG_RW_TIMEOUT_US", FfmpegCommandBuilder::DEFAULT_RW_TIMEOUT_US).to_i)
        @storage_root = File.expand_path(storage_root)
        @media_store = MediaStore.new(root: File.join(@storage_root, "state"))
        @ffprobe_bin = ffprobe_bin
        @range_server_url = range_server_url.to_s.delete_suffix("/")
        @timeout_seconds = timeout_seconds
        @rw_timeout_us = rw_timeout_us
      end

      # Probe and persist metadata for a selected file. Normal interactive
      # probes may reuse a valid raw ffprobe cache, but complete-file probes
      # bypass that cache because VOD packaging needs metadata captured after the
      # file is fully downloaded. Operational ffprobe failures are recorded as
      # degraded metadata so playback can continue with limited information.
      def probe_media!(media_id, file_index, force: false, complete_file: false)
        media = media_store.find(media_id)
        Media.validate_session_request!(media, file_index)
        safe_media_id = media.fetch("media_id")
        safe_file_index = Validation.non_negative_integer!(file_index, field: "file_index")
        cached = force || complete_file ? nil : read_cache(safe_media_id, safe_file_index)

        if cached
          begin
            return update_media_with_probe(safe_media_id, safe_file_index, cached, complete_file: complete_file)
          rescue DomainError => e
            raise unless operational_probe_error?(e)
          end
        end

        attempts = next_attempt_count(media)
        progress_bytes_downloaded = progress_bytes_downloaded(media)
        result = run_probe(safe_media_id, safe_file_index)
        update_media_with_probe(
          safe_media_id,
          safe_file_index,
          result,
          complete_file: complete_file,
          attempts: attempts,
          progress_bytes_downloaded: progress_bytes_downloaded
        )
      rescue DomainError => e
        raise unless operational_probe_error?(e)

        record_probe_error(
          media_id,
          e,
          complete_file: complete_file,
          attempts: attempts,
          progress_bytes_downloaded: progress_bytes_downloaded
        )
      rescue StandardError => e
        record_probe_error(
          media_id,
          e,
          complete_file: complete_file,
          attempts: attempts,
          progress_bytes_downloaded: progress_bytes_downloaded
        )
      end

      def mark_probe_pending!(media_id, file_index, complete_file: false)
        media_store.update(media_id) do |current|
          Media.validate_session_request!(current, file_index)
          previous = metadata_probe(current)
          current.merge(
            "metadata_probe" => previous.merge(
              "status" => "pending",
              "error" => previous["error"] || "ffprobe_timeout",
              "updated_at" => Clock.iso8601,
              "complete_file" => complete_file,
              "attempts" => probe_attempts(previous),
              "progress_bytes_downloaded" => progress_bytes_downloaded(current)
            )
          )
        end
      end

      # Convert raw ffprobe JSON into the persisted media metadata shape. The
      # complete_file flag is part of the trust contract: only successful probes
      # made against a fully downloaded source can unlock final VOD packaging.
      # External subtitle files are folded into the same track list so callers do
      # not need to know whether a subtitle came from the container or the
      # torrent file list.
      def parse_probe_result(result, media, complete_file: false, attempts: nil, progress_bytes_downloaded: nil)
        validate_probe_result!(result)
        streams = result.fetch("streams", [])
        audio_index = 0
        subtitle_index = 0
        audio_tracks = []
        subtitles = []

        streams.each do |stream|
          codec_type = stream["codec_type"]
          tags = stream["tags"] || {}
          case codec_type
          when "audio"
            audio_tracks << {
              "index" => audio_index,
              "stream_index" => stream["index"],
              "codec" => stream["codec_name"],
              "language" => tags["language"],
              "title" => tags["title"]
            }.compact
            audio_index += 1
          when "subtitle"
            subtitles << subtitle_track_from_stream(stream, subtitle_index)
            subtitle_index += 1
          end
        end

        external_subtitles(media, subtitle_index).each { |track| subtitles << track }

        {
          "duration_seconds" => parse_duration(result),
          "audio_tracks" => audio_tracks,
          "subtitles" => subtitles,
          "metadata_probe" => {
            "status" => "ok",
            "updated_at" => Clock.iso8601,
            "complete_file" => complete_file,
            "attempts" => attempts || probe_attempts(media["metadata_probe"]),
            "progress_bytes_downloaded" => progress_bytes_downloaded || progress_bytes_downloaded(media)
          }
        }
      end

      private

      # Run ffprobe against the range-server URL and cache the raw result. The
      # child is launched in its own process group so timeout cleanup is scoped to
      # the probe process rather than this worker. The cache is written only
      # after JSON parsing succeeds, which keeps partial ffprobe output from
      # becoming trusted metadata.
      def run_probe(media_id, file_index)
        safe_media_id = Validation.media_id!(media_id)
        safe_file_index = Validation.non_negative_integer!(file_index, field: "file_index")
        FileUtils.mkdir_p(cache_dir)
        FileUtils.mkdir_p(log_dir)
        out_path = File.join(cache_dir, "#{safe_media_id}-#{safe_file_index}.json.tmp")
        err_path = File.join(log_dir, "ffprobe-#{safe_media_id}-#{safe_file_index}.log")
        final_path = cache_path(safe_media_id, safe_file_index)
        url = "#{range_server_url}/files/#{safe_media_id}/#{safe_file_index}"
        command = [
          ffprobe_bin,
          "-v", "error",
          "-rw_timeout", rw_timeout_us.to_s,
          "-print_format", "json",
          "-show_format",
          "-show_streams",
          url
        ]

        pid = nil
        File.open(out_path, "wb") do |out|
          File.open(err_path, "ab") do |err|
            err.puts("[#{Clock.iso8601}] exec #{command.join(" ")}")
            err.flush
            pid = Process.spawn(*command, out: out, err: err, pgroup: true)
          end
        end
        status = wait_with_timeout(pid)
        unless status&.success?
          raise ValidationError.new("ffprobe failed", code: "ffprobe_failed")
        end

        parsed = JSON.parse(File.read(out_path, encoding: "utf-8"))
        atomic_write_json(final_path, parsed)
        parsed
      ensure
        FileUtils.rm_f(out_path) if out_path
      end

      def wait_with_timeout(pid)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
        loop do
          waited = Process.waitpid2(pid, Process::WNOHANG)
          return waited.last if waited

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            terminate_process_group(pid)
            raise ValidationError.new("ffprobe timed out", code: "ffprobe_timeout")
          end

          sleep 0.05
        end
      rescue Errno::ECHILD
        nil
      end

      def terminate_process_group(pgid)
        Process.kill("TERM", -pgid)
        sleep 0.1
        Process.kill("KILL", -pgid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      # Cached probe JSON is never trusted blindly. If it is malformed or no
      # longer matches the probe contract, it is moved aside before the caller
      # falls back to a fresh probe.
      def read_cache(media_id, file_index)
        path = cache_path(media_id, file_index)
        return nil unless File.file?(path)

        parsed = JSON.parse(File.read(path, encoding: "utf-8"))
        validate_probe_result!(parsed)
        parsed
      rescue JSON::ParserError, DomainError
        quarantine_cache(path)
        nil
      end

      def update_media_with_probe(media_id, file_index, result, complete_file: false, attempts: nil, progress_bytes_downloaded: nil)
        media_store.update(media_id) do |current|
          Media.validate_session_request!(current, file_index)
          current.merge(
            parse_probe_result(
              result,
              current,
              complete_file: complete_file,
              attempts: attempts,
              progress_bytes_downloaded: progress_bytes_downloaded
            )
          )
        end
      end

      # Persist a degraded probe result for operational failures. This records
      # enough context for retry and UI reporting while leaving the selected
      # media usable for flows that can tolerate missing duration or track data.
      def record_probe_error(media_id, error, complete_file: false, attempts: nil, progress_bytes_downloaded: nil)
        media_store.update(media_id) do |current|
          current.merge(
            "metadata_probe" => {
              "status" => "degraded",
              "error" => error.respond_to?(:code) ? error.code : "ffprobe_error",
              "updated_at" => Clock.iso8601,
              "complete_file" => complete_file,
              "attempts" => attempts || probe_attempts(current["metadata_probe"]),
              "progress_bytes_downloaded" => progress_bytes_downloaded || progress_bytes_downloaded(current)
            }
          )
        end
      end

      def subtitle_track_from_stream(stream, index)
        codec = stream["codec_name"].to_s
        tags = stream["tags"] || {}
        policy = subtitle_policy(codec, source: "embedded")
        {
          "index" => index,
          "stream_index" => stream["index"],
          "source" => "embedded",
          "codec" => codec,
          "language" => tags["language"],
          "title" => tags["title"],
          "supported" => policy.fetch(:supported),
          "reason" => policy[:reason]
        }.compact
      end

      # Add supported external subtitle sidecars to the ffprobe-derived subtitle
      # list. Accessibility here is only a lightweight metadata signal; the
      # actual subtitle reader performs a stricter realpath containment check
      # before opening a source file.
      def external_subtitles(media, start_index)
        index = start_index
        media.fetch("files").filter_map do |file|
          next unless file["kind"] == "subtitle"

          ext = File.extname(file["path"].to_s).downcase
          policy = SUBTITLE_EXTENSIONS[ext]
          next unless policy
          source_path = normalized_external_source_path(file["source_path"])
          accessible = policy.fetch(:supported) ? external_source_accessible?(source_path) : false
          reason = if policy.fetch(:supported)
                     accessible ? nil : "subtitle_source_unavailable"
                   else
                     policy[:reason]
                   end

          track = {
            "index" => index,
            "source" => "external",
            "file_index" => file["index"],
            "path" => file["path"],
            "source_path" => source_path,
            "codec" => policy.fetch(:codec),
            "supported" => accessible,
            "reason" => reason
          }.compact
          index += 1
          track
        end
      end

      def validate_probe_result!(result)
        unless result.is_a?(Hash) && result["streams"].is_a?(Array) &&
               (result["format"].nil? || result["format"].is_a?(Hash))
          raise ValidationError.new("invalid ffprobe result", code: "invalid_ffprobe_result")
        end

        result
      end

      def operational_probe_error?(error)
        error.is_a?(ValidationError) && %w[
          ffprobe_failed ffprobe_timeout invalid_ffprobe_result
        ].include?(error.code)
      end

      def normalized_external_source_path(value)
        return nil if value.nil?

        Validation.relative_path!(value, field: "subtitle source_path")
      rescue DomainError
        nil
      end

      def external_source_accessible?(source_path)
        return false if source_path.nil?

        path = File.expand_path(File.join(storage_root, source_path))
        return false unless path.start_with?("#{storage_root}/")

        File.file?(path)
      end

      def subtitle_policy(codec, source: nil)
        if TEXT_SUBTITLE_CODECS.include?(codec)
          { supported: true }
        elsif ASS_SUBTITLE_CODECS.include?(codec)
          source == "embedded" ? { supported: true } : { supported: false, reason: "ass_ssa_unsupported" }
        elsif IMAGE_SUBTITLE_CODECS.include?(codec)
          { supported: false, reason: "unsupported_image_subtitle" }
        else
          { supported: false, reason: "unsupported_subtitle_codec" }
        end
      end

      def parse_duration(result)
        value = result.dig("format", "duration")
        return nil if value.nil? || value.to_s.empty?

        Float(value)
      rescue ArgumentError
        nil
      end

      def metadata_probe(media)
        probe = media["metadata_probe"]
        probe.is_a?(Hash) ? probe : {}
      end

      def probe_attempts(probe)
        value = probe.is_a?(Hash) ? probe["attempts"] : nil
        Integer(value || 0)
      rescue ArgumentError, TypeError
        0
      end

      def next_attempt_count(media)
        probe_attempts(media["metadata_probe"]) + 1
      end

      def progress_bytes_downloaded(media)
        progress = media["video_progress"].is_a?(Hash) ? media["video_progress"] : {}
        Integer(progress["bytes_downloaded"] || 0)
      rescue ArgumentError, TypeError
        0
      end

      def cache_dir
        File.join(storage_root, "state", "probes")
      end

      def log_dir
        File.join(storage_root, "logs", "ffprobe")
      end

      def cache_path(media_id, file_index)
        File.join(cache_dir, "#{Validation.media_id!(media_id)}-#{Validation.non_negative_integer!(file_index, field: "file_index")}.json")
      end

      def atomic_write_json(path, record)
        FileUtils.mkdir_p(File.dirname(path))
        temp = "#{path}.#{Process.pid}.tmp"
        File.write(temp, "#{JSON.pretty_generate(record)}\n")
        File.rename(temp, path)
      ensure
        FileUtils.rm_f(temp) if temp && File.exist?(temp)
      end

      # Preserve invalid cache content for later inspection when possible, but
      # remove it if the filesystem move itself fails. Either way, callers will
      # not reuse a cache entry that failed validation.
      def quarantine_cache(path)
        FileUtils.mkdir_p(corrupt_cache_dir)
        destination = File.join(
          corrupt_cache_dir,
          "#{File.basename(path, ".json")}.#{Time.now.utc.strftime("%Y%m%dT%H%M%S%6NZ")}.#{Process.pid}.#{SecureRandom.hex(4)}.json"
        )
        FileUtils.mv(path, destination)
      rescue SystemCallError
        FileUtils.rm_f(path)
      end

      def corrupt_cache_dir
        File.join(cache_dir, "corrupt")
      end
    end
  end
end
