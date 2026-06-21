# frozen_string_literal: true

# API-side orchestration for interactive playback sessions. It creates durable
# session records, updates media pending/active pointers, and enqueues worker
# jobs, but it does not run ffmpeg or publish HLS readiness itself.
require "json"

require_relative "../domain"
require_relative "../errors"
require_relative "../state_store"
require_relative "job_client"

module TorrentStreaming
  module Transcoder
    # Coordinates play, seek, and stop requests against JSON-backed state. The
    # manager keeps replacement sessions pending until the worker proves HLS is
    # ready, which lets the browser keep using the old active playlist during a
    # seek or track change.
    class SessionManager
      BACKEND_LOG_PREFIX = "[backend:transcoder-manager]"
      START_JOB = "StartInteractiveSessionJob"
      STOP_JOB = "StopSessionJob"
      CANCEL_VOD_JOB = "CancelVodPackagingJob"
      CANCEL_VOD_QUEUE = :vod_control
      UNCHANGED = Object.new.freeze

      attr_reader :media_store, :session_store, :job_client

      def initialize(state_root:, job_client: JobClient)
        @media_store = MediaStore.new(root: state_root)
        @session_store = SessionStore.new(root: state_root)
        @job_client = job_client
      end

      # Creates a new interactive session and makes it the media's pending
      # session. If another pending session exists, it can be stopped because it
      # was never published to clients; an active session is kept alive until the
      # replacement reaches HLS readiness in the worker.
      def start(media_id:, file_index:, start_time_seconds:, selected_audio: nil, selected_subtitle: nil)
        Validation.non_negative_number!(start_time_seconds, field: "start_time_seconds")
        backend_log("start_requested", media_id: media_id, file_index: file_index,
                                       start_time_seconds: start_time_seconds,
                                       selected_audio: selected_audio,
                                       selected_subtitle: selected_subtitle)

        session = nil
        previous_pending_session_id = nil
        replaced_active_session_id = nil
        vod_cancel_media_id = nil
        vod_cancel_attempt_id = nil

        media_store.update(media_id) do |media|
          Media.validate_session_request!(media, file_index)
          Media.validate_track_selection!(
            media,
            selected_audio: selected_audio,
            selected_subtitle: selected_subtitle
          )

          # Capture the active VOD attempt while the media record is locked so
          # the later cancel job targets the same packaging attempt.
          if active_vod_packaging?(media["vod_packaging"])
            vod_cancel_media_id = media.fetch("media_id")
            vod_cancel_attempt_id = media.fetch("vod_packaging").fetch("attempt_id", nil)
          end
          media = mark_vod_cancel_requested(media)
          # Pending sessions have no client handoff yet, so a newer request can
          # supersede them immediately.
          previous_pending_session_id = pending_session_to_replace(media)
          # The active session remains playable until the worker publishes the
          # new session as ready.
          replaced_active_session_id = active_session_to_keep_until_ready(media)
          mark_stopping(previous_pending_session_id) if previous_pending_session_id
          session = create_session(
            media_id: media.fetch("media_id"),
            file_index: file_index,
            start_time_seconds: start_time_seconds,
            selected_audio: selected_audio,
            selected_subtitle: selected_subtitle,
            supersedes_session_id: previous_pending_session_id || replaced_active_session_id,
            replaced_active_session_id: replaced_active_session_id
          )

          media.merge(
            "pending_session_id" => session.fetch("session_id"),
            "state" => next_streaming_state(media.fetch("state"))
          )
        end

        enqueue_cancel_vod(vod_cancel_media_id, vod_cancel_attempt_id) if vod_cancel_media_id
        enqueue_stop(previous_pending_session_id) if previous_pending_session_id
        enqueue_start(session.fetch("session_id"), previous_pending_session_id)
        backend_log("start_enqueued", media_id: media_id,
                                      session_id: session.fetch("session_id"),
                                      previous_pending_session_id: previous_pending_session_id,
                                      replaced_active_session_id: replaced_active_session_id,
                                      vod_cancel_media_id: vod_cancel_media_id,
                                      vod_cancel_attempt_id: vod_cancel_attempt_id)
        session_store.find(session.fetch("session_id"))
      end

      # Starts a replacement session based on an existing session. Callers may
      # change audio or subtitles, but omitted track fields intentionally inherit
      # the previous selections so seeking does not silently reset playback
      # preferences.
      def seek(session_id:, start_time_seconds:, selected_audio: UNCHANGED, selected_subtitle: UNCHANGED)
        previous = session_store.find(session_id)
        backend_log("seek_requested", previous_session_id: session_id,
                                      media_id: previous.fetch("media_id"),
                                      start_time_seconds: start_time_seconds,
                                      selected_audio_changed: !selected_audio.equal?(UNCHANGED),
                                      selected_subtitle_changed: !selected_subtitle.equal?(UNCHANGED))
        start(
          media_id: previous.fetch("media_id"),
          file_index: previous.fetch("file_index"),
          start_time_seconds: start_time_seconds,
          selected_audio: selected_audio.equal?(UNCHANGED) ? previous["selected_audio"] : selected_audio,
          selected_subtitle: selected_subtitle.equal?(UNCHANGED) ? previous["selected_subtitle"] : selected_subtitle
        )
      end

      # Requests worker-side termination for one session. The state change is
      # persisted before the stop job is queued so a restarted worker can still
      # observe and repair the stop request.
      def request_stop(session_id, cleanup: false)
        backend_log("stop_requested", session_id: session_id, cleanup: cleanup)
        session_store.find(session_id)
        session = mark_stopping(session_id)
        enqueue_stop(session_id)
        backend_log("stop_enqueued", session_id: session_id, state: session["state"])
        session_store.find(session_id)
      end

      private

      def backend_debug_enabled?
        ENV.fetch("BACKEND_DEBUG_STDERR", "1") != "0" && ENV["APP_ENV"] != "test"
      end

      def backend_log(event, payload = nil, level: "debug", **kwargs)
        return unless backend_debug_enabled?

        payload = payload.is_a?(Hash) ? payload.merge(kwargs) : kwargs
        record = { service: "transcoder-manager", level: level, event: event }.merge(payload)
        STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate(record)}")
        STDERR.flush
      rescue StandardError => e
        STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate({ service: "transcoder-manager", level: "error", event: "backend_log_failed", error_class: e.class.name, message: e.message })}")
        STDERR.flush
      end

      def backend_error(event, payload = nil, **kwargs)
        backend_log(event, payload, level: "error", **kwargs)
      end

      def create_session(media_id:, file_index:, start_time_seconds:, selected_audio:, selected_subtitle:,
                         supersedes_session_id:, replaced_active_session_id:)
        preview = PlaybackSession.build(
          media_id: media_id,
          file_index: file_index,
          start_time_seconds: start_time_seconds,
          selected_audio: selected_audio,
          selected_subtitle: selected_subtitle,
          supersedes_session_id: supersedes_session_id,
          replaced_active_session_id: replaced_active_session_id
        )
        session_id = preview.fetch("session_id")
        playlist_path = PlaybackSession.playlist_path_for(session_id, media_id: media_id)
        hls_directory = PlaybackSession.hls_directory_for(session_id, media_id: media_id)
        log_path = PlaybackSession.log_path_for(session_id)

        session_store.create(
          media_id: media_id,
          file_index: file_index,
          start_time_seconds: start_time_seconds,
          selected_audio: selected_audio,
          selected_subtitle: selected_subtitle,
          session_id: session_id,
          playlist_path: playlist_path,
          supersedes_session_id: supersedes_session_id,
          replaced_active_session_id: replaced_active_session_id
        ).then do |record|
          session_store.update(record.fetch("session_id")) do |current|
            current.merge(
              "hls_directory" => hls_directory,
              "log_path" => log_path
            )
          end
        end
      rescue DomainError => e
        backend_error("create_session_failed", media_id: media_id, file_index: file_index,
                                               code: e.code, message: e.message,
                                               supersedes_session_id: supersedes_session_id,
                                               replaced_active_session_id: replaced_active_session_id)
        raise
      end

      # Returns a non-terminal pending session that can be retired before it was
      # ever exposed as the active playlist.
      def pending_session_to_replace(media)
        session_id = media["pending_session_id"]
        return nil if session_id.nil?

        session = session_store.find(session_id)
        terminal_session?(session) ? nil : session_id
      rescue NotFoundError
        nil
      end

      # Returns the current active session that must remain available during
      # replacement startup. Lifecycle code stops it only after the new session
      # has been published as HLS-ready.
      def active_session_to_keep_until_ready(media)
        session_id = media["active_session_id"]
        return nil if session_id.nil?

        session = session_store.find(session_id)
        terminal_session?(session) ? nil : session_id
      rescue NotFoundError
        nil
      end

      def mark_stopping(session_id)
        return nil if session_id.nil?

        session_store.update(session_id) do |current|
          case current.fetch("state")
          when "stopped", "stopping"
            current
          when "failed"
            PlaybackSession.transition(current, "stopped")
          else
            PlaybackSession.transition(
              current,
              "stopping",
              updates: { "stop_requested_at" => Clock.iso8601 }
            )
          end
        end
      rescue NotFoundError
        nil
      end

      def clear_media_active_session(session)
        media_store.update(session.fetch("media_id")) do |media|
          next media unless media["active_session_id"] == session.fetch("session_id")

          media.merge(
            "active_session_id" => nil,
            "hls_session_path" => nil
          )
        end
      rescue NotFoundError
        nil
      end

      def mark_vod_cancel_requested(media)
        vod = media["vod_packaging"]
        return media unless active_vod_packaging?(vod)

        media.merge(
          "vod_packaging" => vod.merge(
            "cancel_requested" => true,
            "cancel_reason" => "interactive_preempted",
            "cancel_requested_at" => Clock.iso8601
          )
        )
      end

      def active_vod_packaging?(vod)
        return false unless vod.is_a?(Hash)
        %w[running packaging cancelling].include?(vod["state"])
      end

      def next_streaming_state(state)
        return "streaming" if Media::TRANSITIONS.fetch(state, []).include?("streaming")

        state
      end

      def terminal_session?(session)
        %w[stopped failed].include?(session.fetch("state"))
      end

      def enqueue_start(session_id, previous_session_id)
        backend_log("enqueue_start_job", session_id: session_id, previous_session_id: previous_session_id,
                                         queue: :interactive)
        job_client.enqueue(
          START_JOB,
          args: [session_id, previous_session_id],
          queue: :interactive
        )
      end

      def enqueue_stop(session_id)
        backend_log("enqueue_stop_job", session_id: session_id, queue: :interactive)
        job_client.enqueue(
          STOP_JOB,
          args: [session_id],
          queue: :interactive
        )
      end

      def enqueue_cancel_vod(media_id, attempt_id)
        backend_log("enqueue_cancel_vod_job", media_id: media_id, attempt_id: attempt_id, queue: CANCEL_VOD_QUEUE)
        job_client.enqueue(
          CANCEL_VOD_JOB,
          args: [media_id, attempt_id],
          queue: CANCEL_VOD_QUEUE
        )
      end
    end
  end
end
