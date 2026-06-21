# frozen_string_literal: true

# This file owns final VOD HLS packaging for completed torrent media. It turns a
# trusted complete-file probe into staged video, audio, and subtitle renditions,
# validates the generated playlists, and publishes the finished directory only
# after the output is ready.

require "fileutils"
require "securerandom"
require "time"

require_relative "../domain"
require_relative "../errors"
require_relative "../state_store"
require_relative "../validation"
require_relative "ffmpeg_command_builder"
require_relative "job_client"
require_relative "subtitle_sidecar_writer"

module TorrentStreaming
  module Transcoder
    # Coordinates VOD packaging state, ffmpeg processes, cancellation, recovery,
    # and atomic publication. The class keeps every packaging attempt tied to an
    # attempt id so stale workers cannot overwrite newer state or publish output
    # after cancellation.
    class VodPackager
      ACTIVE_VOD_STATES = %w[pending running packaging cancelling].freeze
      TERMINAL_VOD_STATES = %w[ready failed cancelled].freeze
      REPLAN_MEDIA_STATES = %w[downloaded packaging_vod].freeze

      attr_reader :storage_root, :media_store, :builder, :subtitle_writer,
                  :poll_interval_seconds, :stop_grace_seconds

      def initialize(storage_root: ENV.fetch("STORAGE_ROOT", "/app/storage"), builder: nil,
                     subtitle_writer: nil,
                     poll_interval_seconds: ENV.fetch("FFMPEG_HLS_POLL_INTERVAL_SECONDS", "0.1").to_f,
                     stop_grace_seconds: ENV.fetch("FFMPEG_STOP_GRACE_SECONDS", "5").to_f)
        @storage_root = File.expand_path(storage_root)
        @media_store = MediaStore.new(root: File.join(@storage_root, "state"))
        @builder = builder || FfmpegCommandBuilder.new(storage_root: @storage_root)
        @subtitle_writer = subtitle_writer || SubtitleSidecarWriter.new(storage_root: @storage_root)
        @poll_interval_seconds = poll_interval_seconds
        @stop_grace_seconds = stop_grace_seconds
      end

      # Queue VOD packaging when a media record is eligible and has trusted final
      # metadata. The state update happens before enqueueing so duplicate jobs
      # see the pending record and leave the existing attempt alone unless force
      # explicitly resets it.
      def schedule(media_id, force: false)
        enqueue = false
        media = media_store.update(media_id) do |current|
          next current if vod_ready?(current)
          next current unless force || vod_schedulable?(current)
          next current unless force || final_metadata_ready?(current)

          vod = current["vod_packaging"]
          if !force && vod.is_a?(Hash) && (ACTIVE_VOD_STATES + TERMINAL_VOD_STATES).include?(vod["state"])
            next current
          end

          enqueue = true
          current.merge(
            "state" => "downloaded",
            "hls_vod_path" => nil,
            "vod_packaging" => pending_record(vod)
          )
        end
        enqueue_vod(media.fetch("media_id")) if enqueue
        media_store.find(media.fetch("media_id"))
      end

      # Build final VOD output for one media record. All ffmpeg output is written
      # to an attempt-specific staging directory, then video, audio, subtitles,
      # and the master playlist are validated before anything is published to the
      # final HLS path. Cancellation is checked between phases so interactive
      # playback can preempt long packaging runs without leaving media marked
      # ready for incomplete artifacts.
      def package(media_id)
        media = begin_packaging(media_id)
        return media unless media

        final_dir = vod_directory(media.fetch("media_id"))
        attempt_id = media.fetch("vod_packaging").fetch("attempt_id")
        staging_dir = staging_directory(media.fetch("media_id"), attempt_id)
        log_path = vod_log_path(media.fetch("media_id"))

        begin
          ensure_final_metadata!(media)
          source_path = source_video_path(media)
          FileUtils.rm_rf(staging_dir)
          FileUtils.mkdir_p(staging_dir)
          FileUtils.mkdir_p(File.dirname(log_path))

          video_uri = run_vod_command(
            media.fetch("media_id"),
            attempt_id,
            builder.vod_video_command(source_path: source_path, output_root: staging_dir),
            log_path
          )
          return mark_cancelled(media.fetch("media_id"), attempt_id, requeue: true) if video_uri == :cancelled

          audio_renditions = []
          supported_audio_tracks(media).each do |track|
            result = run_vod_command(
              media.fetch("media_id"),
              attempt_id,
              builder.vod_audio_command(source_path: source_path, output_root: staging_dir, audio_track: track),
              log_path
            )
            return mark_cancelled(media.fetch("media_id"), attempt_id, requeue: true) if result == :cancelled

            audio_renditions << audio_rendition(track)
          end

          subtitle_renditions = write_vod_subtitles(media, staging_dir)
          return mark_cancelled(media.fetch("media_id"), attempt_id, requeue: true) if cancel_requested?(media.fetch("media_id"), attempt_id)

          write_master_playlist(
            staging_dir,
            audio_renditions: audio_renditions,
            subtitle_renditions: subtitle_renditions
          )
          return mark_cancelled(media.fetch("media_id"), attempt_id, requeue: true) if cancel_requested?(media.fetch("media_id"), attempt_id)

          publish_ready(
            media.fetch("media_id"),
            attempt_id,
            staging_dir: staging_dir,
            final_dir: final_dir,
            audio_renditions: audio_renditions,
            subtitle_renditions: subtitle_renditions,
            unsupported_subtitles: unsupported_subtitles(media)
          ) || mark_cancelled(media.fetch("media_id"), attempt_id, requeue: true)
        rescue DomainError => e
          mark_failed(media.fetch("media_id"), attempt_id, code: e.code, message: e.message)
        rescue StandardError => e
          mark_failed(media.fetch("media_id"), attempt_id, code: "vod_packaging_failed", message: e.message)
        ensure
          FileUtils.rm_rf(staging_dir) if Dir.exist?(staging_dir)
        end
      end

      # Replan VOD work that was interrupted before a clean terminal state was
      # recorded. Boot recovery only requeues media when final metadata is still
      # trusted; otherwise it records metadata_pending so a complete-file probe
      # can refresh the contract before packaging restarts.
      def recover_interrupted!
        replanned = []
        media_store.all.each do |media|
          next if vod_ready?(media)
          next unless replan_vod?(media)

          unless final_metadata_ready?(media)
            mark_metadata_pending_for_recovery(media) if metadata_recoverable_without_probe?(media)
            next
          end

          updated = media_store.update(media.fetch("media_id")) do |current|
            next current if vod_ready?(current)
            next current unless final_metadata_ready?(current)

            current.merge(
              "state" => "downloaded",
              "hls_vod_path" => nil,
              "vod_packaging" => pending_record(current["vod_packaging"]).merge(
                "replanned_at" => Clock.iso8601,
                "error" => {
                  "code" => "stale_vod_worker_boot",
                  "message" => "VOD packaging was replanned after worker boot",
                  "at" => Clock.iso8601
                }
              )
            )
          end
          enqueue_vod(updated.fetch("media_id"))
          replanned << updated.fetch("media_id")
        end
        replanned
      end

      private

      # Mark interrupted work as waiting for metadata instead of packaging from a
      # partial or degraded probe. This lets recovery preserve the need for a
      # trusted complete-file probe without losing the fact that VOD should be
      # retried later.
      def mark_metadata_pending_for_recovery(media)
        media_store.update(media.fetch("media_id")) do |current|
          next current if vod_ready?(current)
          next current if final_metadata_ready?(current)
          next current unless metadata_recoverable_without_probe?(current)

          current.merge(
            "state" => "downloaded",
            "hls_vod_path" => nil,
            "vod_packaging" => metadata_pending_record(current["vod_packaging"])
          )
        end
      rescue NotFoundError
        nil
      end

      # Claim a packaging attempt under the media record lock. This rejects
      # terminal failures, duplicate running attempts, already-ready media, and
      # records that still need a complete-file probe before ffmpeg work starts.
      # A fresh attempt id is the ownership token used by cancellation and stale
      # worker checks throughout the rest of the run.
      def begin_packaging(media_id)
        started = false
        media = media_store.update(media_id) do |current|
          next current if vod_ready?(current)
          next current unless REPLAN_MEDIA_STATES.include?(current.fetch("state"))

          vod = current["vod_packaging"]
          next current if terminal_vod_blocked?(vod)
          unless final_metadata_ready?(current)
            next current.merge(
              "state" => "downloaded",
              "vod_packaging" => metadata_pending_record(vod)
            )
          end
          if vod.is_a?(Hash) && vod["state"] == "running"
            next current
          end

          started = true
          attempt_id = SecureRandom.hex(16)
          current.merge(
            "state" => "packaging_vod",
            "vod_packaging" => running_record(vod, media_id: current.fetch("media_id"), attempt_id: attempt_id)
          )
        end
        started ? media : nil
      end

      def pending_record(previous)
        {
          "state" => "pending",
          "queued_at" => Clock.iso8601,
          "attempts" => previous.is_a?(Hash) ? previous.fetch("attempts", 0) : 0,
          "attempt_id" => nil,
          "cancel_requested" => false,
          "ffmpeg_pid" => nil,
          "ffmpeg_pgid" => nil,
          "process_identity" => nil
        }
      end

      def running_record(previous, media_id:, attempt_id:)
        {
          "state" => "running",
          "started_at" => Clock.iso8601,
          "attempts" => (previous.is_a?(Hash) ? previous.fetch("attempts", 0) : 0) + 1,
          "attempt_id" => attempt_id,
          "cancel_requested" => false,
          "ffmpeg_pid" => nil,
          "ffmpeg_pgid" => nil,
          "process_identity" => nil,
          "log_path" => relative_vod_log_path(media_id)
        }
      end

      def metadata_pending_record(previous)
        pending_record(previous).merge(
          "state" => "metadata_pending",
          "error" => {
            "code" => "vod_metadata_unavailable",
            "message" => "VOD packaging is waiting for trusted metadata",
            "at" => Clock.iso8601
          }
        )
      end

      def vod_ready?(media)
        media.fetch("state") == "ready" && media["hls_vod_path"] && File.file?(File.join(storage_root, "hls", media["hls_vod_path"]))
      end

      # Final VOD must be based on a probe that was made after the selected file
      # completed. Degraded or partial metadata is useful for playback, but it is
      # not trusted enough to decide final renditions for a published asset.
      def final_metadata_ready?(media)
        probe = media["metadata_probe"]
        probe.is_a?(Hash) && probe["status"] == "ok" && probe["complete_file"] == true
      end

      def terminal_vod_blocked?(vod)
        return false unless vod.is_a?(Hash)
        return true if vod["state"] == "failed"
        return true if vod["state"] == "cancelled" && !vod["requeue_requested"]

        false
      end

      def interrupted_vod?(media)
        vod = media["vod_packaging"]
        media.fetch("state") == "packaging_vod" ||
          (vod.is_a?(Hash) && ACTIVE_VOD_STATES.include?(vod["state"])) ||
          (vod.is_a?(Hash) && vod["state"] == "cancelled" && vod["requeue_requested"])
      end

      def missing_ready_artifact?(media)
        media.fetch("state") == "ready" && media["hls_vod_path"] && !vod_ready?(media)
      end

      def metadata_recoverable_without_probe?(media)
        interrupted_vod?(media) || missing_ready_artifact?(media)
      end

      def replan_vod?(media)
        vod = media["vod_packaging"]
        return true if vod.is_a?(Hash) && vod["state"] == "cancelled" && vod["requeue_requested"]
        return false if vod.is_a?(Hash) && %w[failed cancelled].include?(vod["state"])
        return true if media.fetch("state") == "downloaded" && media["hls_vod_path"].nil?
        return true if media.fetch("state") == "packaging_vod"
        return true if media.fetch("state") == "ready" && media["hls_vod_path"] && !vod_ready?(media)

        vod.is_a?(Hash) && ACTIVE_VOD_STATES.include?(vod["state"])
      end

      def vod_schedulable?(media)
        REPLAN_MEDIA_STATES.include?(media.fetch("state")) || selected_file_complete?(media)
      end

      def selected_file_complete?(media)
        progress = media["video_progress"].is_a?(Hash) ? media["video_progress"] : {}
        total = Integer(progress["bytes_total"] || 0)
        downloaded = Integer(progress["bytes_downloaded"] || 0)
        total.positive? && downloaded >= total
      rescue ArgumentError, TypeError
        false
      end

      # Fail the current attempt if trusted final metadata is not present. This
      # guard is repeated inside package because state can change between queue
      # scheduling and the worker actually claiming the job.
      def ensure_final_metadata!(media)
        return if final_metadata_ready?(media)

        raise ValidationError.new("final VOD metadata is unavailable", code: "vod_metadata_unavailable")
      end

      # Resolve the selected completed video file inside torrent storage. The
      # persisted file path is relative, then both lexical containment and
      # realpath containment are checked so symlinks cannot redirect ffmpeg
      # outside the media directory.
      def source_video_path(media)
        file = selected_video_file(media)
        base = strict_torrent_media_directory(media.fetch("media_id"))
        Validation.relative_path!(file.fetch("path"), field: "file.path")
        target = File.expand_path(File.join(base, file.fetch("path")))
        unless target.start_with?("#{base}/")
          raise ValidationError.new("source video escapes torrent storage", code: "invalid_path")
        end
        unless File.file?(target)
          raise ValidationError.new("source video is unavailable", code: "source_unavailable")
        end

        # Realpath closes symlink escapes after the selected file is found.
        target_real = File.realpath(target)
        unless target_real.start_with?("#{base}/")
          raise ValidationError.new("source video escapes torrent storage", code: "invalid_path")
        end

        target_real
      end

      def selected_video_file(media)
        Media.validate_session_request!(media, media.fetch("selected_file_index"))
        file = media.fetch("files").find { |candidate| candidate["index"] == media.fetch("selected_file_index") }
        unless file && file["kind"] == "video" && file.fetch("supported", true)
          raise ValidationError.new("selected file is not a supported video", code: "invalid_file_index")
        end

        file
      end

      def supported_audio_tracks(media)
        media.fetch("audio_tracks").select { |track| track.fetch("supported", true) }
      end

      def unsupported_subtitles(media)
        media.fetch("subtitles").select { |track| track["supported"] == false }.map do |track|
          {
            "index" => track["index"],
            "codec" => track["codec"],
            "reason" => track["reason"] || "unsupported_subtitle_track"
          }.compact
        end
      end

      # Write VOD subtitle sidecars and their HLS playlists into staging. Each
      # playlist is validated immediately so a bad subtitle output cannot be
      # referenced from the final master playlist.
      def write_vod_subtitles(media, output_root)
        vod_subtitle_tracks(media).map do |track|
          vtt_uri = subtitle_writer.prepare_vod!(
            media_id: media.fetch("media_id"),
            track: track,
            output_root: output_root
          )
          playlist_uri = subtitle_playlist_uri(track)
          write_subtitle_playlist(
            File.join(output_root, playlist_uri),
            vtt_uri: File.basename(vtt_uri),
            duration_seconds: media["duration_seconds"]
          )
          validate_hls_playlist!(File.join(output_root, playlist_uri))
          subtitle_rendition(track, playlist_uri)
        end
      end

      def vod_subtitle_tracks(media)
        tracks = media.fetch("subtitles").select do |track|
          track.fetch("supported", true) && track["source"] == "external" && track["source_path"]
        end
        return tracks unless tracks.empty?

        media.fetch("files").filter_map.with_index do |file, index|
          next unless file["kind"] == "subtitle" && file.fetch("supported", true)

          source_path = subtitle_source_path(media.fetch("media_id"), file)
          next unless source_path

          {
            "index" => index,
            "source" => "external",
            "file_index" => file["index"],
            "path" => file["path"],
            "source_path" => source_path,
            "codec" => File.extname(file["path"].to_s).downcase == ".vtt" ? "webvtt" : "subrip",
            "supported" => true
          }
        end
      end

      def subtitle_source_path(media_id, file)
        extension = File.extname(file["path"].to_s).downcase
        return nil unless %w[.srt .vtt].include?(extension)

        Validation.relative_path!(file.fetch("path"), field: "subtitle.path")
        relative = File.join("torrents", media_id, file.fetch("path"))
        base = strict_torrent_media_directory(media_id)
        path = File.expand_path(File.join(base, file.fetch("path")))
        return nil unless path.start_with?("#{base}/")
        return nil unless File.file?(path)

        path_real = File.realpath(path)
        # Realpath containment catches subtitle symlinks that point outside the media tree.
        unless path_real.start_with?("#{base}/")
          raise ValidationError.new("subtitle source escapes torrent storage", code: "invalid_path")
        end

        relative
      end

      def strict_torrent_media_directory(media_id)
        safe_media_id = Validation.media_id!(media_id)
        torrents_root = File.realpath(File.join(storage_root, "torrents"))
        base = File.expand_path(File.join(torrents_root, safe_media_id))
        unless base.start_with?("#{torrents_root}/")
          raise ValidationError.new("media directory escapes torrent storage", code: "invalid_path")
        end

        base_real = File.realpath(base)
        unless base_real == base
          raise ValidationError.new("media directory escapes torrent storage", code: "invalid_path")
        end

        base
      rescue Errno::ENOENT
        File.expand_path(File.join(storage_root, "torrents", safe_media_id))
      end

      def audio_rendition(track)
        index = Validation.non_negative_integer!(track.fetch("index"), field: "audio.index")
        {
          "index" => index,
          "name" => track_name(track, fallback: "Audio #{index}"),
          "language" => track["language"],
          "uri" => "audio_#{index}/playlist.m3u8",
          "default" => index.zero?
        }.compact
      end

      def subtitle_rendition(track, uri)
        index = Validation.non_negative_integer!(track.fetch("index"), field: "subtitle.index")
        {
          "index" => index,
          "name" => track_name(track, fallback: "Subtitle #{index}"),
          "language" => track["language"],
          "uri" => uri
        }.compact
      end

      def track_name(track, fallback:)
        [track["language"], track["title"]].compact.reject(&:empty?).join(" ").then do |value|
          value.empty? ? fallback : value
        end
      end

      # Run one ffmpeg command for the current VOD attempt. The process id and
      # identity are recorded after spawn so cancellation and recovery can target
      # only the owned process group. A cancellation request is treated as a
      # normal control path and returns :cancelled, while a completed command must
      # still pass playlist validation before it is accepted.
      def run_vod_command(media_id, attempt_id, command, log_path)
        return :cancelled if cancel_requested?(media_id, attempt_id)

        prepare_hls_output!(command)
        pid = spawn_ffmpeg(command, log_path)
        unless record_vod_process(media_id, attempt_id, pid)
          terminate_process_group(pid, grace_seconds: stop_grace_seconds)
          return :cancelled
        end

        status = wait_for_process(pid, media_id, attempt_id)
        terminate_process_group(pid, grace_seconds: stop_grace_seconds) if status == :cancelled
        clear_vod_process(media_id, attempt_id)
        return :cancelled if status == :cancelled || cancel_requested?(media_id, attempt_id)
        if status&.success?
          validate_hls_playlist!(command.last)
          return true
        end

        raise ValidationError.new("ffmpeg VOD packaging failed", code: "vod_ffmpeg_failed")
      end

      def prepare_hls_output!(command)
        playlist = command.last
        FileUtils.mkdir_p(File.dirname(playlist))
        segment_pattern = option_value(command, "-hls_segment_filename")
        FileUtils.mkdir_p(File.dirname(segment_pattern)) if segment_pattern
      end

      def option_value(command, option)
        index = command.index(option)
        index ? command[index + 1] : nil
      end

      # Validate that ffmpeg produced a closed VOD media playlist and that every
      # referenced segment is local, present, and non-empty. This prevents the
      # final master playlist from pointing at partial output or paths outside
      # the rendition directory.
      def validate_hls_playlist!(playlist_path)
        unless File.file?(playlist_path) && File.size?(playlist_path)
          raise ValidationError.new("ffmpeg did not publish a VOD media playlist", code: "vod_hls_invalid")
        end

        base = File.realpath(File.dirname(playlist_path))
        lines = File.readlines(playlist_path, chomp: true)
        unless lines.include?("#EXT-X-ENDLIST")
          raise ValidationError.new("VOD media playlist is not closed", code: "vod_hls_invalid")
        end

        segments = lines.reject { |line| line.empty? || line.start_with?("#") }
        if segments.empty?
          raise ValidationError.new("VOD media playlist has no segments", code: "vod_hls_invalid")
        end

        segments.each do |segment|
          Validation.relative_path!(segment, field: "hls.segment")
          segment_path = File.expand_path(File.join(base, segment))
          unless segment_path.start_with?("#{base}/")
            raise ValidationError.new("VOD media segment escapes playlist directory", code: "vod_hls_invalid")
          end
          unless File.file?(segment_path) && File.size?(segment_path)
            raise ValidationError.new("VOD media segment is missing", code: "vod_hls_invalid")
          end
        end
      end

      def spawn_ffmpeg(command, log_path)
        File.open(log_path, "ab") do |log|
          log.sync = true
          log.puts("[#{Clock.iso8601}] exec #{log_command(command)}")
          Process.spawn(*command, out: log, err: log, pgroup: true)
        end
      end

      def log_command(command)
        command.map { |argument| argument.to_s.gsub(/[[:cntrl:]]/, " ") }.join(" ")
      end

      def wait_for_process(pid, media_id, attempt_id)
        loop do
          waited = Process.waitpid2(pid, Process::WNOHANG)
          return waited.last if waited
          return :cancelled if cancel_requested?(media_id, attempt_id)

          sleep poll_interval_seconds
        end
      rescue Errno::ECHILD
        nil
      end

      # Attach the spawned ffmpeg process to this attempt in durable state. If
      # the attempt was cancelled or superseded between spawn and update, the
      # caller immediately stops the process instead of letting stale work run.
      def record_vod_process(media_id, attempt_id, pid)
        identity = process_identity(pid)
        recorded = false
        media_store.update(media_id) do |current|
          vod = current["vod_packaging"].is_a?(Hash) ? current["vod_packaging"] : {}
          next current unless active_owned_vod?(vod, attempt_id)

          recorded = true
          current.merge(
            "vod_packaging" => vod.merge(
              "state" => "running",
              "ffmpeg_pid" => pid,
              "ffmpeg_pgid" => pid,
              "process_identity" => identity,
              "log_path" => relative_vod_log_path(media_id)
            )
          )
        end
        recorded
      end

      def clear_vod_process(media_id, attempt_id)
        media_store.update(media_id) do |current|
          vod = current["vod_packaging"].is_a?(Hash) ? current["vod_packaging"] : {}
          next current unless vod["attempt_id"] == attempt_id

          current.merge(
            "vod_packaging" => vod.merge(
              "ffmpeg_pid" => nil,
              "ffmpeg_pgid" => nil,
              "process_identity" => nil
            )
          )
        end
      rescue NotFoundError
        nil
      end

      # Treat any missing media record or changed attempt id as cancellation.
      # Workers poll this while ffmpeg runs, so stale attempts exit quickly
      # without publishing or clearing state owned by a newer attempt.
      def cancel_requested?(media_id, attempt_id)
        media = media_store.find(media_id)
        vod = media["vod_packaging"]
        return true unless vod.is_a?(Hash)
        # A changed attempt id means this worker no longer owns the packaging run.
        return true unless vod["attempt_id"] == attempt_id

        vod["cancel_requested"] || vod["state"] == "cancelled"
      rescue NotFoundError
        true
      end

      def active_owned_vod?(vod, attempt_id)
        vod.is_a?(Hash) &&
          vod["attempt_id"] == attempt_id &&
          %w[running packaging].include?(vod["state"]) &&
          !vod["cancel_requested"]
      end

      def write_master_playlist(output_root, audio_renditions:, subtitle_renditions:)
        path = File.join(output_root, "master.m3u8")
        lines = ["#EXTM3U", "#EXT-X-VERSION:3"]
        audio_renditions.each do |rendition|
          attrs = {
            "TYPE" => "AUDIO",
            "GROUP-ID" => "audio",
            "NAME" => rendition.fetch("name"),
            "DEFAULT" => rendition.fetch("default") ? "YES" : "NO",
            "AUTOSELECT" => "YES",
            "URI" => rendition.fetch("uri")
          }
          attrs["LANGUAGE"] = rendition["language"] if rendition["language"]
          lines << "#EXT-X-MEDIA:#{render_hls_attributes(attrs)}"
        end
        subtitle_renditions.each do |rendition|
          attrs = {
            "TYPE" => "SUBTITLES",
            "GROUP-ID" => "subs",
            "NAME" => rendition.fetch("name"),
            "DEFAULT" => "NO",
            "AUTOSELECT" => "YES",
            "FORCED" => "NO",
            "URI" => rendition.fetch("uri")
          }
          attrs["LANGUAGE"] = rendition["language"] if rendition["language"]
          lines << "#EXT-X-MEDIA:#{render_hls_attributes(attrs)}"
        end
        stream_attrs = { "BANDWIDTH" => "2500000" }
        stream_attrs["AUDIO"] = "audio" unless audio_renditions.empty?
        stream_attrs["SUBTITLES"] = "subs" unless subtitle_renditions.empty?
        lines << "#EXT-X-STREAM-INF:#{render_hls_attributes(stream_attrs)}"
        lines << "video/playlist.m3u8"
        File.write(path, "#{lines.join("\n")}\n")
      end

      def write_subtitle_playlist(path, vtt_uri:, duration_seconds:)
        duration = begin
          value = Float(duration_seconds)
          value.positive? && value.finite? ? value : 1.0
        rescue ArgumentError, TypeError
          1.0
        end
        FileUtils.mkdir_p(File.dirname(path))
        File.write(
          path,
          [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:#{duration.ceil}",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXTINF:#{format('%.3f', duration)},",
            vtt_uri,
            "#EXT-X-ENDLIST"
          ].join("\n") + "\n"
        )
      end

      def render_hls_attributes(attrs)
        attrs.map do |key, value|
          sanitized = sanitize_hls_attribute(value)
          if %w[BANDWIDTH TYPE DEFAULT AUTOSELECT FORCED].include?(key) || %w[YES NO].include?(sanitized)
            "#{key}=#{sanitized}"
          else
            "#{key}=\"#{escape_hls_attribute(sanitized)}\""
          end
        end.join(",")
      end

      def sanitize_hls_attribute(value)
        value.to_s.gsub(/[\u0000-\u001f\u007f]/, " ").squeeze(" ").strip
      end

      def escape_hls_attribute(value)
        value.to_s.gsub("\\", "\\\\\\").gsub('"', "\\\"")
      end

      # Replace the final VOD directory with the already validated staging
      # directory. Keeping this as a directory move means clients only see old
      # complete output or new complete output, never a half-filled publish.
      def publish_vod_directory(staging_dir, final_dir)
        FileUtils.mkdir_p(File.dirname(final_dir))
        backup = "#{final_dir}.old.#{Process.pid}"
        FileUtils.rm_rf(backup)
        FileUtils.mv(final_dir, backup) if Dir.exist?(final_dir)
        FileUtils.mv(staging_dir, final_dir)
        FileUtils.rm_rf(backup)
      end

      # Publish validated staging output and mark media ready in one locked state
      # update. If the attempt is no longer active, nothing is moved and the
      # caller treats the run as cancelled so stale workers cannot expose their
      # artifacts.
      def publish_ready(media_id, attempt_id, staging_dir:, final_dir:, audio_renditions:, subtitle_renditions:, unsupported_subtitles:)
        published = false
        updated = media_store.update(media_id) do |current|
          vod = current["vod_packaging"].is_a?(Hash) ? current["vod_packaging"] : {}
          next current unless active_owned_vod?(vod, attempt_id)

          # Move staging into the final VOD location while this attempt still owns state.
          publish_vod_directory(staging_dir, final_dir)
          published = true
          current.merge(
            "state" => "ready",
            "hls_vod_path" => File.join("vod", media_id, "master.m3u8"),
            "vod_packaging" => {
              "state" => "ready",
              "completed_at" => Clock.iso8601,
              "audio_renditions" => audio_renditions,
              "subtitle_renditions" => subtitle_renditions,
              "unsupported_subtitles" => unsupported_subtitles,
              "log_path" => relative_vod_log_path(media_id),
              "attempt_id" => attempt_id,
              "ffmpeg_pid" => nil,
              "ffmpeg_pgid" => nil,
              "process_identity" => nil
            }
          )
        end
        published ? updated : nil
      rescue NotFoundError
        nil
      end

      # Record a cooperative VOD cancellation and optionally enqueue a retry.
      # This is used when interactive playback needs worker capacity, so
      # cancellation is terminal for the current attempt but may immediately
      # requeue packaging after the preempting work has started.
      def mark_cancelled(media_id, attempt_id, requeue:)
        enqueue = false
        media = media_store.update(media_id) do |current|
          vod = current["vod_packaging"].is_a?(Hash) ? current["vod_packaging"] : {}
          next current unless vod["attempt_id"] == attempt_id

          already_requeued = vod["state"] == "cancelled" && vod["requeue_requested"]
          enqueue = requeue && !already_requeued
          current.merge(
            "state" => "downloaded",
            "hls_vod_path" => nil,
            "vod_packaging" => vod.merge(
              "state" => "cancelled",
              "cancelled_at" => vod["cancelled_at"] || Clock.iso8601,
              "cancel_requested" => false,
              "requeue_requested" => requeue || vod["requeue_requested"],
              "ffmpeg_pid" => nil,
              "ffmpeg_pgid" => nil,
              "process_identity" => nil
            )
          )
        end
        enqueue_vod(media_id) if enqueue
        media
      rescue NotFoundError
        nil
      end

      def mark_failed(media_id, attempt_id, code:, message:)
        media_store.update(media_id) do |current|
          vod = current["vod_packaging"].is_a?(Hash) ? current["vod_packaging"] : {}
          next current unless active_owned_vod?(vod, attempt_id)

          current.merge(
            "state" => "downloaded",
            "hls_vod_path" => nil,
            "vod_packaging" => vod.merge(
              "state" => "failed",
              "error" => {
                "code" => code,
                "message" => message,
                "at" => Clock.iso8601
              },
              "ffmpeg_pid" => nil,
              "ffmpeg_pgid" => nil,
              "process_identity" => nil
            )
          )
        end
      end

      def enqueue_vod(media_id)
        JobClient.enqueue("StartVodPackagingJob", args: [media_id], queue: :vod)
      end

      def vod_directory(media_id)
        File.join(storage_root, "hls", "vod", Validation.media_id!(media_id))
      end

      def staging_directory(media_id, attempt_id)
        safe_attempt = attempt_id.to_s.gsub(/[^a-f0-9]/, "")
        File.join(storage_root, "hls", "vod", ".#{Validation.media_id!(media_id)}.#{Process.pid}.#{safe_attempt}.tmp")
      end

      def vod_log_path(media_id)
        File.join(storage_root, "logs", "ffmpeg", "vod-#{Validation.media_id!(media_id)}.log")
      end

      def relative_vod_log_path(media_id)
        "ffmpeg/vod-#{Validation.media_id!(media_id)}.log"
      end

      def subtitle_playlist_uri(track)
        index = Validation.non_negative_integer!(track.fetch("index"), field: "subtitle.index")
        File.join("subtitles", "subtitle_#{index}.m3u8")
      end

      # Stop an owned ffmpeg process group with TERM, then KILL if it does not
      # exit during the grace period. The current worker process group is never
      # signalled, which protects the Sidekiq worker from malformed persisted
      # process data.
      def terminate_process_group(pgid, grace_seconds:)
        return true unless pgid && pgid.positive?
        return false if pgid == Process.getpgrp

        signal_process_group("TERM", pgid)
        return true if wait_for_process_group_exit(pgid, monotonic_time + grace_seconds)

        signal_process_group("KILL", pgid)
        wait_for_process_group_exit(pgid, monotonic_time + grace_seconds)
      end

      def signal_process_group(signal, pgid)
        Process.kill(signal, -pgid)
      rescue Errno::ESRCH
        nil
      rescue Errno::EPERM
        begin
          Process.kill(signal, pgid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end
      end

      def wait_for_process_group_exit(pgid, deadline)
        loop do
          return true unless process_group_alive?(pgid)
          return false if monotonic_time >= deadline

          sleep poll_interval_seconds
        end
      end

      def process_group_alive?(pgid)
        Process.kill(0, -pgid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Capture a best-effort process identity for diagnostics and PID reuse
      # protection. Linux start ticks are preferred, with ps start time as a
      # portable fallback when /proc is unavailable.
      def process_identity(pid)
        proc_stat = "/proc/#{pid}/stat"
        if File.readable?(proc_stat)
          # Start ticks distinguish this ffmpeg process from a later process that reuses the PID.
          stat = File.read(proc_stat)
          fields = stat.split(") ", 2).last.to_s.split
          start_ticks = fields[19]
          return "proc_start_ticks:#{start_ticks}" if start_ticks && !start_ticks.empty?
        end

        output = IO.popen(["ps", "-o", "lstart=", "-p", pid.to_s], &:read)
        value = output.to_s.strip
        value.empty? ? nil : value
      rescue StandardError
        nil
      end
    end
  end
end
