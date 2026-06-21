# frozen_string_literal: true

# Defines the versioned media and playback-session records persisted under
# storage/state. These validators and transition tables are the Ruby services'
# shared state contract, so changes here need matching migrations and tests.
require "securerandom"
require "time"

require_relative "errors"
require_relative "magnet"
require_relative "validation"

module TorrentStreaming
  module Clock
    module_function

    def iso8601
      Time.now.utc.iso8601
    end
  end

  # Media state is persisted as JSON and shared across API and worker processes.
  # The state names and transitions below describe the durable lifecycle, not
  # just in-memory behavior.
  module Media
    STATES = %w[
      queued metadata waiting_file_selection selected downloading streaming
      streamable downloaded packaging_vod ready failed
    ].freeze

    TRANSITIONS = {
      "queued" => %w[metadata failed],
      "metadata" => %w[waiting_file_selection downloading failed],
      "waiting_file_selection" => %w[selected failed],
      "selected" => %w[downloading streaming failed],
      "downloading" => %w[streaming streamable downloaded failed],
      "streaming" => %w[streamable downloading failed],
      "streamable" => %w[streaming downloaded failed],
      "downloaded" => %w[packaging_vod ready failed],
      "packaging_vod" => %w[ready downloaded failed],
      "ready" => %w[packaging_vod failed],
      "failed" => %w[metadata queued]
    }.freeze
    SESSION_STARTABLE_STATES = %w[selected downloading streaming streamable downloaded packaging_vod ready].freeze
    REQUIRED_FIELDS = %w[
      schema_version id media_id magnet info_hash name files selected_file_index
      video_progress duration_seconds audio_tracks subtitles active_session_id state
      errors hls_session_path hls_vod_path created_at updated_at
    ].freeze
    OPTIONAL_SESSION_ID_FIELDS = %w[pending_session_id].freeze

    module_function

    # Builds the first valid media record from the canonical magnet identity.
    # Validation here keeps new records subject to the same persisted schema
    # that StateStore enforces when records are reread from disk.
    def build_from_magnet(magnet, state: "metadata", now: Clock.iso8601)
      normalized = Magnet.normalize(magnet)
      media_id = Magnet.media_id(normalized)
      record = {
        "schema_version" => 1,
        "id" => media_id,
        "media_id" => media_id,
        "magnet" => normalized,
        "info_hash" => nil,
        "name" => nil,
        "files" => [],
        "selected_file_index" => nil,
        "video_progress" => {
          "bytes_downloaded" => 0,
          "bytes_total" => 0
        },
        "duration_seconds" => nil,
        "audio_tracks" => [],
        "subtitles" => [],
        "active_session_id" => nil,
        "state" => state,
        "errors" => [],
        "hls_session_path" => nil,
        "hls_vod_path" => nil,
        "created_at" => now,
        "updated_at" => now
      }
      validate!(record)
      record
    end

    # Applies only legal lifecycle moves and returns a new validated record for
    # callers to persist atomically through StateStore.
    def transition(record, to_state, updates: {}, now: Clock.iso8601)
      from_state = record.fetch("state")
      unless TRANSITIONS.fetch(from_state, []).include?(to_state)
        raise InvalidTransitionError, "cannot transition media from #{from_state} to #{to_state}"
      end

      next_record = deep_copy(record).merge(updates)
      next_record["state"] = to_state
      next_record["updated_at"] = now
      validate!(next_record)
      next_record
    end

    # Validates the stored media schema, IDs, selected-file contract, and
    # persisted relative paths before any caller trusts the record.
    def validate!(record)
      raise ValidationError.new("media record must be an object", code: "invalid_record") unless record.is_a?(Hash)

      missing = REQUIRED_FIELDS.reject { |field| record.key?(field) }
      unless missing.empty?
        raise ValidationError.new("missing media fields: #{missing.join(", ")}", code: "missing_fields")
      end
      raise SchemaVersionError unless record["schema_version"] == 1

      media_id = Validation.media_id!(record["media_id"] || record["id"])
      raise InvalidIdError, "media id mismatch" unless record["id"] == media_id && record["media_id"] == media_id
      raise ValidationError.new("invalid media state", code: "invalid_state") unless STATES.include?(record["state"])

      files = record.fetch("files")
      raise ValidationError.new("files must be an array", code: "invalid_files") unless files.is_a?(Array)
      files.each { |file| validate_file!(file) }
      %w[audio_tracks subtitles].each do |field|
        raise ValidationError.new("#{field} must be an array", code: "invalid_tracks") unless record.fetch(field).is_a?(Array)
      end

      selected = record["selected_file_index"]
      if SESSION_STARTABLE_STATES.include?(record["state"])
        validate_selected_file!(files, selected)
      elsif !selected.nil?
        Validation.non_negative_integer!(selected, field: "selected_file_index")
      end

      active_session_id = record["active_session_id"]
      Validation.session_id!(active_session_id) unless active_session_id.nil?
      OPTIONAL_SESSION_ID_FIELDS.each do |field|
        value = record[field]
        Validation.session_id!(value) unless value.nil?
      end

      %w[hls_session_path hls_vod_path].each do |field|
        value = record[field]
        Validation.relative_path!(value, field: field) unless value.nil?
      end

      record
    end

    # Play and seek requests may only target the selected torrent file. This
    # keeps transient API input aligned with the persisted media selection.
    def validate_session_request!(record, file_index)
      validate!(record)
      unless SESSION_STARTABLE_STATES.include?(record.fetch("state"))
        raise ValidationError.new("media is not ready for session creation", code: "media_not_session_startable")
      end

      requested_index = Validation.non_negative_integer!(file_index, field: "file_index")
      validate_selected_file!(record.fetch("files"), record["selected_file_index"])
      unless requested_index == record.fetch("selected_file_index")
        raise ValidationError.new("file_index must match selected_file_index", code: "file_index_mismatch")
      end

      record
    end

    # Track choices are validated against the metadata stored on the media
    # record so workers do not need to reinterpret client-supplied indexes.
    def validate_track_selection!(record, selected_audio:, selected_subtitle:)
      validate!(record)
      validate_audio_selection!(record.fetch("audio_tracks"), selected_audio)
      validate_subtitle_selection!(record.fetch("subtitles"), selected_subtitle)
      record
    end

    # File paths in media records stay relative; serving and packaging code
    # resolve them under trusted roots later.
    def validate_file!(file)
      raise ValidationError.new("file must be an object", code: "invalid_file") unless file.is_a?(Hash)

      Validation.non_negative_integer!(file["index"], field: "file.index")
      Validation.relative_path!(file["path"], field: "file.path") if file.key?("path")
      file
    end
    private_class_method :validate_file!

    def validate_selected_file!(files, selected)
      raise ValidationError.new("files must not be empty for selected media", code: "missing_files") if files.empty?

      Validation.non_negative_integer!(selected, field: "selected_file_index")
      return if files.any? { |file| file["index"] == selected }

      raise ValidationError.new("selected_file_index is not present in files", code: "unknown_file_index")
    end
    private_class_method :validate_selected_file!

    def validate_audio_selection!(tracks, selected)
      return if selected.nil?

      index = Validation.non_negative_integer!(selected, field: "selected_audio")
      raise ValidationError.new("unknown audio track", code: "unknown_audio_track") if tracks.empty? && index.positive?
      return if tracks.empty?
      return if tracks.any? { |track| track.is_a?(Hash) && track["index"] == index }

      raise ValidationError.new("unknown audio track", code: "unknown_audio_track")
    end
    private_class_method :validate_audio_selection!

    def validate_subtitle_selection!(tracks, selected)
      return if selected.nil?

      index = Validation.non_negative_integer!(selected, field: "selected_subtitle")
      raise ValidationError.new("unknown subtitle track", code: "unknown_subtitle_track") if tracks.empty?

      track = tracks.find { |candidate| candidate.is_a?(Hash) && candidate["index"] == index }
      raise ValidationError.new("unknown subtitle track", code: "unknown_subtitle_track") unless track
      return unless track.key?("supported") && !track["supported"]

      raise ValidationError.new("unsupported subtitle track",
                                code: track["reason"] || "unsupported_subtitle_track")
    end
    private_class_method :validate_subtitle_selection!

    def deep_copy(record)
      Marshal.load(Marshal.dump(record))
    end
    private_class_method :deep_copy
  end

  # Playback sessions are short-lived records, but their paths and process
  # identities are persisted so workers can recover and stop owned ffmpeg work.
  module PlaybackSession
    STATES = %w[starting buffering hls_ready playing seeking stopping stopped failed].freeze

    TRANSITIONS = {
      "starting" => %w[buffering hls_ready stopping failed],
      "buffering" => %w[hls_ready stopping failed],
      "hls_ready" => %w[playing seeking stopping failed],
      "playing" => %w[seeking stopping failed],
      "seeking" => %w[buffering hls_ready stopping failed],
      "stopping" => %w[stopped failed],
      "stopped" => [],
      "failed" => %w[stopped]
    }.freeze
    REQUIRED_FIELDS = %w[
      schema_version id session_id media_id file_index start_time_seconds selected_audio
      selected_subtitle state playlist_path ffmpeg_pid started_at updated_at stopped_at error
    ].freeze
    OPTIONAL_RELATIVE_PATH_FIELDS = %w[
      hls_directory log_path master_playlist_path subtitle_path subtitle_playlist_path subtitle_log_path
    ].freeze
    OPTIONAL_INTEGER_FIELDS = %w[ffmpeg_pgid ffmpeg_exit_status subtitle_ffmpeg_pid subtitle_ffmpeg_pgid].freeze
    OPTIONAL_STRING_FIELDS = %w[ffmpeg_process_identity subtitle_ffmpeg_process_identity].freeze
    SUBTITLE_MODES = %w[none sidecar hls].freeze
    OPTIONAL_SESSION_ID_FIELDS = %w[supersedes_session_id replaced_active_session_id].freeze

    module_function

    # Creates a versioned session record. Derived paths are filled by callers
    # from validated IDs so HLS output and logs remain session-scoped.
    def build(media_id:, file_index:, start_time_seconds:, selected_audio: nil, selected_subtitle: nil,
              session_id: nil, playlist_path: nil, supersedes_session_id: nil,
              replaced_active_session_id: nil, now: Clock.iso8601)
      id = session_id || "sess_#{SecureRandom.hex(16)}"
      record = {
        "schema_version" => 1,
        "id" => id,
        "session_id" => id,
        "media_id" => media_id,
        "file_index" => file_index,
        "start_time_seconds" => start_time_seconds,
        "selected_audio" => selected_audio,
        "selected_subtitle" => selected_subtitle,
        "state" => "starting",
        "playlist_path" => playlist_path,
        "ffmpeg_pid" => nil,
        "ffmpeg_pgid" => nil,
        "ffmpeg_started_at" => nil,
        "ffmpeg_process_identity" => nil,
        "ffmpeg_exit_status" => nil,
        "subtitle_mode" => "none",
        "master_playlist_path" => nil,
        "subtitle_playlist_path" => nil,
        "subtitle_ffmpeg_pid" => nil,
        "subtitle_ffmpeg_pgid" => nil,
        "subtitle_ffmpeg_process_identity" => nil,
        "subtitle_log_path" => nil,
        "hls_directory" => nil,
        "log_path" => nil,
        "supersedes_session_id" => supersedes_session_id,
        "replaced_active_session_id" => replaced_active_session_id,
        "started_at" => now,
        "updated_at" => now,
        "stopped_at" => nil,
        "error" => nil
      }
      validate!(record)
      record
    end

    # Session transitions are intentionally narrow because workers may recover
    # from persisted state after process or host restarts.
    def transition(record, to_state, updates: {}, now: Clock.iso8601)
      from_state = record.fetch("state")
      unless TRANSITIONS.fetch(from_state, []).include?(to_state)
        raise InvalidTransitionError, "cannot transition session from #{from_state} to #{to_state}"
      end

      next_record = deep_copy(record).merge(updates)
      next_record["state"] = to_state
      next_record["updated_at"] = now
      next_record["stopped_at"] ||= now if to_state == "stopped"
      validate!(next_record)
      next_record
    end

    # Builds the public playlist path from IDs that have already passed the
    # persisted ID validators.
    def playlist_path_for(session_id, media_id:)
      id = Validation.session_id!(session_id)
      media = Validation.media_id!(media_id)
      "sessions/#{media}/#{id}/playlist.m3u8"
    end

    def hls_directory_for(session_id, media_id:)
      File.dirname(playlist_path_for(session_id, media_id: media_id))
    end

    # Session log paths derive from validated session IDs and stay relative to
    # the shared storage log root.
    def log_path_for(session_id)
      id = Validation.session_id!(session_id)
      "ffmpeg/#{id}.log"
    end

    # Validates the session record shape, relative path fields, process
    # identity fields, and replacement links before state is trusted.
    def validate!(record)
      raise ValidationError.new("session record must be an object", code: "invalid_record") unless record.is_a?(Hash)

      missing = REQUIRED_FIELDS.reject { |field| record.key?(field) }
      unless missing.empty?
        raise ValidationError.new("missing session fields: #{missing.join(", ")}", code: "missing_fields")
      end
      raise SchemaVersionError unless record["schema_version"] == 1

      session_id = Validation.session_id!(record["session_id"] || record["id"])
      raise InvalidIdError, "session id mismatch" unless record["id"] == session_id && record["session_id"] == session_id
      Validation.media_id!(record["media_id"])
      Validation.non_negative_integer!(record["file_index"], field: "file_index")
      Validation.non_negative_number!(record["start_time_seconds"], field: "start_time_seconds")
      %w[selected_audio selected_subtitle].each do |field|
        value = record[field]
        Validation.non_negative_integer!(value, field: field) unless value.nil?
      end
      raise ValidationError.new("invalid session state", code: "invalid_state") unless STATES.include?(record["state"])

      playlist_path = record["playlist_path"]
      if record["state"] == "hls_ready" && playlist_path.nil?
        raise ValidationError.new("hls_ready session requires playlist_path", code: "missing_playlist")
      end
      Validation.relative_path!(playlist_path, field: "playlist_path") unless playlist_path.nil?

      subtitle_mode = record["subtitle_mode"] || "none"
      unless SUBTITLE_MODES.include?(subtitle_mode)
        raise ValidationError.new("invalid subtitle_mode", code: "invalid_subtitle_mode")
      end

      OPTIONAL_RELATIVE_PATH_FIELDS.each do |field|
        value = record[field]
        Validation.relative_path!(value, field: field) unless value.nil?
      end

      pid = record["ffmpeg_pid"]
      Validation.non_negative_integer!(pid, field: "ffmpeg_pid") unless pid.nil?
      OPTIONAL_INTEGER_FIELDS.each do |field|
        value = record[field]
        Validation.non_negative_integer!(value, field: field) unless value.nil?
      end
      OPTIONAL_STRING_FIELDS.each do |field|
        value = record[field]
        unless value.nil? || (value.is_a?(String) && !value.empty?)
          raise ValidationError.new("#{field} must be a non-empty string", code: "invalid_string")
        end
      end
      OPTIONAL_SESSION_ID_FIELDS.each do |field|
        value = record[field]
        Validation.session_id!(value) unless value.nil?
      end

      record
    end

    def deep_copy(record)
      Marshal.load(Marshal.dump(record))
    end
    private_class_method :deep_copy
  end
end
