# frozen_string_literal: true

# Worker-side lifecycle for interactive HLS sessions. This file owns ffmpeg
# process groups, readiness validation, pending-to-active publication, session
# retirement, cleanup, and boot recovery for transient interactive output.
require "fileutils"
require "json"
require "set"
require "time"

require_relative "../domain"
require_relative "../errors"
require_relative "../state_store"
require_relative "ffmpeg_command_builder"
require_relative "job_client"
require_relative "subtitle_sidecar_writer"

module TorrentStreaming
  module Transcoder
    # Runs the interactive session state machine after the API has created a
    # durable session record. It deliberately separates process ownership from
    # API request handling so worker restarts can recover from JSON state.
    class SessionLifecycle
      BACKEND_LOG_PREFIX = "[backend:transcoder-lifecycle]"
      ACTIVE_STALE_STATES = %w[starting buffering hls_ready playing seeking stopping].freeze

      attr_reader :storage_root, :session_store, :media_store, :builder, :subtitle_writer,
                  :ready_timeout_seconds, :poll_interval_seconds, :stop_grace_seconds

      def initialize(storage_root: ENV.fetch("STORAGE_ROOT", "/app/storage"), builder: nil,
                     subtitle_writer: nil,
                     ready_timeout_seconds: ENV.fetch("FFMPEG_HLS_READY_TIMEOUT_SECONDS", "30").to_f,
                     poll_interval_seconds: ENV.fetch("FFMPEG_HLS_POLL_INTERVAL_SECONDS", "0.1").to_f,
                     stop_grace_seconds: ENV.fetch("FFMPEG_STOP_GRACE_SECONDS", "5").to_f)
        @storage_root = File.expand_path(storage_root)
        @session_store = SessionStore.new(root: File.join(@storage_root, "state"))
        @media_store = MediaStore.new(root: File.join(@storage_root, "state"))
        @builder = builder || FfmpegCommandBuilder.new(storage_root: @storage_root)
        @subtitle_writer = subtitle_writer || SubtitleSidecarWriter.new(storage_root: @storage_root)
        @ready_timeout_seconds = ready_timeout_seconds
        @poll_interval_seconds = poll_interval_seconds
        @stop_grace_seconds = stop_grace_seconds
      end

      # Starts ffmpeg for a session and waits until HLS is genuinely playable
      # before publishing it. A superseded pending session can be stopped first,
      # but any replaced active session is left running until this session has a
      # closed segment and can safely become the media's active playlist.
      def start_session(session_id, previous_session_id = nil)
        backend_log("start_session_enter", session_id: session_id, previous_session_id: previous_session_id)
        # This argument is the previous pending session from SessionManager; the
        # active-session retirement happens only after the new playlist is ready.
        stop_session(previous_session_id) if previous_session_id && previous_session_id != session_id

        session = session_store.find(session_id)
        return session if terminal?(session)
        return session if session.fetch("state") == "stopping"

        command = builder.interactive_command(session)
        begin
          subtitle_selection = subtitle_selection_for(session)
        rescue DomainError => e
          backend_error("subtitle_selection_failed", media_id: session.fetch("media_id"), session_id: session_id,
                                                     code: e.code, message: e.message)
          return mark_failed(session_id, code: e.code, message: e.message)
        end
        begin
          subtitle_command = subtitle_selection[:track] ? builder.interactive_subtitle_command(session, subtitle_selection.fetch(:track)) : nil
        rescue DomainError => e
          backend_error("subtitle_command_failed", media_id: session.fetch("media_id"), session_id: session_id,
                                                   code: e.code, message: e.message)
          return mark_failed(session_id, code: e.code, message: e.message)
        end
        hls_dir = builder.absolute_hls_directory(session.fetch("media_id"), session.fetch("session_id"))
        log_path = builder.absolute_log_path(session.fetch("session_id"))
        subtitle_log_path = subtitle_command ? builder.absolute_subtitle_log_path(session.fetch("session_id")) : nil
        FileUtils.mkdir_p(hls_dir)
        FileUtils.mkdir_p(File.dirname(log_path))
        FileUtils.mkdir_p(File.join(hls_dir, "subtitles")) if subtitle_command
        FileUtils.mkdir_p(File.dirname(subtitle_log_path)) if subtitle_log_path
        backend_log("ffmpeg_prepare", media_id: session.fetch("media_id"), session_id: session.fetch("session_id"),
                                      hls_dir: hls_dir, log_path: log_path, command: command,
                                      subtitle_mode: subtitle_selection.fetch(:mode),
                                      subtitle_command: subtitle_command)

        begin
          subtitle_path = subtitle_selection.fetch(:mode) == "sidecar" ? subtitle_writer.prepare!(session) : nil
          session = session_store.update(session_id) do |current|
            current.merge(
              "subtitle_mode" => subtitle_selection.fetch(:mode),
              "subtitle_path" => subtitle_path,
              "master_playlist_path" => subtitle_selection.fetch(:mode) == "hls" ? master_playlist_path_for(current) : nil,
              "subtitle_playlist_path" => subtitle_selection.fetch(:mode) == "hls" ? subtitle_playlist_path_for(current) : nil,
              "subtitle_log_path" => subtitle_selection.fetch(:mode) == "hls" ? subtitle_log_path_for(current) : nil
            )
          end
        rescue DomainError => e
          backend_error("subtitle_prepare_failed", media_id: session.fetch("media_id"), session_id: session_id,
                                                   code: e.code, message: e.message)
          return mark_failed(session_id, code: e.code, message: e.message)
        end

        pid = spawn_ffmpeg(command, log_path)
        process_identity = process_identity(pid)
        subtitle_pid = nil
        subtitle_process_identity = nil
        if subtitle_command
          subtitle_pid = spawn_ffmpeg(subtitle_command, subtitle_log_path)
          subtitle_process_identity = process_identity(subtitle_pid)
        end
        backend_log("ffmpeg_spawned", media_id: session.fetch("media_id"), session_id: session_id,
                                      pid: pid, pgid: pid, process_identity: process_identity,
                                      subtitle_pid: subtitle_pid, subtitle_pgid: subtitle_pid,
                                      subtitle_process_identity: subtitle_process_identity)
        session_after_spawn = nil

        begin
          session_after_spawn = session_store.update(session_id) do |current|
            # A stop request can arrive after spawn but before this state write;
            # keep terminal/stopping state authoritative and kill the new group.
            if terminal?(current) || current.fetch("state") == "stopping"
              current
            else
              PlaybackSession.transition(
                current,
                "buffering",
                updates: {
                  "ffmpeg_pid" => pid,
                  "ffmpeg_pgid" => pid,
                  "ffmpeg_started_at" => Clock.iso8601,
                  "ffmpeg_process_identity" => process_identity,
                  "subtitle_ffmpeg_pid" => subtitle_pid,
                  "subtitle_ffmpeg_pgid" => subtitle_pid,
                  "subtitle_ffmpeg_process_identity" => subtitle_process_identity,
                  "hls_directory" => PlaybackSession.hls_directory_for(
                    current.fetch("session_id"),
                    media_id: current.fetch("media_id")
                  ),
                  "log_path" => PlaybackSession.log_path_for(current.fetch("session_id")),
                  "error" => nil
                }
              )
            end
          end
        rescue StandardError
          terminate_process_group(pid, grace_seconds: stop_grace_seconds)
          terminate_process_group(subtitle_pid, grace_seconds: stop_grace_seconds) if subtitle_pid
          raise
        end

        if terminal?(session_after_spawn) || session_after_spawn.fetch("state") == "stopping"
          backend_log("session_terminal_after_spawn", media_id: session_after_spawn.fetch("media_id"),
                                                      session_id: session_id,
                                                      state: session_after_spawn.fetch("state"),
                                                      pid: pid)
          terminate_process_group(pid, grace_seconds: stop_grace_seconds)
          terminate_process_group(subtitle_pid, grace_seconds: stop_grace_seconds) if subtitle_pid
          return session_after_spawn
        end

        wait_for_hls_ready(session_id, pid, subtitle_pid)
      end

      # Moves a session toward stopped state and terminates any recorded process
      # groups with TERM followed by KILL if needed. The state transition is
      # idempotent so repeated stop jobs and recovery passes can share it.
      def stop_session(session_id)
        backend_log("stop_session_enter", session_id: session_id)
        return nil if session_id.nil?

        session = session_store.find(session_id)
        if session.fetch("state") == "stopped"
          backend_log("stop_session_already_stopped", media_id: session.fetch("media_id"), session_id: session_id)
          return session
        end

        stopping = session_store.update(session_id) do |current|
          case current.fetch("state")
          when "stopped", "stopping"
            current
          when "failed"
            PlaybackSession.transition(current, "stopped", updates: stopped_updates)
          else
            PlaybackSession.transition(
              current,
              "stopping",
              updates: { "stop_requested_at" => Clock.iso8601 }
            )
          end
        end

        terminated = terminate_recorded_process_group(stopping, strict_identity: false)
        subtitle_terminated = terminate_recorded_subtitle_process_group(stopping, strict_identity: false)
        backend_log("stop_session_process_termination", media_id: stopping.fetch("media_id"), session_id: session_id,
                                                        state: stopping.fetch("state"), terminated: terminated,
                                                        subtitle_terminated: subtitle_terminated,
                                                        ffmpeg_pid: stopping["ffmpeg_pid"],
                                                        ffmpeg_pgid: stopping["ffmpeg_pgid"],
                                                        subtitle_ffmpeg_pid: stopping["subtitle_ffmpeg_pid"],
                                                        subtitle_ffmpeg_pgid: stopping["subtitle_ffmpeg_pgid"])
        return stopping unless terminated && subtitle_terminated

        stopped = session_store.update(session_id) do |current|
          case current.fetch("state")
          when "stopped"
            current.merge(stopped_updates)
          when "failed"
            PlaybackSession.transition(current, "stopped", updates: stopped_updates)
          else
            current = PlaybackSession.transition(current, "stopping") unless current.fetch("state") == "stopping"
            PlaybackSession.transition(current, "stopped", updates: stopped_updates)
          end
        end
        clear_media_active_session(stopped)
        backend_log("stop_session_complete", media_id: stopped.fetch("media_id"), session_id: session_id,
                                             state: stopped.fetch("state"))
        stopped
      rescue NotFoundError => e
        backend_error("stop_session_not_found", session_id: session_id, message: e.message)
        nil
      end

      # Removes HLS files for a terminal session only. Cleanup intentionally
      # recomputes the expected directory from media/session IDs before deleting
      # so a corrupted persisted path cannot widen the delete target.
      def cleanup_session(session_id)
        session = session_store.find(session_id)
        return false unless %w[stopped failed].include?(session.fetch("state"))

        expected_directory = PlaybackSession.hls_directory_for(
          session.fetch("session_id"),
          media_id: session.fetch("media_id")
        )
        persisted_directory = session["hls_directory"]
        if persisted_directory && persisted_directory != expected_directory
          # Delete only the exact per-session directory derived from identity.
          raise ValidationError.new("hls_directory does not match session identity", code: "invalid_hls_directory")
        end

        target = safe_hls_target(expected_directory)
        FileUtils.rm_rf(target) if Dir.exist?(target)
        true
      rescue NotFoundError
        false
      end

      def cleanup_expired_sessions(ttl_seconds: ENV.fetch("HLS_SESSION_TTL_SECONDS", "3600").to_f)
        cutoff = Time.now.utc - ttl_seconds
        active_ids = active_media_session_ids
        removed = []
        session_store.all.each do |session|
          session_id = session.fetch("session_id")
          next if active_ids.include?(session_id)
          next unless %w[stopped failed].include?(session.fetch("state"))
          next unless session_expired?(session, cutoff)

          removed << session_id if cleanup_session(session_id)
        end
        removed
      end

      # Repairs interactive session state after worker boot. Any non-terminal
      # session that could have owned ffmpeg is treated as stale, its recorded
      # process groups are terminated with identity checks, and media pointers
      # are cleared when they no longer reference a live session.
      def recover_stale_sessions!
        session_store.all.each do |session|
          next unless ACTIVE_STALE_STATES.include?(session.fetch("state"))

          terminate_recorded_process_group(session, strict_identity: true)
          terminate_recorded_subtitle_process_group(session, strict_identity: true)
          mark_stale_stopped(session.fetch("session_id"))
        end
        clear_stale_media_sessions
        true
      end

      def cancel_vod_packaging(media_id, attempt_id: nil, requeue: true)
        media = media_store.find(media_id)
        vod = media["vod_packaging"]
        return media unless active_vod_packaging?(vod, attempt_id: attempt_id)

        terminate_vod_process_group(vod)
        cancelled = false
        updated = media_store.update(media.fetch("media_id")) do |current|
          current_vod = current["vod_packaging"]
          next current unless active_vod_packaging?(current_vod, attempt_id: attempt_id)

          cancelled = true
          current.merge(
            "state" => current.fetch("state") == "packaging_vod" ? "downloaded" : current.fetch("state"),
            "vod_packaging" => current_vod.merge(
              "state" => "cancelled",
              "cancel_requested" => false,
              "cancelled_at" => Clock.iso8601,
              "ffmpeg_pid" => nil,
              "ffmpeg_pgid" => nil,
              "requeue_requested" => requeue
            )
          )
        end
        enqueue_vod_requeue(media.fetch("media_id")) if requeue && cancelled
        updated
      rescue NotFoundError
        nil
      end

      private

      def backend_debug_enabled?
        ENV.fetch("BACKEND_DEBUG_STDERR", "1") != "0" && ENV["APP_ENV"] != "test"
      end

      def backend_log(event, payload = nil, level: "debug", **kwargs)
        return unless backend_debug_enabled?

        payload = payload.is_a?(Hash) ? payload.merge(kwargs) : kwargs
        record = { service: "transcoder-lifecycle", level: level, event: event }.merge(payload)
        STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate(record)}")
        STDERR.flush
      rescue StandardError => e
        STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate({ service: "transcoder-lifecycle", level: "error", event: "backend_log_failed", error_class: e.class.name, message: e.message })}")
        STDERR.flush
      end

      def backend_error(event, payload = nil, **kwargs)
        backend_log(event, payload, level: "error", **kwargs)
      end

      def subtitle_selection_for(session)
        selected = session["selected_subtitle"]
        return { mode: "none", track: nil } if selected.nil?

        track = selected_subtitle_track(session)
        unless track
          raise ValidationError.new("unknown subtitle track", code: "unknown_subtitle_track")
        end
        unless track.fetch("supported", true)
          raise ValidationError.new("unsupported subtitle track", code: track["reason"] || "unsupported_subtitle_track")
        end
        case track["source"]
        when "external"
          { mode: "sidecar", track: nil }
        when "embedded"
          unless track.key?("stream_index")
            raise ValidationError.new("embedded subtitle stream is unavailable", code: "subtitle_stream_unavailable")
          end
          { mode: "hls", track: track }
        else
          raise ValidationError.new("unsupported subtitle track", code: track["reason"] || "unsupported_subtitle_track")
        end
      end

      def selected_subtitle_track(session)
        selected = session["selected_subtitle"]
        return nil if selected.nil?

        media = media_store.find(session.fetch("media_id"))
        media.fetch("subtitles").find { |candidate| candidate["index"] == selected }
      end

      def master_playlist_path_for(session)
        File.join(
          PlaybackSession.hls_directory_for(session.fetch("session_id"), media_id: session.fetch("media_id")),
          "master.m3u8"
        )
      end

      def subtitle_playlist_path_for(session)
        selected = Validation.non_negative_integer!(session.fetch("selected_subtitle"), field: "selected_subtitle")
        File.join(
          PlaybackSession.hls_directory_for(session.fetch("session_id"), media_id: session.fetch("media_id")),
          "subtitles",
          "subtitle_#{selected}.m3u8"
        )
      end

      def subtitle_log_path_for(session)
        "ffmpeg/#{Validation.session_id!(session.fetch("session_id"))}-subtitles.log"
      end

      def spawn_ffmpeg(command, log_path)
        File.open(log_path, "ab") do |log|
          log.sync = true
          log.puts("[#{Clock.iso8601}] exec #{command.join(" ")}")
          Process.spawn(*command, out: log, err: log, pgroup: true)
        end
      end

      # Polls for a publishable HLS session while also watching the spawned
      # processes. Readiness requires playlist validation, a live primary ffmpeg
      # process, and a successful or still-running subtitle process when embedded
      # subtitles are being segmented.
      def wait_for_hls_ready(session_id, pid, subtitle_pid = nil)
        deadline = monotonic_time + ready_timeout_seconds
        subtitle_process_completed = false
        backend_log("wait_for_hls_ready_start", session_id: session_id, pid: pid,
                                                subtitle_pid: subtitle_pid, timeout_seconds: ready_timeout_seconds)
        loop do
          current = session_store.find(session_id)
          return current if terminal?(current)
          return stop_session(session_id) if current.fetch("state") == "stopping"

          if hls_ready?(current)
            sleep poll_interval_seconds
            exit_status = reap_exit_status(pid)
            if exit_status
              backend_error("ffmpeg_exited_after_playlist_probe", media_id: current.fetch("media_id"),
                                                            session_id: session_id, pid: pid,
                                                            exit_status: exit_status)
              terminate_process_group(subtitle_pid, grace_seconds: stop_grace_seconds) if subtitle_pid
              return mark_failed(session_id, code: "ffmpeg_exited_before_hls_ready",
                                         message: "ffmpeg exited before HLS became ready",
                                         exit_status: exit_status)
            end
            subtitle_exit_status = reap_exit_status(subtitle_pid) if subtitle_pid && !subtitle_process_completed
            if subtitle_exit_status && !subtitle_exit_status.zero?
              backend_error("subtitle_ffmpeg_exited_after_playlist_probe", media_id: current.fetch("media_id"),
                                                                      session_id: session_id, pid: subtitle_pid,
                                                                      exit_status: subtitle_exit_status)
              terminate_process_group(pid, grace_seconds: stop_grace_seconds)
              return mark_failed(session_id, code: "subtitle_ffmpeg_failed",
                                         message: "subtitle ffmpeg failed before HLS became ready",
                                         exit_status: subtitle_exit_status)
            end
            subtitle_process_completed = true if subtitle_exit_status&.zero?
            detach_process(pid)
            detach_process(subtitle_pid) if subtitle_pid && !subtitle_process_completed
            backend_log("hls_ready_detected", media_id: current.fetch("media_id"), session_id: session_id,
                                              playlist_path: current["playlist_path"], pid: pid,
                                              subtitle_pid: subtitle_pid)
            return mark_hls_ready(session_id)
          end

          exit_status = reap_exit_status(pid)
          if exit_status
            backend_error("ffmpeg_exited_before_hls_ready", media_id: current.fetch("media_id"),
                                                         session_id: session_id, pid: pid,
                                                         exit_status: exit_status)
            terminate_process_group(subtitle_pid, grace_seconds: stop_grace_seconds) if subtitle_pid
            return mark_failed(session_id, code: "ffmpeg_exited_before_hls_ready",
                                       message: "ffmpeg exited before HLS became ready",
                                       exit_status: exit_status)
          end

          if subtitle_pid && !subtitle_process_completed
            subtitle_exit_status = reap_exit_status(subtitle_pid)
            if subtitle_exit_status && !subtitle_exit_status.zero?
              backend_error("subtitle_ffmpeg_exited_before_hls_ready", media_id: current.fetch("media_id"),
                                                                     session_id: session_id, pid: subtitle_pid,
                                                                     exit_status: subtitle_exit_status)
              terminate_process_group(pid, grace_seconds: stop_grace_seconds)
              return mark_failed(session_id, code: "subtitle_ffmpeg_failed",
                                         message: "subtitle ffmpeg failed before HLS became ready",
                                         exit_status: subtitle_exit_status)
            end
            if subtitle_exit_status&.zero?
              subtitle_process_completed = true
              next
            end
            unless subtitle_exit_status || process_alive?(subtitle_pid)
              backend_error("subtitle_ffmpeg_not_alive_before_hls_ready", media_id: current.fetch("media_id"),
                                                                     session_id: session_id, pid: subtitle_pid)
              terminate_process_group(pid, grace_seconds: stop_grace_seconds)
              return mark_failed(session_id, code: "subtitle_ffmpeg_exited_before_hls_ready",
                                         message: "subtitle ffmpeg exited before HLS became ready")
            end
          end

          unless process_alive?(pid)
            backend_error("ffmpeg_not_alive_before_hls_ready", media_id: current.fetch("media_id"),
                                                        session_id: session_id, pid: pid)
            terminate_process_group(subtitle_pid, grace_seconds: stop_grace_seconds) if subtitle_pid && !subtitle_process_completed
            return mark_failed(session_id, code: "ffmpeg_exited_before_hls_ready",
                                       message: "ffmpeg exited before HLS became ready")
          end

          if monotonic_time >= deadline
            backend_error("hls_ready_timeout", media_id: current.fetch("media_id"), session_id: session_id,
                                               pid: pid, timeout_seconds: ready_timeout_seconds,
                                               playlist_path: current["playlist_path"],
                                               subtitle_pid: subtitle_pid,
                                               subtitle_playlist_path: current["subtitle_playlist_path"])
            terminate_process_group(pid, grace_seconds: stop_grace_seconds)
            terminate_process_group(subtitle_pid, grace_seconds: stop_grace_seconds) if subtitle_pid
            return mark_failed(session_id, code: "hls_ready_timeout",
                                       message: "ffmpeg did not produce a playlist before timeout")
          end

          sleep poll_interval_seconds
        end
      end

      # Returns true only after the media playlist references closed, existing
      # output. Embedded subtitle sessions must also have a valid subtitle HLS
      # playlist before the master playlist is written and checked.
      def hls_ready?(session)
        return false unless media_playlist_ready?(session.fetch("playlist_path"), extension: ".ts")
        return true unless session["subtitle_mode"] == "hls"
        return false unless media_playlist_ready?(session.fetch("subtitle_playlist_path"), extension: ".vtt")

        write_master_playlist(session)
        media_playlist_ready?(session.fetch("master_playlist_path"), extension: ".m3u8", require_segments: false)
      end

      def media_playlist_ready?(relative_playlist, extension:, require_segments: true)
        return false if relative_playlist.nil?

        playlist = File.join(storage_root, "hls", relative_playlist)
        directory = File.dirname(playlist)
        return false unless File.file?(playlist) && File.size?(playlist)
        return true unless require_segments

        segment_names = File.readlines(playlist, chomp: true).reject do |line|
          line.empty? || line.start_with?("#")
        end
        return false if segment_names.empty?
        # ffmpeg writes temp segments while closing files; nested or .tmp names
        # are not safe to publish to the web tier.
        return false if segment_names.any? do |name|
          name.include?("/") || name.end_with?(".tmp") || File.extname(name) != extension
        end

        first_segment = File.join(directory, segment_names.first)
        File.file?(first_segment) && File.size?(first_segment)
      rescue SystemCallError
        false
      end

      # Publishes the local master playlist for interactive subtitle HLS. The
      # path is recomputed from session identity before writing so a stale or
      # corrupted session field cannot redirect master playlist output.
      def write_master_playlist(session)
        relative = master_playlist_path_for(session)
        expected_directory = PlaybackSession.hls_directory_for(
          session.fetch("session_id"),
          media_id: session.fetch("media_id")
        )
        return nil unless relative == File.join(expected_directory, "master.m3u8")

        subtitle_playlist = session.fetch("subtitle_playlist_path")
        subtitle_uri = relative_uri_from_session_root(subtitle_playlist, expected_directory)
        track = selected_subtitle_track(session)
        target = safe_hls_target(relative)
        temp = "#{target}.tmp"
        lines = [
          "#EXTM3U",
          "#EXT-X-VERSION:3",
          "#EXT-X-MEDIA:#{render_hls_attributes(subtitle_media_attributes(track, subtitle_uri))}",
          "#EXT-X-STREAM-INF:#{render_hls_attributes({ "BANDWIDTH" => "2500000", "SUBTITLES" => "subs" })}",
          "playlist.m3u8"
        ]
        File.write(temp, "#{lines.join("\n")}\n")
        File.rename(temp, target)
        relative
      ensure
        FileUtils.rm_f(temp) if temp && File.exist?(temp)
      end

      def subtitle_media_attributes(track, subtitle_uri)
        attrs = {
          "TYPE" => "SUBTITLES",
          "GROUP-ID" => "subs",
          "NAME" => track_name(track, fallback: "Selected subtitle"),
          "DEFAULT" => "YES",
          "AUTOSELECT" => "YES",
          "FORCED" => "NO",
          "URI" => subtitle_uri
        }
        attrs["LANGUAGE"] = track["language"] if track && track["language"]
        attrs
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

      def relative_uri_from_session_root(relative, expected_directory)
        Validation.relative_path!(relative, field: "subtitle_playlist_path")
        unless relative.start_with?("#{expected_directory}/")
          raise ValidationError.new("subtitle playlist path does not match session identity", code: "invalid_path")
        end

        relative.delete_prefix("#{expected_directory}/")
      end

      def track_name(track, fallback:)
        return fallback unless track

        [track["language"], track["title"]].compact.reject(&:empty?).join(" ").then do |value|
          value.empty? ? fallback : value
        end
      end

      # Marks the session ready and publishes it to the media record in one
      # state-driven step. Publication may fail if the media pending pointer has
      # moved on to a newer session, in which case this worker leaves the stale
      # session unchanged instead of stealing active playback.
      def mark_hls_ready(session_id)
        published = false
        ready = session_store.update(session_id) do |current|
          case current.fetch("state")
          when "hls_ready", "playing"
            current
          when "stopping"
            current
          else
            ready = PlaybackSession.transition(current, "hls_ready", updates: { "error" => nil })
            if publish_hls_ready_session(ready)
              published = true
              ready
            else
              current
            end
          end
        end
        retire_replaced_active_session(ready) if published
        backend_log("hls_ready_marked", media_id: ready.fetch("media_id"), session_id: session_id,
                                        state: ready.fetch("state"), published: published,
                                        playlist_path: ready["playlist_path"])
        ready
      end

      def mark_failed(session_id, code:, message:, exit_status: nil)
        failed = session_store.update(session_id) do |current|
          next current if terminal?(current)

          PlaybackSession.transition(
            current,
            "failed",
            updates: {
              "error" => {
                "code" => code,
                "message" => message,
                "at" => Clock.iso8601
              },
              "ffmpeg_pid" => nil,
              "ffmpeg_pgid" => nil,
              "subtitle_ffmpeg_pid" => nil,
              "subtitle_ffmpeg_pgid" => nil,
              "subtitle_ffmpeg_process_identity" => nil,
              "ffmpeg_exit_status" => exit_status
            }
          )
        end
        clear_media_active_session(failed)
        backend_error("session_marked_failed", media_id: failed.fetch("media_id"), session_id: session_id,
                                               code: code, message: message, exit_status: exit_status,
                                               log_path: failed["log_path"])
        failed
      end

      def mark_stale_stopped(session_id)
        session_store.update(session_id) do |current|
          next current if current.fetch("state") == "stopped"

          record = current
          record = PlaybackSession.transition(record, "stopping") unless record.fetch("state") == "stopping"
          PlaybackSession.transition(
            record,
            "stopped",
            updates: stopped_updates.merge(
              "error" => {
                "code" => "stale_worker_boot",
                "message" => "session process state was stale at worker boot",
                "at" => Clock.iso8601
              }
            )
          )
        end
      end

      def stopped_updates
        {
          "ffmpeg_pid" => nil,
          "ffmpeg_pgid" => nil,
          "ffmpeg_process_identity" => nil,
          "subtitle_ffmpeg_pid" => nil,
          "subtitle_ffmpeg_pgid" => nil,
          "subtitle_ffmpeg_process_identity" => nil
        }
      end

      def clear_media_active_session(session)
        media_store.update(session.fetch("media_id")) do |media|
          session_id = session.fetch("session_id")
          # Only clear pointers that still reference this session; newer
          # pending/active sessions must survive stale stop or failure jobs.
          next media unless media["active_session_id"] == session_id || media["pending_session_id"] == session_id

          media.merge(
            "active_session_id" => media["active_session_id"] == session_id ? nil : media["active_session_id"],
            "hls_session_path" => media["active_session_id"] == session_id ? nil : media["hls_session_path"],
            "pending_session_id" => media["pending_session_id"] == session_id ? nil : media["pending_session_id"]
          )
        end
      rescue NotFoundError
        nil
      end

      # Swaps a ready session into the media record. Pending IDs are treated as
      # the handoff authority: if another request has already installed a newer
      # pending session, this older worker result is ignored.
      def publish_hls_ready_session(session)
        session_id = session.fetch("session_id")
        published = false
        media_store.update(session.fetch("media_id")) do |media|
          pending_session_id = media["pending_session_id"]
          active_session_id = media["active_session_id"]
          if pending_session_id
            # Prevent stale workers from publishing a session that has already
            # been replaced by a newer pending request.
            next media unless pending_session_id == session_id
          else
            next media unless active_session_id.nil? || active_session_id == session_id
          end

          published = true
          media.merge(
            "active_session_id" => session_id,
            "pending_session_id" => nil,
            "hls_session_path" => session.fetch("hls_directory"),
            "state" => media.fetch("state") == "selected" ? "streaming" : media.fetch("state")
          )
        end
        backend_log("publish_hls_ready_session", media_id: session.fetch("media_id"), session_id: session_id,
                                                 published: published)
        published
      rescue NotFoundError
        backend_error("publish_hls_ready_media_missing", media_id: session.fetch("media_id"), session_id: session_id)
        false
      end

      # Stops the active session that this ready session replaced. Delaying this
      # until after publication lets seeks and track changes keep the previous
      # playlist playable while the replacement buffers.
      def retire_replaced_active_session(session)
        previous_active_session_id = session["replaced_active_session_id"]
        return if previous_active_session_id.nil? || previous_active_session_id == session.fetch("session_id")

        stop_session(previous_active_session_id)
      end

      def clear_stale_media_sessions
        media_store.all.each do |media|
          media_store.update(media.fetch("media_id")) do |current|
            updates = {}

            active_id = current["active_session_id"]
            if active_id
              begin
                active_session = session_store.find(active_id)
                if terminal?(active_session)
                  # Boot recovery only removes media pointers after confirming
                  # the referenced session is terminal or missing.
                  updates["active_session_id"] = nil
                  updates["hls_session_path"] = nil
                end
              rescue NotFoundError
                updates["active_session_id"] = nil
                updates["hls_session_path"] = nil
              end
            end

            pending_id = current["pending_session_id"]
            if pending_id
              begin
                pending_session = session_store.find(pending_id)
                updates["pending_session_id"] = nil if terminal?(pending_session)
              rescue NotFoundError
                updates["pending_session_id"] = nil
              end
            end

            updates.empty? ? current : current.merge(updates)
          end
        rescue NotFoundError
          media_store.update(media.fetch("media_id")) do |current|
            current.merge(
              "active_session_id" => nil,
              "hls_session_path" => nil,
              "pending_session_id" => nil
            )
          end
        end
      end

      def active_media_session_ids
        media_store.all.each_with_object(Set.new) do |media, set|
          set << media["active_session_id"] if media["active_session_id"]
          set << media["pending_session_id"] if media["pending_session_id"]
        end
      end

      def session_expired?(session, cutoff)
        timestamp = session["stopped_at"] || session["updated_at"]
        Time.parse(timestamp) < cutoff
      rescue ArgumentError, TypeError
        true
      end

      # Resolves a persisted HLS directory into the storage HLS root. Cleanup
      # uses this as its final guard so only the exact interactive session tree
      # can be removed.
      def safe_hls_target(relative_directory)
        Validation.relative_path!(relative_directory, field: "hls_directory")
        base = File.expand_path(File.join(storage_root, "hls"))
        target = File.expand_path(File.join(base, relative_directory))
        unless target == base || target.start_with?("#{base}/")
          raise ValidationError.new("hls_directory escapes storage root", code: "invalid_path")
        end

        target
      end

      # Terminates a recorded primary ffmpeg group only if the stored process
      # identity still matches when strict recovery asks for that protection.
      def terminate_recorded_process_group(record, strict_identity:)
        pgid = record["ffmpeg_pgid"] || record["ffmpeg_pid"]
        return true unless pgid
        return true unless process_identity_matches?(record, strict: strict_identity)

        terminate_process_group(pgid, grace_seconds: stop_grace_seconds)
      end

      # Applies the same identity check to the optional subtitle ffmpeg process
      # group, whose fields are stored separately on the session record.
      def terminate_recorded_subtitle_process_group(record, strict_identity:)
        pgid = record["subtitle_ffmpeg_pgid"] || record["subtitle_ffmpeg_pid"]
        return true unless pgid
        subtitle_record = {
          "ffmpeg_pid" => record["subtitle_ffmpeg_pid"],
          "ffmpeg_pgid" => record["subtitle_ffmpeg_pgid"],
          "ffmpeg_process_identity" => record["subtitle_ffmpeg_process_identity"]
        }
        return true unless process_identity_matches?(subtitle_record, strict: strict_identity)

        terminate_process_group(pgid, grace_seconds: stop_grace_seconds)
      end

      def terminate_vod_process_group(vod)
        record = {
          "ffmpeg_pid" => vod["ffmpeg_pid"],
          "ffmpeg_pgid" => vod["ffmpeg_pgid"],
          "ffmpeg_process_identity" => vod["process_identity"]
        }
        terminate_recorded_process_group(record, strict_identity: false)
      end

      # Compares stored process identity with the currently running PID to lower
      # the risk of killing a reused PID during boot recovery.
      def process_identity_matches?(record, strict:)
        pid = record["ffmpeg_pid"]
        return false unless pid

        expected = record["ffmpeg_process_identity"]
        return !strict if expected.nil?

        current = process_identity(pid)
        return false if current.nil?

        current == expected
      end

      # Sends TERM and then KILL to the whole process group. The current Ruby
      # process group is never targeted, which protects the worker if corrupted
      # state points at its own group.
      def terminate_process_group(pgid, grace_seconds:)
        return true unless pgid && pgid.positive?
        # Never signal the worker's own process group from persisted state.
        return false if pgid == Process.getpgrp

        backend_log("signal_process_group", pgid: pgid, signal: "TERM", grace_seconds: grace_seconds)
        signal_process_group("TERM", pgid)
        return true if wait_for_process_group_exit(pgid, monotonic_time + grace_seconds)

        backend_error("signal_process_group_kill", pgid: pgid, signal: "KILL", grace_seconds: grace_seconds)
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

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def process_group_alive?(pgid)
        Process.kill(0, -pgid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        process_alive?(pgid)
      end

      def wait_for_process_group_exit(pgid, deadline)
        loop do
          reap_exit_status(pgid)
          return true unless process_group_alive?(pgid)
          return false if monotonic_time >= deadline

          sleep poll_interval_seconds
        end
      end

      def terminal?(session)
        %w[stopped failed].include?(session.fetch("state"))
      end

      def active_vod_packaging?(vod, attempt_id: nil)
        return false unless vod.is_a?(Hash)
        return false unless %w[running packaging cancelling].include?(vod["state"])

        vod.fetch("attempt_id", nil) == attempt_id
      end

      def enqueue_vod_requeue(media_id)
        JobClient.enqueue(
          "StartVodPackagingJob",
          args: [media_id],
          queue: :vod
        )
      end

      # Captures a lightweight process identity for later recovery. Linux start
      # ticks are preferred, with `ps` start time used as a portable fallback.
      def process_identity(pid)
        proc_stat = "/proc/#{pid}/stat"
        if File.readable?(proc_stat)
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

      def reap_exit_status(pid)
        waited = Process.waitpid2(pid, Process::WNOHANG)
        return nil unless waited

        status = waited.last
        if status.exited?
          status.exitstatus
        elsif status.signaled?
          128 + status.termsig
        else
          1
        end
      rescue Errno::ECHILD
        nil
      end

      def detach_process(pid)
        Process.detach(pid)
      rescue Errno::ECHILD
        nil
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
