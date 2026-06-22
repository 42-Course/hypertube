# frozen_string_literal: true

# This file converts trusted external subtitle files into WebVTT sidecars for
# interactive sessions and final VOD output. It exists to keep subtitle parsing,
# path containment, cue shifting, and sidecar publication under the same Ruby
# safety rules as the rest of the transcoder state machine.

require "fileutils"

require_relative "../domain"
require_relative "../errors"
require_relative "../state_store"
require_relative "../validation"

module TorrentStreaming
  module Transcoder
    # Writes subtitle sidecars only after resolving persisted source paths back
    # into the selected torrent storage tree. Interactive output shifts cue
    # times so a seeked session starts at zero, while VOD output preserves source
    # timing for the complete asset.
    class SubtitleSidecarWriter
      attr_reader :storage_root, :media_store

      def initialize(storage_root: ENV.fetch("STORAGE_ROOT", "/app/storage"))
        @storage_root = File.expand_path(storage_root)
        @media_store = MediaStore.new(root: File.join(@storage_root, "state"))
      end

      # Prepare an external subtitle sidecar for an interactive playback
      # session. The selected track must still be present and supported in media
      # metadata, then its source path is revalidated against torrent storage
      # before any file is read. Cues are shifted by the session start time so the
      # browser sees subtitles aligned to the seeked HLS timeline.
      def prepare!(session)
        selected = session["selected_subtitle"]
        return nil if selected.nil?

        media = media_store.find(session.fetch("media_id"))
        track = media.fetch("subtitles").find { |candidate| candidate["index"] == selected }
        unless track
          raise ValidationError.new("unknown subtitle track", code: "unknown_subtitle_track")
        end
        unless track.fetch("supported", true)
          raise ValidationError.new("unsupported subtitle track", code: track["reason"] || "unsupported_subtitle_track")
        end
        unless track["source"] == "external"
          raise ValidationError.new("embedded subtitle extraction is unavailable for interactive sessions",
                                    code: "embedded_subtitle_sidecar_unavailable")
        end

        source_path = safe_storage_path(track["source_path"], media_id: media.fetch("media_id"))
        cues = parse_subtitle_file(source_path)
        shifted = shift_cues(cues, session.fetch("start_time_seconds"))
        write_sidecar(session, selected, shifted)
      end

      # Prepare an external subtitle sidecar for final VOD packaging. VOD uses
      # the same source-path trust boundary as interactive playback, but it does
      # not shift cue times because the published asset starts at the beginning
      # of the completed file. When output_root is provided, the sidecar is
      # written inside the caller's staging directory.
      def prepare_vod!(media_id:, track:, output_root: nil)
        safe_media_id = Validation.media_id!(media_id)
        unless track.fetch("supported", true)
          raise ValidationError.new("unsupported subtitle track", code: track["reason"] || "unsupported_subtitle_track")
        end
        unless track["source"] == "external"
          raise ValidationError.new("embedded subtitle extraction is unavailable for VOD",
                                    code: "embedded_subtitle_sidecar_unavailable")
        end

        selected = Validation.non_negative_integer!(track.fetch("index"), field: "subtitle.index")
        source_path = safe_storage_path(track["source_path"], media_id: safe_media_id)
        cues = parse_subtitle_file(source_path)
        write_vod_sidecar(safe_media_id, selected, cues, output_root: output_root)
      end

      private

      # Resolve a persisted subtitle source path across the storage trust
      # boundary. Persisted paths are relative, but torrent contents may include
      # symlinks, so this method checks both the lexical expanded path and the
      # final realpath before returning a file that can be opened.
      def safe_storage_path(relative, media_id: nil)
        raise ValidationError.new("subtitle source is unavailable", code: "subtitle_source_unavailable") if relative.nil?

        Validation.relative_path!(relative, field: "subtitle source_path")
        safe_media_id = media_id ? Validation.media_id!(media_id) : nil
        base = safe_media_id ? strict_torrent_media_directory(safe_media_id) : File.realpath(storage_root)
        if safe_media_id
          prefix = File.join("torrents", safe_media_id, "")
          unless relative.start_with?(prefix)
            raise ValidationError.new("subtitle source escapes torrent storage", code: "invalid_path")
          end
          path = File.expand_path(File.join(base, relative.delete_prefix(prefix)))
        else
          path = File.expand_path(File.join(base, relative))
        end
        unless path.start_with?("#{base}/")
          raise ValidationError.new("subtitle source escapes torrent storage", code: "invalid_path")
        end
        raise ValidationError.new("subtitle source is unavailable", code: "subtitle_source_unavailable") unless File.file?(path)

        # Realpath closes symlink escapes after the lexical expand_path check.
        path_real = File.realpath(path)
        unless path_real.start_with?("#{base}/")
          raise ValidationError.new("subtitle source escapes torrent storage", code: "invalid_path")
        end

        path_real
      end

      def strict_torrent_media_directory(media_id)
        torrents_root = File.realpath(File.join(storage_root, "torrents"))
        base = File.expand_path(File.join(torrents_root, media_id))
        unless base.start_with?("#{torrents_root}/")
          raise ValidationError.new("subtitle source escapes torrent storage", code: "invalid_path")
        end

        # Reject a media directory that is itself a symlink outside the torrent root.
        base_real = File.realpath(base)
        unless base_real == base
          raise ValidationError.new("subtitle source escapes torrent storage", code: "invalid_path")
        end

        base
      rescue Errno::ENOENT
        raise ValidationError.new("subtitle source is unavailable", code: "subtitle_source_unavailable")
      end

      def parse_subtitle_file(path)
        case File.extname(path).downcase
        when ".srt"
          parse_srt(File.read(path, encoding: "utf-8"))
        when ".vtt"
          parse_vtt(File.read(path, encoding: "utf-8"))
        when ".ass", ".ssa"
          raise ValidationError.new("ASS/SSA subtitles are not converted in interactive v1",
                                    code: "ass_ssa_unsupported")
        else
          raise ValidationError.new("unsupported subtitle source", code: "unsupported_subtitle_source")
        end
      end

      def parse_srt(text)
        normalized = text.gsub("\r\n", "\n").gsub("\r", "\n")
        normalized.split(/\n{2,}/).filter_map do |block|
          lines = block.lines.map(&:chomp)
          lines.shift if lines.first.to_s.match?(/\A\d+\z/)
          timing = lines.shift.to_s
          match = timing.match(/\A(.+?)\s+-->\s+(.+?)(?:\s|$)/)
          next unless match

          {
            start: parse_timestamp(match[1].tr(",", ".")),
            end: parse_timestamp(match[2].tr(",", ".")),
            text: lines.join("\n")
          }
        end
      end

      def parse_vtt(text)
        normalized = text.gsub("\r\n", "\n").gsub("\r", "\n")
        normalized.sub(/\AWEBVTT.*?\n\n/m, "").split(/\n{2,}/).filter_map do |block|
          lines = block.lines.map(&:chomp)
          lines.shift unless lines.first.to_s.include?("-->")
          timing = lines.shift.to_s
          match = timing.match(/\A(.+?)\s+-->\s+(.+?)(?:\s|$)/)
          next unless match

          {
            start: parse_timestamp(match[1]),
            end: parse_timestamp(match[2]),
            text: lines.join("\n")
          }
        end
      end

      def parse_timestamp(value)
        parts = value.strip.split(":")
        seconds = parts.pop.to_f
        minutes = parts.pop.to_i
        hours = parts.pop.to_i
        (hours * 3600) + (minutes * 60) + seconds
      end

      # Move subtitle cues onto the interactive session timeline. Cues that end
      # before the seek point are dropped, and cues that overlap the seek point
      # are clamped to start at zero so the generated sidecar is immediately
      # playable with the new HLS session.
      def shift_cues(cues, offset)
        start_offset = Float(offset)
        cues.filter_map do |cue|
          next if cue.fetch(:end) <= start_offset

          {
            start: [cue.fetch(:start) - start_offset, 0.0].max,
            end: cue.fetch(:end) - start_offset,
            text: cue.fetch(:text)
          }
        end
      end

      def write_sidecar(session, selected, cues)
        relative = File.join(
          PlaybackSession.hls_directory_for(session.fetch("session_id"), media_id: session.fetch("media_id")),
          "subtitle_#{selected}.vtt"
        )
        target = safe_hls_path(relative)
        FileUtils.mkdir_p(File.dirname(target))
        temp = "#{target}.tmp"
        File.write(temp, render_vtt(cues))
        File.rename(temp, target)
        relative
      ensure
        FileUtils.rm_f(temp) if temp && File.exist?(temp)
      end

      def write_vod_sidecar(media_id, selected, cues, output_root:)
        filename = File.join("subtitles", "subtitle_#{selected}.vtt")
        target =
          if output_root
            File.expand_path(File.join(output_root, filename))
          else
            safe_hls_path(File.join("vod", media_id, filename))
          end
        FileUtils.mkdir_p(File.dirname(target))
        temp = "#{target}.tmp"
        File.write(temp, render_vtt(cues))
        File.rename(temp, target)
        output_root ? filename : File.join("vod", media_id, filename)
      ensure
        FileUtils.rm_f(temp) if temp && File.exist?(temp)
      end

      def render_vtt(cues)
        body = cues.map.with_index(1) do |cue, index|
          [
            index.to_s,
            "#{format_timestamp(cue.fetch(:start))} --> #{format_timestamp(cue.fetch(:end))}",
            cue.fetch(:text)
          ].join("\n")
        end
        "WEBVTT\n\n#{body.join("\n\n")}\n"
      end

      def format_timestamp(seconds)
        total_ms = (seconds * 1000).round
        hours = total_ms / 3_600_000
        total_ms %= 3_600_000
        minutes = total_ms / 60_000
        total_ms %= 60_000
        secs = total_ms / 1000
        ms = total_ms % 1000
        format("%02d:%02d:%02d.%03d", hours, minutes, secs, ms)
      end

      def safe_hls_path(relative)
        Validation.relative_path!(relative, field: "subtitle_path")
        base = File.expand_path(File.join(storage_root, "hls"))
        target = File.expand_path(File.join(base, relative))
        unless target.start_with?("#{base}/")
          raise ValidationError.new("subtitle sidecar escapes HLS root", code: "invalid_path")
        end

        target
      end
    end
  end
end
