# frozen_string_literal: true

# Builds the exact ffmpeg command lines used by interactive sessions and VOD
# packaging. This file exists to keep command construction pure and shared while
# lifecycle code focuses on state transitions, process ownership, and recovery.
require "fileutils"

require_relative "../validation"

module TorrentStreaming
  module Transcoder
    # Centralizes HLS command shape and output paths. Callers validate session
    # state elsewhere, then use this builder for the stable range-server input
    # URL, stream maps, segment names, and per-session log locations.
    class FfmpegCommandBuilder
      DEFAULT_RANGE_SERVER_URL = "http://range-server:7000"
      DEFAULT_RW_TIMEOUT_US = 30_000_000
      HLS_TIME_SECONDS = 2
      VOD_HLS_TIME_SECONDS = 4

      attr_reader :storage_root, :ffmpeg_bin, :range_server_url, :rw_timeout_us,
                  :vod_preset, :vod_crf, :vod_audio_bitrate

      def initialize(storage_root:, ffmpeg_bin: ENV.fetch("FFMPEG_BIN", "ffmpeg"),
                     range_server_url: ENV.fetch("RANGE_SERVER_URL", DEFAULT_RANGE_SERVER_URL),
                     rw_timeout_us: ENV.fetch("FFMPEG_RW_TIMEOUT_US", DEFAULT_RW_TIMEOUT_US).to_i,
                     vod_preset: ENV.fetch("FFMPEG_VOD_PRESET", "medium"),
                     vod_crf: ENV.fetch("FFMPEG_VOD_CRF", "20"),
                     vod_audio_bitrate: ENV.fetch("FFMPEG_VOD_AUDIO_BITRATE", "160k"))
        @storage_root = File.expand_path(storage_root)
        @ffmpeg_bin = ffmpeg_bin
        @range_server_url = range_server_url.to_s.delete_suffix("/")
        @rw_timeout_us = validate_positive_integer(rw_timeout_us, "rw_timeout_us")
        @vod_preset = vod_preset.to_s
        @vod_crf = vod_crf.to_s
        @vod_audio_bitrate = vod_audio_bitrate.to_s
      end

      # Builds the primary interactive video/audio HLS command. The generated
      # playlist is session-scoped and uses temp-file segments so lifecycle code
      # can wait for closed segments before publishing readiness.
      def interactive_command(session)
        media_id = Validation.media_id!(session.fetch("media_id"))
        session_id = Validation.session_id!(session.fetch("session_id"))
        file_index = Validation.non_negative_integer!(session.fetch("file_index"), field: "file_index")
        start_time = Validation.non_negative_number!(session.fetch("start_time_seconds"), field: "start_time_seconds")
        audio_index = session["selected_audio"] || 0
        Validation.non_negative_integer!(audio_index, field: "selected_audio")

        hls_dir = absolute_hls_directory(media_id, session_id)
        playlist_path = File.join(hls_dir, "playlist.m3u8")
        segment_pattern = File.join(hls_dir, "segment_%05d.ts")
        input_url = "#{range_server_url}/files/#{media_id}/#{file_index}"

        [
          ffmpeg_bin,
          "-hide_banner",
          "-nostdin",
          "-y",
          "-ss", format_seconds(start_time),
          "-rw_timeout", rw_timeout_us.to_s,
          "-i", input_url,
          "-map", "0:v:0",
          "-map", "0:a:#{audio_index}?",
          "-sn",
          "-c:v", "libx264",
          "-preset", "ultrafast",
          "-tune", "zerolatency",
          "-pix_fmt", "yuv420p",
          "-c:a", "aac",
          "-profile:a", "aac_low",
          "-ac", "2",
          "-ar", "48000",
          "-b:a", "160k",
          "-force_key_frames", "expr:gte(t,n_forced*#{HLS_TIME_SECONDS})",
          "-sc_threshold", "0",
          "-avoid_negative_ts", "make_zero",
          "-f", "hls",
          "-hls_time", HLS_TIME_SECONDS.to_s,
          "-hls_list_size", "0",
          "-hls_flags", "independent_segments+temp_file",
          "-hls_segment_filename", segment_pattern,
          playlist_path
        ]
      end

      # Builds the companion embedded-subtitle HLS command. External subtitles
      # are written as sidecars elsewhere; this command is only for embedded text
      # streams that must become segmented WebVTT before the master playlist is
      # safe to publish.
      def interactive_subtitle_command(session, subtitle_track)
        media_id = Validation.media_id!(session.fetch("media_id"))
        session_id = Validation.session_id!(session.fetch("session_id"))
        file_index = Validation.non_negative_integer!(session.fetch("file_index"), field: "file_index")
        start_time = Validation.non_negative_number!(session.fetch("start_time_seconds"), field: "start_time_seconds")
        stream_index = Validation.non_negative_integer!(subtitle_track.fetch("stream_index"), field: "subtitle.stream_index")
        subtitle_index = Validation.non_negative_integer!(subtitle_track.fetch("index"), field: "subtitle.index")

        hls_dir = absolute_hls_directory(media_id, session_id)
        subtitle_dir = File.join(hls_dir, "subtitles")
        playlist_path = File.join(subtitle_dir, "subtitle_#{subtitle_index}.m3u8")
        segment_pattern = File.join(subtitle_dir, "subtitle_#{subtitle_index}_%05d.vtt")
        input_url = "#{range_server_url}/files/#{media_id}/#{file_index}"

        [
          ffmpeg_bin,
          "-hide_banner",
          "-nostdin",
          "-y",
          "-ss", format_seconds(start_time),
          "-rw_timeout", rw_timeout_us.to_s,
          "-i", input_url,
          "-map", "0:#{stream_index}",
          "-vn",
          "-an",
          "-c:s", "webvtt",
          "-f", "segment",
          "-segment_time", HLS_TIME_SECONDS.to_s,
          "-segment_list_type", "m3u8",
          "-segment_list_size", "0",
          "-segment_format", "webvtt",
          "-write_empty_segments", "1",
          "-segment_list", playlist_path,
          segment_pattern
        ]
      end

      # Builds the VOD video rendition command. VOD uses a staging output root
      # supplied by the packager so completed playlists can be validated before
      # anything is published as final media.
      def vod_video_command(source_path:, output_root:)
        output = File.expand_path(output_root)
        playlist_path = File.join(output, "video", "playlist.m3u8")
        segment_pattern = File.join(output, "video", "segment_%05d.ts")

        [
          ffmpeg_bin,
          "-hide_banner",
          "-nostdin",
          "-y",
          "-i", File.expand_path(source_path),
          "-map", "0:v:0",
          "-an",
          "-sn",
          "-c:v", "libx264",
          "-preset", vod_preset,
          "-crf", vod_crf,
          "-pix_fmt", "yuv420p",
          "-force_key_frames", "expr:gte(t,n_forced*#{VOD_HLS_TIME_SECONDS})",
          "-sc_threshold", "0",
          "-f", "hls",
          "-hls_time", VOD_HLS_TIME_SECONDS.to_s,
          "-hls_playlist_type", "vod",
          "-hls_flags", "independent_segments+temp_file",
          "-hls_segment_filename", segment_pattern,
          playlist_path
        ]
      end

      # Builds one VOD audio rendition command for the selected track metadata.
      # The packager calls this repeatedly so alternate audio playlists share the
      # same staging and validation path as the video rendition.
      def vod_audio_command(source_path:, output_root:, audio_track:)
        audio_index = Validation.non_negative_integer!(audio_track.fetch("index"), field: "audio.index")
        output = File.expand_path(output_root)
        playlist_path = File.join(output, "audio_#{audio_index}", "playlist.m3u8")
        segment_pattern = File.join(output, "audio_#{audio_index}", "segment_%05d.ts")

        [
          ffmpeg_bin,
          "-hide_banner",
          "-nostdin",
          "-y",
          "-i", File.expand_path(source_path),
          "-map", "0:a:#{audio_index}",
          "-vn",
          "-sn",
          "-c:a", "aac",
          "-b:a", vod_audio_bitrate,
          "-f", "hls",
          "-hls_time", VOD_HLS_TIME_SECONDS.to_s,
          "-hls_playlist_type", "vod",
          "-hls_flags", "independent_segments+temp_file",
          "-hls_segment_filename", segment_pattern,
          playlist_path
        ]
      end

      def absolute_hls_directory(media_id, session_id)
        media = Validation.media_id!(media_id)
        session = Validation.session_id!(session_id)
        File.join(storage_root, "hls", "sessions", media, session)
      end

      def absolute_playlist_path(media_id, session_id)
        File.join(absolute_hls_directory(media_id, session_id), "playlist.m3u8")
      end

      def absolute_master_playlist_path(media_id, session_id)
        File.join(absolute_hls_directory(media_id, session_id), "master.m3u8")
      end

      def absolute_log_path(session_id)
        session = Validation.session_id!(session_id)
        File.join(storage_root, "logs", "ffmpeg", "#{session}.log")
      end

      def absolute_subtitle_log_path(session_id)
        session = Validation.session_id!(session_id)
        File.join(storage_root, "logs", "ffmpeg", "#{session}-subtitles.log")
      end

      private

      def validate_positive_integer(value, field)
        integer = Integer(value)
        raise ArgumentError, "#{field} must be positive" unless integer.positive?

        integer
      end

      def format_seconds(value)
        if value.is_a?(Integer) || value == value.to_i
          value.to_i.to_s
        else
          format("%.3f", value)
        end
      end
    end
  end
end
