# frozen_string_literal: true

# Presentation helpers for the web service.
# This file converts internal media/session records into browser-safe payloads and user-facing status messages.

require "json"

# WebUI is the boundary between durable application state and ERB/player.js.
# It strips untrusted path details, chooses public URLs, and keeps pending
# playback sessions separate from playlists that are actually safe to attach.
module WebUI
  module_function

  MEDIA_TERMINAL_STATES = %w[packaging_vod ready].freeze
  PLAYABLE_SESSION_STATES = %w[hls_ready playing].freeze

  # Merges the range-server's torrent snapshot into the web-owned media record.
  # The range-server owns torrent progress, but the Ruby state file remains the
  # browser-facing source for selected files, playback sessions, and VOD state.
  def sync_media!(media_store:, media_id:, range_server_client:)
    torrent = range_server_client.fetch_torrent(media_id)
    files_payload = range_server_client.fetch_files(media_id)

    media_store.update(media_id) do |current|
      files = normalized_files(files_payload["files"])
      selected_file_index = torrent["selected_file_index"]
      torrent_progress = normalized_progress(torrent["progress"])
      progress = selected_file_progress(files, selected_file_index) ||
                 selected_status_progress(torrent["selected_file_progress"]) ||
                 torrent_progress
      next_state = derive_media_state(current: current, torrent: torrent, files: files, progress: progress)
      errors = public_media_errors(torrent["error"])

      current.merge(
        "info_hash" => torrent["info_hash"],
        "name" => torrent["name"],
        "files" => files,
        "selected_file_index" => selected_file_index,
        "video_progress" => progress,
        "state" => next_state,
        "errors" => errors
      )
    end
  end

  # Main browser contract consumed by player.js and the ERB bootstrap script.
  # It exposes only presentation-safe media, playback, warning, and error data.
  def media_payload(media, session_store:)
    active = media["active_session_id"] ? safe_find_session(session_store, media["active_session_id"]) : nil
    pending = media["pending_session_id"] ? safe_find_session(session_store, media["pending_session_id"]) : nil
    current = pending || active

    {
      media_id: media.fetch("media_id"),
      name: media["name"],
      state: media.fetch("state"),
      info_hash: media["info_hash"],
      metadata_probe: media["metadata_probe"],
      duration_seconds: media["duration_seconds"],
      selected_file_index: media["selected_file_index"],
      active_session_id: active&.fetch("session_id"),
      pending_session_id: pending&.fetch("session_id"),
      current_session_id: current&.fetch("session_id"),
      video_progress: media.fetch("video_progress"),
      files: public_files(media.fetch("files"), selected_file_index: media["selected_file_index"]),
      audio_tracks: public_tracks(media.fetch("audio_tracks"), kind: :audio),
      subtitles: public_tracks(media.fetch("subtitles"), kind: :subtitle),
      playback: playback_payload(media, active_session: active, pending_session: pending),
      vod: vod_payload(media),
      warnings: user_warnings(media),
      errors: user_errors(media, active_session: active, pending_session: pending)
    }
  end

  # Public session contract. Playlist URLs are withheld until the session has a playable HLS state.
  def session_payload(session, media_id:)
    ready = PLAYABLE_SESSION_STATES.include?(session.fetch("state"))
    {
      session_id: session.fetch("session_id"),
      media_id: media_id,
      state: session.fetch("state"),
      file_index: session.fetch("file_index"),
      start_time_seconds: session.fetch("start_time_seconds"),
      selected_audio: session["selected_audio"],
      selected_subtitle: session["selected_subtitle"],
      error: session["error"],
      subtitle_mode: subtitle_mode(session),
      playlist_url: ready ? session_playlist_url(session, media_id: media_id) : nil,
      subtitle_url: ready && subtitle_mode(session) == "sidecar" && session["subtitle_path"] ? "/media/#{media_id}/sessions/#{session.fetch("session_id")}/hls/#{File.basename(session.fetch("subtitle_path"))}" : nil
    }
  end

  # Returns only the currently active playlist. Pending replacement sessions are
  # intentionally hidden until the worker has published a ready playlist, which
  # prevents the browser from attaching half-built HLS output after rapid seeks.
  def active_playlist_payload(media, session_store:)
    active = media["active_session_id"] ? safe_find_session(session_store, media["active_session_id"]) : nil
    return { media_id: media.fetch("media_id"), session_id: nil, session_start_time_seconds: nil, playlist_url: nil, subtitle_url: nil, subtitle_mode: "none" } unless active

    payload = session_payload(active, media_id: media.fetch("media_id"))
    {
      media_id: media.fetch("media_id"),
      session_id: payload.fetch(:session_id),
      session_start_time_seconds: payload.fetch(:start_time_seconds),
      playlist_url: payload.fetch(:playlist_url),
      subtitle_url: payload.fetch(:subtitle_url),
      subtitle_mode: payload.fetch(:subtitle_mode)
    }
  end

  def vod_payload(media)
    vod = media["vod_packaging"].is_a?(Hash) ? media["vod_packaging"] : {}
    ready = media.fetch("state") == "ready" && media["hls_vod_path"]
    {
      state: vod["state"],
      ready: !!ready,
      playlist_url: ready ? "/media/#{media.fetch("media_id")}/vod/master.m3u8" : nil,
      audio_renditions: Array(vod["audio_renditions"]).map { |track| public_vod_rendition(track) },
      subtitle_renditions: Array(vod["subtitle_renditions"]).map { |track| public_vod_rendition(track) },
      unsupported_subtitles: Array(vod["unsupported_subtitles"]),
      error: public_vod_error(vod["error"])
    }
  end

  # Escapes JSON for embedding inside a script tag without changing the payload shape.
  def json_script(value)
    JSON.generate(value)
        .gsub("<", "\\u003c")
        .gsub(">", "\\u003e")
        .gsub("&", "\\u0026")
        .gsub("\u2028", "\\u2028")
        .gsub("\u2029", "\\u2029")
  end

  def clamp_target(target_seconds, duration_seconds)
    target = Float(target_seconds)
    unless target.finite?
      raise TorrentStreaming::ValidationError.new("target_seconds must be finite", code: "invalid_number")
    end
    target = 0.0 if target.negative?
    return target if duration_seconds.nil?

    duration = Float(duration_seconds)
    duration.finite? ? [target, duration].min : target
  rescue ArgumentError, TypeError
    raise TorrentStreaming::ValidationError.new("target_seconds must be numeric", code: "invalid_number")
  end

  def session_for_seek(media)
    media["pending_session_id"] || media["active_session_id"]
  end

  def waiting_for_metadata?(media)
    media.fetch("state") == "metadata"
  end

  def no_video_files?(media)
    media.fetch("files").none? { |file| file["kind"] == "video" && file["supported"] != false }
  end

  def unsupported_subtitles?(media)
    media.fetch("subtitles").any? { |track| track["supported"] == false }
  end

  # Track metadata may come from ffprobe or torrent filenames, so labels are rebuilt for display.
  def public_tracks(tracks, kind:)
    tracks.map do |track|
      item = {
        index: track["index"],
        codec: track["codec"],
        supported: track.fetch("supported", true),
        reason: track["reason"]
      }
      item[:language] = track["language"] if track.key?("language")
      item[:title] = track["title"] if track.key?("title")
      item[:source] = track["source"] if kind == :subtitle && track.key?("source")
      item[:label] = track_label(track, kind: kind)
      item
    end
  end

  # File paths from torrent metadata are untrusted; expose only a basename for the UI.
  def public_files(files, selected_file_index:)
    files.map do |file|
      {
        index: file["index"],
        display_name: safe_metadata_basename(file["display_name"] || file["path"]),
        size: file["size"],
        kind: file["kind"],
        supported: file.fetch("supported", true),
        progress: file["progress"] || {},
        selected: file["index"] == selected_file_index
      }
    end
  end

  # Playback payload keeps two ideas separate: selected track choices may come
  # from a pending session, but playlist URLs come only from a playable active
  # session. That lets the UI show current intent while still attaching safe HLS.
  def playback_payload(media, active_session:, pending_session:)
    active_session ||= nil
    selected_session = pending_session || active_session
    playable_active = active_session if active_session && PLAYABLE_SESSION_STATES.include?(active_session.fetch("state"))
    {
      active_session_id: playable_active&.fetch("session_id"),
      pending_session_id: pending_session&.fetch("session_id"),
      session_start_time_seconds: playable_active&.fetch("start_time_seconds"),
      playlist_url: playable_active ? session_playlist_url(playable_active, media_id: media.fetch("media_id")) : nil,
      subtitle_url: playable_active && subtitle_mode(playable_active) == "sidecar" && playable_active["subtitle_path"] ? "/media/#{media.fetch("media_id")}/sessions/#{playable_active.fetch("session_id")}/hls/#{File.basename(playable_active.fetch("subtitle_path"))}" : nil,
      subtitle_mode: playable_active ? subtitle_mode(playable_active) : "none",
      selected_audio: selected_session&.fetch("selected_audio"),
      selected_subtitle: selected_session&.fetch("selected_subtitle")
    }
  end

  def subtitle_mode(session)
    mode = session["subtitle_mode"]
    return mode if %w[none sidecar hls].include?(mode)
    return "sidecar" if session["subtitle_path"]

    "none"
  end

  def session_playlist_url(session, media_id:)
    filename = subtitle_mode(session) == "hls" ? "master.m3u8" : "playlist.m3u8"
    "/media/#{media_id}/sessions/#{session.fetch("session_id")}/hls/#{filename}"
  end

  def user_errors(media, active_session:, pending_session:)
    errors = []
    if waiting_for_metadata?(media)
      errors << {
        code: "metadata_unavailable",
        title: "Metadata unavailable",
        message: "Torrent metadata is still loading.",
        action: "Wait for metadata or retry the magnet."
      }
    end

    if media.fetch("state") == "waiting_file_selection" && no_video_files?(media)
      errors << {
        code: "no_video_files",
        title: "No video files",
        message: "The torrent metadata does not expose a supported video file.",
        action: "Choose another magnet."
      }
    end

    [pending_session, active_session].compact.each do |session|
      next unless session["error"].is_a?(Hash)

      errors << error_from_code(session["error"]["code"])
    end

    vod = media["vod_packaging"]
    if vod.is_a?(Hash) && vod["error"].is_a?(Hash)
      errors << error_from_code(vod["error"]["code"])
    end

    if unsupported_subtitles?(media)
      media.fetch("subtitles").each do |track|
        next unless track["supported"] == false

        errors << error_from_code(track["reason"], fallback_message: track_label(track, kind: :subtitle))
      end
    end

    Array(media["errors"]).each do |error|
      next unless error.is_a?(Hash)

      errors << error_from_code(error["code"] || error["error"])
    end

    deduplicate_errors(errors)
  end

  def user_warnings(media)
    warnings = []
    probe = media["metadata_probe"]
    if probe.is_a?(Hash)
      case probe["status"]
      when "pending"
        warnings << {
          code: "metadata_probe_pending",
          title: "Metadata retrying",
          message: "Duration and track details are being retried now that more torrent data is available.",
          action: "Playback can continue; duration and track choices will update automatically when probing succeeds."
        }
      when "degraded"
        warnings << warning_from_probe_code(probe["error"])
      end
    end

    deduplicate_errors(warnings)
  end

  def warning_from_probe_code(code)
    case code
    when "ffprobe_timeout"
      {
        code: "metadata_probe_slow",
        title: "Metadata still loading",
        message: "Duration and track details are not available yet because the torrent data needed for probing is still arriving.",
        action: "Playback can continue; the app will retry metadata probing when more data arrives."
      }
    when "ffprobe_failed", "invalid_ffprobe_result"
      {
        code: "metadata_probe_degraded",
        title: "Metadata limited",
        message: "Duration and track details could not be read from the current file data.",
        action: "Playback can still start with default tracks; retry after more data is available."
      }
    else
      {
        code: "metadata_probe_degraded",
        title: "Metadata limited",
        message: "Duration and track details are temporarily unavailable.",
        action: "Playback can still start; retry after more data is available."
      }
    end
  end

  def error_from_code(code, fallback_message: nil)
    case code
    when "ffprobe_timeout", "hls_ready_timeout", "piece_timeout"
      {
        code: "peers_slow",
        title: "Peers are slow",
        message: "The requested area is not arriving quickly enough.",
        action: "Wait a few seconds, then retry play or seek."
      }
    when "ffprobe_failed", "ffmpeg_exited_before_hls_ready"
      {
        code: "unsupported_format",
        title: "Unsupported format",
        message: "The current file could not be prepared for interactive playback.",
        action: "Try another file from the torrent."
      }
    when "source_unavailable", "vod_metadata_unavailable", "vod_ffmpeg_failed",
         "vod_packaging_failed", "vod_hls_invalid", "invalid_path"
      {
        code: "vod_unavailable",
        title: "Final VOD unavailable",
        message: "The final VOD could not be prepared from the completed file.",
        action: "Retry after the source file and metadata are available."
      }
    when "unsupported_image_subtitle", "ass_ssa_unsupported",
         "embedded_subtitle_sidecar_unavailable", "subtitle_source_unavailable",
         "subtitle_stream_unavailable", "subtitle_ffmpeg_failed",
         "subtitle_ffmpeg_exited_before_hls_ready"
      {
        code: "unsupported_subtitle",
        title: "Unsupported subtitle",
        message: fallback_message || "The selected subtitle cannot be used for interactive playback.",
        action: "Choose another subtitle or disable subtitles."
      }
    when nil
      {
        code: "internal_error",
        title: "Internal error",
        message: fallback_message || "The player hit an unexpected error.",
        action: "Retry the action."
      }
    else
      {
        code: "internal_error",
        title: "Internal error",
        message: fallback_message || "The player hit an unexpected error.",
        action: "Retry the action."
      }
    end
  end

  def deduplicate_errors(errors)
    seen = {}
    errors.each_with_object([]) do |error, list|
      key = [error[:code], error[:message]]
      next if seen[key]

      seen[key] = true
      list << error
    end
  end

  def safe_find_session(session_store, session_id)
    session_store.find(session_id)
  rescue TorrentStreaming::NotFoundError
    nil
  end

  def normalized_files(files)
    Array(files).map do |file|
      {
        "index" => file["index"],
        "path" => file["path"],
        "display_name" => file["display_name"],
        "size" => file["size"],
        "offset" => file["offset"],
        "piece_start" => file["piece_start"],
        "piece_end" => file["piece_end"],
        "kind" => file["kind"],
        "supported" => file.fetch("supported", true),
        "progress" => normalized_progress(file["progress"])
      }.compact
    end
  end

  def normalized_progress(progress)
    value = progress.is_a?(Hash) ? progress : {}
    {
      "bytes_downloaded" => integer_or_zero(value["bytes_downloaded"]),
      "bytes_total" => integer_or_zero(value["bytes_total"]),
      "pieces_have" => integer_or_zero(value["pieces_have"]),
      "pieces_total" => integer_or_zero(value["pieces_total"])
    }
  end

  def selected_file_progress(files, selected_file_index)
    return nil if selected_file_index.nil?

    selected = files.find { |file| file["index"] == selected_file_index }
    return nil unless selected

    progress = normalized_progress(selected["progress"])
    progress["bytes_total"].positive? ? progress : nil
  end

  def selected_status_progress(progress)
    return nil unless progress.is_a?(Hash)

    normalized = normalized_progress(progress)
    normalized["bytes_total"].positive? ? normalized : nil
  end

  def integer_or_zero(value)
    Integer(value || 0)
  rescue ArgumentError, TypeError
    0
  end

  def public_media_errors(error)
    return [] if error.nil?

    code =
      if error.is_a?(Hash)
        error["code"] || error["error"] || "range_server_error"
      else
        error.to_s
      end
    [{ "code" => code.to_s }]
  end

  def derive_media_state(current:, torrent:, files:, progress:)
    return current.fetch("state") if MEDIA_TERMINAL_STATES.include?(current.fetch("state"))
    return "failed" if torrent["error"]
    return "metadata" unless torrent["metadata_ready"]

    video_files = files.select { |file| file["kind"] == "video" && file.fetch("supported", true) }
    return "waiting_file_selection" if video_files.empty?
    return "waiting_file_selection" if torrent["selected_file_index"].nil?

    bytes_total = progress["bytes_total"]
    bytes_downloaded = progress["bytes_downloaded"]
    return "downloaded" if bytes_total.positive? && bytes_downloaded >= bytes_total
    return "streaming" if current["active_session_id"] || current["pending_session_id"]

    bytes_downloaded.positive? ? "downloading" : "selected"
  end

  # Final VOD packaging is scheduled only after the selected file is complete and trusted metadata exists.
  def vod_schedule_needed?(media)
    return false unless selected_file_complete?(media)
    return false unless vod_metadata_ready?(media)
    return false if media["hls_vod_path"]

    vod = media["vod_packaging"]
    return true unless vod.is_a?(Hash)

    !%w[pending running packaging ready cancelling failed cancelled].include?(vod["state"])
  end

  # Complete-file probes are separate from interactive probes because VOD packaging needs full-file metadata.
  def vod_probe_needed?(media)
    selected_file_complete?(media) && !vod_metadata_ready?(media)
  end

  def vod_metadata_ready?(media)
    probe = media["metadata_probe"]
    probe.is_a?(Hash) && probe["status"] == "ok" && probe["complete_file"] == true
  end

  def selected_file_complete?(media)
    progress = media["video_progress"].is_a?(Hash) ? media["video_progress"] : {}
    bytes_total = integer_or_zero(progress["bytes_total"])
    bytes_downloaded = integer_or_zero(progress["bytes_downloaded"])
    bytes_total.positive? && bytes_downloaded >= bytes_total
  end

  def public_vod_rendition(track)
    return {} unless track.is_a?(Hash)

    {
      index: track["index"],
      name: track["name"],
      language: track["language"],
      uri: File.basename(track["uri"].to_s)
    }.compact
  end

  def public_vod_error(error)
    return nil unless error.is_a?(Hash)

    mapped = error_from_code(error["code"])
    {
      code: mapped[:code],
      title: mapped[:title],
      message: mapped[:message],
      action: mapped[:action]
    }
  end

  def track_label(track, kind:)
    parts = []
    parts << (kind == :audio ? "Audio" : "Subtitle")
    parts << track["language"] if track["language"]
    parts << track["title"] if track["title"]
    parts << track["codec"] if track["codec"]
    if kind == :subtitle && track["source"] == "external" && track["path"]
      basename = safe_metadata_basename(track["path"])
      parts << basename unless basename.empty?
    end
    parts.compact.join(" - ")
  end

  def safe_metadata_basename(value)
    File.basename(value.to_s.tr("\\", "/"))
  end
end
