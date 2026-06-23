# frozen_string_literal: true

# Browser-facing Sinatra service for the torrent streaming UI.
# It owns request handling, cross-service orchestration, and the final safety checks before HLS files are served.

[
  File.expand_path("shared/lib", __dir__),
  File.expand_path("../../shared/ruby/lib", __dir__)
].each { |path| $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path) }

require "erb"
require "json"
require "sinatra/base"
require "time"
require "health_helpers"
require "torrent_streaming"

require_relative "service_clients"
require_relative "stream_ticket_verifier"
require_relative "web_ui"

# WebApp is the only service exposed to the browser. Internal services can create
# state and HLS artifacts, but this class decides what becomes a public response.
class WebApp < Sinatra::Base
  BACKEND_LOG_PREFIX = "[backend:web]"
  MAX_JSON_BODY_BYTES = Integer(ENV.fetch("WEB_MAX_JSON_BODY_BYTES", "65536"))
  DEFAULT_METADATA_PROBE_RETRY_SECONDS = 15.0

  set :bind, "0.0.0.0"
  set :port, ENV.fetch("PORT", "4567").to_i
  set :public_folder, File.expand_path("public", __dir__)
  set :views, File.expand_path("views", __dir__)
  set :static, true
  set :host_authorization,
      permitted_hosts: ENV.fetch(
        "PERMITTED_HOSTS",
        "localhost,127.0.0.1,0.0.0.0,web,transcoder-api"
      ).split(",").map(&:strip)

  before do
    apply_cors_headers!
    enforce_json_body_limit! if %w[POST PUT PATCH].include?(request.request_method)
  end

  # CORS preflight: answer before any auth gate so the browser can proceed.
  options "*" do
    apply_cors_headers!
    200
  end

  helpers do
    def backend_debug_enabled?
      ENV.fetch("BACKEND_DEBUG_STDERR", "1") != "0" && ENV["APP_ENV"] != "test"
    end

    def backend_log(event, payload = nil, level: "debug", **kwargs)
      return unless backend_debug_enabled?

      payload = payload.is_a?(Hash) ? payload.merge(kwargs) : kwargs
      record = {
        service: "web",
        level: level,
        event: event,
        method: request.request_method,
        path: request.path_info,
        request_id: request.env["HTTP_X_REQUEST_ID"]
      }.merge(payload)
      STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate(record)}")
      STDERR.flush
    rescue StandardError => e
      STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate({ service: "web", level: "error", event: "backend_log_failed", error_class: e.class.name, message: e.message })}")
      STDERR.flush
    end

    def backend_error(event, payload = nil, **kwargs)
      backend_log(event, payload, level: "error", **kwargs)
    end

    def debug_request_path?
      request.path_info.start_with?("/media") || request.path_info.start_with?("/sessions")
    end

    def h(value)
      Rack::Utils.escape_html(value.to_s)
    end

    # ── Stream ticket gate ──────────────────────────────────────────────────
    # The browser-facing content + playback-control surface is gated by a
    # signed stream ticket minted by the Hypertube API (see StreamTicket there
    # and StreamTicketVerifier here). Enforcement is opt-in so the standalone
    # ERB dev/test UI keeps working without auth: it is OFF unless
    # STREAM_TICKET_REQUIRED=1 (the React/production deployment sets it).

    # Viewer routes that deliver content or drive playback. The dev HTML shell
    # (`/`, `/media/:id`) and the orchestration endpoints (magnet create,
    # select-file) are intentionally excluded: the former are dev-only, the
    # latter move to machine-to-machine auth with the API handoff.
    GATED_STREAM_PATTERNS = [
      %r{\A/media/[^/]+/sessions/[^/]+/hls/},
      %r{\A/media/[^/]+/vod/},
      %r{\A/media/[^/]+/status\.json\z},
      %r{\A/media/[^/]+/playback\z},
      %r{\A/media/[^/]+/active-playlist\.json\z},
      %r{\A/media/[^/]+/(?:play|seek)\z},
      %r{\A/media/[^/]+/(?:pause|resume)\z},
      %r{\A/sessions/[^/]+/(?:stop|status\.json)\z}
    ].freeze

    def stream_ticket_required?
      ENV.fetch("STREAM_TICKET_REQUIRED", "0") == "1"
    end

    def gated_stream_path?(path)
      GATED_STREAM_PATTERNS.any? { |pattern| pattern.match?(path) }
    end

    # Extracts the media_id segment from a `/media/:media_id/...` path, or nil.
    def media_id_from_path(path)
      match = %r{\A/media/(?<media_id>[^/]+)/}.match(path)
      match && match[:media_id]
    end

    # Reads the ticket from the Authorization bearer header, a `ticket` query
    # param (so an <video>/hls.js src URL can carry it), or X-Stream-Ticket.
    def stream_ticket_token
      authorization = request.env["HTTP_AUTHORIZATION"].to_s
      return authorization.split(" ", 2).last if authorization.downcase.start_with?("bearer ")

      params["ticket"] || request.env["HTTP_X_STREAM_TICKET"]
    end

    # Verifies the ticket and, when the API has bound it to a concrete media
    # (via the movie->magnet handoff that fills the `media_id` claim), enforces
    # that the ticket matches the media being requested. Halts on any failure.
    def require_stream_ticket!(media_id: nil)
      token = stream_ticket_token
      halt_json_error!(401, "missing_stream_ticket", "A stream ticket is required") if token.to_s.empty?

      claims = StreamTicketVerifier.verify(token)
      request.env["stream.claims"] = claims

      bound_media_id = claims["media_id"]
      if media_id && bound_media_id && bound_media_id != media_id
        halt_json_error!(403, "stream_ticket_scope", "Stream ticket is not valid for this media")
      end

      claims
    rescue StreamTicketVerifier::Error => e
      backend_error("stream_ticket_invalid", message: e.message)
      halt_json_error!(401, "invalid_stream_ticket", "Stream ticket is invalid or expired")
    end

    # ── CORS ────────────────────────────────────────────────────────────────
    # The SPA (different origin) talks to this service directly, carrying the
    # stream ticket as a Bearer header. Allow the configured origins and the
    # headers/methods the player needs, including preflight.
    def cors_allowed_origins
      ENV.fetch("CORS_ALLOWED_ORIGINS", "http://localhost:5173").split(",").map(&:strip)
    end

    def apply_cors_headers!
      origin = request.env["HTTP_ORIGIN"]
      return if origin.nil?
      return unless cors_allowed_origins.include?("*") || cors_allowed_origins.include?(origin)

      headers "Access-Control-Allow-Origin"  => origin,
              "Vary"                          => "Origin",
              "Access-Control-Allow-Methods"  => "GET, POST, OPTIONS",
              "Access-Control-Allow-Headers"  => "Authorization, Content-Type, X-Stream-Ticket",
              "Access-Control-Max-Age"        => "600"
    end

    # Machine-to-machine gate for orchestration endpoints (media creation). The
    # Hypertube API authenticates with a signed service-scope token rather than
    # a viewer ticket. Only enforced when STREAM_TICKET_REQUIRED is on, so the
    # dev magnet form keeps working.
    def require_service_token!
      token = stream_ticket_token
      halt_json_error!(401, "missing_service_token", "A service token is required") if token.to_s.empty?

      StreamTicketVerifier.verify(token, scope: StreamTicketVerifier::SERVICE_SCOPE)
    rescue StreamTicketVerifier::Error => e
      backend_error("service_token_invalid", message: e.message)
      halt_json_error!(401, "invalid_service_token", "Service token is invalid or expired")
    end

    def state_root
      File.join(HealthHelpers.storage_root, "state")
    end

    def media_store
      @media_store ||= TorrentStreaming::MediaStore.new(root: state_root)
    end

    def session_store
      @session_store ||= TorrentStreaming::SessionStore.new(root: state_root)
    end

    def range_server_client
      @range_server_client ||= WebServices::RangeServerClient.new
    end

    def transcoder_api_client
      @transcoder_api_client ||= WebServices::TranscoderApiClient.new
    end

    def request_json?
      request.media_type == "application/json"
    end

    def request_data
      return json_body if request_json?

      params
    end

    def json_body
      enforce_json_body_limit!

      request.body.rewind
      raw = request.body.read(MAX_JSON_BODY_BYTES + 1)
      if raw.bytesize > MAX_JSON_BODY_BYTES
        halt_json_error!(413, "request_body_too_large", "JSON body is too large")
      end

      body = raw.empty? ? {} : JSON.parse(raw)
      unless body.is_a?(Hash)
        raise TorrentStreaming::ValidationError.new("JSON body must be an object", code: "invalid_body")
      end

      body
    rescue JSON::ParserError
      raise TorrentStreaming::ValidationError.new("invalid JSON body", code: "invalid_json")
    end

    def enforce_json_body_limit!
      content_length = request.content_length&.to_i
      return unless content_length && content_length > MAX_JSON_BODY_BYTES

      halt_json_error!(413, "request_body_too_large", "JSON body is too large")
    end

    def wants_redirect?
      !request_json?
    end

    def json_response(payload, status_code: 200)
      content_type :json
      status status_code
      JSON.generate(payload)
    end

    def halt_json_error!(status_code, error, message)
      content_type :json
      status status_code
      halt JSON.generate(error: error, message: message)
    end

    def public_remote_message(error)
      backend_error("upstream_public_error", status: error.status, code: error.code, message: error.message)
      error.status >= 500 ? "Upstream service unavailable." : "Upstream request failed."
    end

    def remote_error!(error)
      backend_error("remote_error_response", status: error.status, code: error.code, message: error.message,
                                             payload: error.payload)
      json_response(
        {
          error: error.code,
          message: public_remote_message(error)
        },
        status_code: error.status
      )
    end

    def domain_error!(error)
      message = error.is_a?(TorrentStreaming::CorruptJsonError) ? "corrupt JSON state" : error.message
      status_code =
        case error
        when TorrentStreaming::NotFoundError
          404
        when TorrentStreaming::CorruptJsonError, TorrentStreaming::SchemaVersionError
          409
        else
          400
        end
      backend_error("domain_error_response", status: status_code, code: error.code, message: message,
                                             error_class: error.class.name)
      json_response({ error: error.code, message: message }, status_code: status_code)
    end

    def html_error_status(error)
      case error
      when TorrentStreaming::NotFoundError
        404
      when TorrentStreaming::CorruptJsonError, TorrentStreaming::SchemaVersionError
        409
      else
        400
      end
    end

    def hls_root
      File.expand_path(File.join(HealthHelpers.storage_root, "hls"))
    end

    def expected_hls_directory(session)
      TorrentStreaming::PlaybackSession.hls_directory_for(
        session.fetch("session_id"),
        media_id: session.fetch("media_id")
      )
    end

    # Verifies that every persisted HLS path still matches the deterministic
    # media/session identity. State files are durable data, so this check treats
    # them as untrusted before any playlist, segment, or subtitle artifact is
    # exposed over HTTP.
    def validate_session_artifact_paths!(session)
      expected_directory = expected_hls_directory(session)
      stored_directory = session["hls_directory"] || File.dirname(session.fetch("playlist_path"))
      TorrentStreaming::Validation.relative_path!(stored_directory, field: "hls_directory")
      if stored_directory != expected_directory
        raise TorrentStreaming::ValidationError.new("session HLS directory does not match session identity",
                                                    code: "invalid_path")
      end

      expected_playlist = TorrentStreaming::PlaybackSession.playlist_path_for(
        session.fetch("session_id"),
        media_id: session.fetch("media_id")
      )
      playlist_path = session.fetch("playlist_path")
      TorrentStreaming::Validation.relative_path!(playlist_path, field: "playlist_path")
      if playlist_path != expected_playlist
        raise TorrentStreaming::ValidationError.new("session playlist path does not match session identity",
                                                    code: "invalid_path")
      end

      master_playlist_path = session["master_playlist_path"]
      unless master_playlist_path.nil?
        expected_master = File.join(expected_directory, "master.m3u8")
        TorrentStreaming::Validation.relative_path!(master_playlist_path, field: "master_playlist_path")
        if master_playlist_path != expected_master
          raise TorrentStreaming::ValidationError.new("session master playlist path does not match session identity",
                                                      code: "invalid_path")
        end
      end

      subtitle_playlist_path = session["subtitle_playlist_path"]
      unless subtitle_playlist_path.nil?
        selected = TorrentStreaming::Validation.non_negative_integer!(session.fetch("selected_subtitle"), field: "selected_subtitle")
        expected_subtitle_playlist = File.join(expected_directory, "subtitles", "subtitle_#{selected}.m3u8")
        TorrentStreaming::Validation.relative_path!(subtitle_playlist_path, field: "subtitle_playlist_path")
        if subtitle_playlist_path != expected_subtitle_playlist
          raise TorrentStreaming::ValidationError.new("session subtitle playlist path does not match session identity",
                                                      code: "invalid_path")
        end
      end

      subtitle_path = session["subtitle_path"]
      return expected_directory if subtitle_path.nil?

      TorrentStreaming::Validation.relative_path!(subtitle_path, field: "subtitle_path")
      if File.dirname(subtitle_path) != expected_directory
        raise TorrentStreaming::ValidationError.new("session subtitle path does not match session identity",
                                                    code: "invalid_path")
      end

      expected_directory
    end

    def load_hls_session!(media_id, session_id)
      safe_media_id = TorrentStreaming::Validation.media_id!(media_id)
      safe_session_id = TorrentStreaming::Validation.session_id!(session_id)
      media = media_store.find(safe_media_id)
      session = session_store.find(safe_session_id)
      unless session.fetch("media_id") == media.fetch("media_id")
        raise TorrentStreaming::NotFoundError, "session not found for media"
      end
      unless %w[hls_ready playing].include?(session.fetch("state"))
        raise TorrentStreaming::ValidationError.new("session HLS is not ready", code: "hls_not_ready")
      end

      [media, session]
    end

    # Resolves a stored relative HLS path into an absolute file path after
    # traversal, symlink, existence, and optional identity-root checks. The
    # identity check binds the file to the expected media/session directory, so a
    # valid-looking path cannot be reused to serve another session's artifacts.
    def safe_hls_target(relative, field:, identity_root: nil)
      TorrentStreaming::Validation.relative_path!(relative, field: field)
      target = File.expand_path(File.join(hls_root, relative))
      unless target.start_with?("#{hls_root}/")
        raise TorrentStreaming::ValidationError.new("HLS path escapes root", code: "invalid_path")
      end
      raise TorrentStreaming::NotFoundError, "HLS artifact not found" unless File.file?(target)
      root_realpath = File.realpath(hls_root)
      target_realpath = File.realpath(target)
      # Compare real paths after the file exists so symlinks cannot redirect an artifact out of storage/hls.
      unless target_realpath == root_realpath || target_realpath.start_with?("#{root_realpath}/")
        raise TorrentStreaming::ValidationError.new("HLS artifact escapes root via symlink", code: "invalid_path")
      end
      if identity_root
        TorrentStreaming::Validation.relative_path!(identity_root, field: "#{field} identity")
        identity_target = File.expand_path(File.join(root_realpath, identity_root))
        unless identity_target.start_with?("#{root_realpath}/")
          raise TorrentStreaming::ValidationError.new("HLS identity path escapes root", code: "invalid_path")
        end
        identity_realpath = File.realpath(identity_target)
        # The identity directory itself must not be a symlink to another media or session directory.
        unless identity_realpath == identity_target
          raise TorrentStreaming::ValidationError.new("HLS identity path escapes root via symlink", code: "invalid_path")
        end
        unless target_realpath == identity_target || target_realpath.start_with?("#{identity_target}/")
          raise TorrentStreaming::ValidationError.new("HLS artifact does not match media identity", code: "invalid_path")
        end
      end

      target
    rescue Errno::ENOENT
      raise TorrentStreaming::NotFoundError, "HLS artifact not found"
    end

    def safe_playlist_file(session)
      directory = validate_session_artifact_paths!(session)
      safe_hls_target(session.fetch("playlist_path"), field: "playlist_path", identity_root: directory)
    end

    def safe_master_playlist_file(session)
      directory = validate_session_artifact_paths!(session)
      master_playlist_path = session["master_playlist_path"]
      unless session["subtitle_mode"] == "hls" && master_playlist_path
        raise TorrentStreaming::NotFoundError, "HLS artifact not found"
      end

      safe_hls_target(master_playlist_path, field: "master_playlist_path", identity_root: directory)
    end

    # Maps a single session HLS URL component to an allowed segment or sidecar file.
    def safe_hls_file(session, filename)
      safe_filename = TorrentStreaming::Validation.safe_component!(filename, field: "hls filename")
      raise TorrentStreaming::ValidationError.new("temporary HLS artifacts are not served", code: "hls_not_ready") if safe_filename.end_with?(".tmp")

      directory = validate_session_artifact_paths!(session)
      relative =
        case File.extname(safe_filename)
        when ".ts"
          File.join(directory, safe_filename)
        when ".vtt"
          subtitle_path = session["subtitle_path"]
          unless subtitle_path && File.basename(subtitle_path) == safe_filename
            raise TorrentStreaming::NotFoundError, "HLS artifact not found"
          end
          subtitle_path
        else
          raise TorrentStreaming::ValidationError.new("unsupported HLS artifact type", code: "unsupported_hls_artifact")
        end

      safe_hls_target(relative, field: "hls artifact", identity_root: directory)
    end

    # Restricts subtitle HLS requests to the selected subtitle rendition for this session.
    def safe_hls_subtitle_file(session, filename)
      safe_filename = TorrentStreaming::Validation.safe_component!(filename, field: "hls subtitle filename")
      raise TorrentStreaming::ValidationError.new("temporary HLS artifacts are not served", code: "hls_not_ready") if safe_filename.end_with?(".tmp")

      directory = validate_session_artifact_paths!(session)
      selected = TorrentStreaming::Validation.non_negative_integer!(session.fetch("selected_subtitle"), field: "selected_subtitle")
      prefix = "subtitle_#{selected}"
      relative =
        case File.extname(safe_filename)
        when ".m3u8"
          subtitle_playlist_path = session["subtitle_playlist_path"]
          unless subtitle_playlist_path && File.basename(subtitle_playlist_path) == safe_filename
            raise TorrentStreaming::NotFoundError, "HLS artifact not found"
          end
          subtitle_playlist_path
        when ".vtt"
          unless safe_filename.start_with?("#{prefix}_")
            raise TorrentStreaming::NotFoundError, "HLS artifact not found"
          end
          File.join(directory, "subtitles", safe_filename)
        else
          raise TorrentStreaming::ValidationError.new("unsupported HLS artifact type", code: "unsupported_hls_artifact")
        end

      safe_hls_target(relative, field: "hls subtitle artifact", identity_root: directory)
    end

    # Final VOD HLS is served only after packaging has published the canonical master playlist.
    def load_vod_media!(media_id)
      safe_media_id = TorrentStreaming::Validation.media_id!(media_id)
      media = media_store.find(safe_media_id)
      unless media.fetch("state") == "ready" && media["hls_vod_path"]
        raise TorrentStreaming::ValidationError.new("VOD HLS is not ready", code: "hls_not_ready")
      end
      expected = File.join("vod", media.fetch("media_id"), "master.m3u8")
      unless media.fetch("hls_vod_path") == expected
        raise TorrentStreaming::ValidationError.new("VOD playlist path does not match media identity",
                                                    code: "invalid_path")
      end

      media
    end

    def safe_vod_playlist_file(media)
      safe_vod_target(media, media.fetch("hls_vod_path"))
    end

    def safe_vod_file(media, relative_path)
      components = relative_path.to_s.split("/")
      if components.empty? || components.any? { |component| component.empty? || component == "." || component == ".." }
        raise TorrentStreaming::ValidationError.new("invalid VOD artifact path", code: "invalid_path")
      end
      components.each { |component| TorrentStreaming::Validation.safe_component!(component, field: "vod filename") }
      if components.last.end_with?(".tmp")
        raise TorrentStreaming::ValidationError.new("temporary HLS artifacts are not served", code: "hls_not_ready")
      end
      unless %w[.m3u8 .ts .vtt].include?(File.extname(components.last))
        raise TorrentStreaming::ValidationError.new("unsupported HLS artifact type", code: "unsupported_hls_artifact")
      end

      safe_vod_target(media, File.join("vod", media.fetch("media_id"), *components))
    end

    # Applies the same root and identity checks to published VOD artifacts.
    def safe_vod_target(media, relative)
      TorrentStreaming::Validation.relative_path!(relative, field: "vod artifact")
      expected_base = File.join("vod", media.fetch("media_id"))
      unless relative == expected_base || relative.start_with?("#{expected_base}/")
        raise TorrentStreaming::ValidationError.new("VOD path does not match media identity", code: "invalid_path")
      end

      safe_hls_target(relative, field: "vod artifact", identity_root: expected_base)
    end

    def hls_content_type(path)
      case File.extname(path)
      when ".m3u8"
        "application/vnd.apple.mpegurl"
      when ".ts"
        "video/mp2t"
      when ".vtt"
        "text/vtt; charset=utf-8"
      else
        raise TorrentStreaming::ValidationError.new("unsupported HLS artifact type", code: "unsupported_hls_artifact")
      end
    end

    # Pulls range-server torrent state into local media JSON, then performs the
    # web-owned follow-up decisions that depend on that fresh state. Probe retry
    # and VOD scheduling live here because they bridge range progress with
    # transcoder-api work requests.
    def sync_media!(media_id)
      media = WebUI.sync_media!(
        media_store: media_store,
        media_id: media_id,
        range_server_client: range_server_client
      )
      media = if WebUI.vod_probe_needed?(media)
                ensure_probe(media, force: true, complete_file: true)
              else
                maybe_retry_metadata_probe(media)
              end
      schedule_vod_if_needed(media)
      notify_api_if_downloaded(media)
      media_store.find(media.fetch("media_id"))
    end

    # One-time machine-to-machine callback telling the Hypertube API a media has
    # finished downloading. Fires on the next sync after the media reaches a
    # complete state and is idempotent (api_notified_at guards re-sends).
    def notify_api_if_downloaded(media)
      return unless %w[downloaded packaging_vod ready].include?(media.fetch("state"))
      return if media["api_notified_at"]

      client = WebServices::HypertubeApiClient.new
      return unless client.configured?

      notified = client.notify_download_complete(
        token: StreamTicketVerifier.issue_service_token,
        payload: {
          media_id: media.fetch("media_id"),
          info_hash: media["info_hash"],
          name: media["name"],
          file_path: media["hls_vod_path"],
          duration_seconds: media["duration_seconds"]
        }
      )
      return unless notified

      media_store.update(media.fetch("media_id")) do |current|
        current.merge("api_notified_at" => Time.now.utc.iso8601)
      end
    rescue StandardError => e
      backend_error("notify_api_if_downloaded_failed", media_id: media.fetch("media_id"), message: e.message)
    end

    def safe_sync_media(media_id)
      safe_media_id = TorrentStreaming::Validation.media_id!(media_id)
      sync_media!(safe_media_id)
    rescue WebServices::RemoteServiceError => e
      backend_error("sync_media_remote_failed", media_id: safe_media_id, status: e.status, code: e.code,
                                                message: e.message)
      media_store.find(safe_media_id)
    end

    def ensure_probe(media, force: false, complete_file: false)
      selected_file_index = media["selected_file_index"]
      return media if selected_file_index.nil?
      return media if !force && media["metadata_probe"].is_a?(Hash) && media["metadata_probe"]["status"] == "ok"

      transcoder_api_client.probe_media(
        media_id: media.fetch("media_id"),
        file_index: selected_file_index,
        force: force,
        complete_file: complete_file
      )
      media_store.find(media.fetch("media_id"))
    rescue WebServices::RemoteServiceError => e
      backend_error("probe_media_remote_failed", media_id: media.fetch("media_id"), status: e.status, code: e.code,
                                                message: e.message, force: force, complete_file: complete_file)
      media_store.find(media.fetch("media_id"))
    end

    # Retries degraded metadata probes only when new bytes have arrived and the backoff has expired.
    def maybe_retry_metadata_probe(media)
      return media unless metadata_probe_retry_needed?(media)

      selected_file_index = media.fetch("selected_file_index")
      transcoder_api_client.probe_media(
        media_id: media.fetch("media_id"),
        file_index: selected_file_index,
        force: true,
        complete_file: false,
        async: true
      )
      media_store.find(media.fetch("media_id"))
    rescue WebServices::RemoteServiceError => e
      backend_error("metadata_probe_retry_remote_failed",
                    media_id: media.fetch("media_id"),
                    status: e.status,
                    code: e.code,
                    message: e.message)
      media_store.find(media.fetch("media_id"))
    end

    # A timeout is treated as temporary if torrent progress moved forward since the last probe.
    def metadata_probe_retry_needed?(media)
      return false unless media["selected_file_index"]
      return false if media["duration_seconds"]

      probe = media["metadata_probe"]
      return false unless probe.is_a?(Hash)
      return false unless probe["status"] == "degraded" && probe["error"] == "ffprobe_timeout"
      return false unless metadata_probe_retry_backoff_expired?(probe)

      metadata_probe_current_progress(media) > WebUI.integer_or_zero(probe["progress_bytes_downloaded"])
    end

    def metadata_probe_retry_backoff_expired?(probe)
      updated_at = Time.parse(probe["updated_at"].to_s)
      (Time.now.utc - updated_at) >= metadata_probe_retry_seconds
    rescue ArgumentError, TypeError
      true
    end

    def metadata_probe_retry_seconds
      Float(ENV.fetch("METADATA_PROBE_RETRY_SECONDS", DEFAULT_METADATA_PROBE_RETRY_SECONDS.to_s))
    rescue ArgumentError, TypeError
      DEFAULT_METADATA_PROBE_RETRY_SECONDS
    end

    def metadata_probe_current_progress(media)
      progress = media["video_progress"].is_a?(Hash) ? media["video_progress"] : {}
      WebUI.integer_or_zero(progress["bytes_downloaded"])
    end

    # Starts final VOD packaging once the selected file and trusted complete-file metadata are ready.
    def schedule_vod_if_needed(media)
      return unless WebUI.vod_schedule_needed?(media)

      transcoder_api_client.schedule_vod(media_id: media.fetch("media_id"))
    rescue WebServices::RemoteServiceError => e
      backend_error("schedule_vod_remote_failed", media_id: media.fetch("media_id"), status: e.status, code: e.code,
                                                 message: e.message)
      nil
    end

    def resume_torrent_quietly(media_id)
      range_server_client.resume_torrent(media_id: media_id)
    rescue WebServices::RemoteServiceError => e
      backend_error("resume_torrent_failed", media_id: media_id, status: e.status, code: e.code, message: e.message)
      nil
    end

    def status_payload(media)
      WebUI.media_payload(media, session_store: session_store)
    end

    def present_session(session_record, media_id:)
      WebUI.session_payload(session_record, media_id: media_id)
    end

    def active_playlist_payload(media)
      WebUI.active_playlist_payload(media, session_store: session_store)
    end

    def parse_non_negative_integer(value, field:)
      Integer(value).tap do |integer|
        raise TorrentStreaming::ValidationError.new("#{field} must be a non-negative integer", code: "invalid_integer") if integer.negative?
      end
    rescue ArgumentError, TypeError
      raise TorrentStreaming::ValidationError.new("#{field} must be a non-negative integer", code: "invalid_integer")
    end

    def parse_optional_track(value, field:)
      return nil if value.nil? || value == ""

      parse_non_negative_integer(value, field: field)
    end

    def load_media_or_raise!(media_id)
      media_store.find(TorrentStreaming::Validation.media_id!(media_id))
    end

    def build_play_payload(data, media)
      {
        file_index: parse_non_negative_integer(data.fetch("file_index"), field: "file_index"),
        selected_audio: parse_optional_track(data["selected_audio"], field: "selected_audio"),
        selected_subtitle: parse_optional_track(data["selected_subtitle"], field: "selected_subtitle"),
        start_time_seconds: WebUI.clamp_target(data.fetch("start_time_seconds"), media["duration_seconds"])
      }
    rescue KeyError => e
      raise TorrentStreaming::ValidationError.new("missing #{e.key}", code: "missing_field")
    end

    def render_index(status_code: 200, form_error: nil)
      @form_error = form_error
      @media_list = media_store.all.sort_by { |media| media["updated_at"] }.reverse
      status status_code
      erb :index
    end

    def render_media_page(media, status_code: 200, page_error: nil)
      @page_error = page_error
      @media = media
      @media_payload = status_payload(media)
      @bootstrap_json = WebUI.json_script(@media_payload)
      status status_code
      erb :media
    end
  end

  get "/health" do
    json_response({ service: "web", status: "ok" })
  end

  get "/health/live" do
    json_response({ service: "web", status: "live" })
  end

  get "/health/ready" do
    checks = {
      state_writable: HealthHelpers.check_writable_dir(File.join(HealthHelpers.storage_root, "state")),
      hls_writable: HealthHelpers.check_writable_dir(File.join(HealthHelpers.storage_root, "hls")),
      transcoder_api_ready: HealthHelpers.check_http("#{ENV.fetch("TRANSCODER_API_URL")}/health/ready")
    }
    payload = HealthHelpers.status_payload(service: "web", checks: checks)
    json_response(payload, status_code: payload[:status] == "ready" ? 200 : 503)
  end

  before do
    backend_log("request", query_string: request.query_string, content_length: request.content_length) if debug_request_path?
  end

  # Gate the viewer content + playback-control surface behind a stream ticket
  # when enforcement is enabled. Runs before route dispatch, so the media_id is
  # read from the path rather than route params.
  before do
    next if request.request_method == "OPTIONS"
    next unless stream_ticket_required?
    next unless gated_stream_path?(request.path_info)

    require_stream_ticket!(media_id: media_id_from_path(request.path_info))
  end

  after do
    backend_log("response", status: response.status, content_type: response["Content-Type"]) if debug_request_path?
  end

  get "/" do
    render_index
  end

  post "/media" do
    require_service_token! if stream_ticket_required?
    data = request_data
    magnet = data["magnet"] || data[:magnet]
    media = media_store.create_from_magnet(magnet)
    range_server_client.create_torrent(media_id: media.fetch("media_id"), magnet: media.fetch("magnet"))
    synced = safe_sync_media(media.fetch("media_id"))

    if wants_redirect?
      redirect "/media/#{synced.fetch("media_id")}"
    else
      json_response(synced, status_code: 201)
    end
  rescue WebServices::RemoteServiceError => e
    if wants_redirect?
      render_index(status_code: e.status, form_error: public_remote_message(e))
    else
      remote_error!(e)
    end
  rescue TorrentStreaming::DomainError => e
    if wants_redirect?
      render_index(status_code: html_error_status(e), form_error: e.is_a?(TorrentStreaming::CorruptJsonError) ? "corrupt JSON state" : e.message)
    else
      domain_error!(e)
    end
  end

  get "/media/:media_id" do
    media = safe_sync_media(params.fetch("media_id"))
    render_media_page(media)
  rescue TorrentStreaming::DomainError => e
    if request_json?
      domain_error!(e)
    else
      render_index(status_code: html_error_status(e), form_error: e.is_a?(TorrentStreaming::CorruptJsonError) ? "corrupt JSON state" : e.message)
    end
  end

  get "/media/:media_id/status.json" do
    media = safe_sync_media(params.fetch("media_id"))
    json_response(status_payload(media))
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  post "/media/:media_id/select-file" do
    media = safe_sync_media(params.fetch("media_id"))
    data = request_data
    file_index = parse_non_negative_integer(data.fetch("file_index"), field: "file_index")
    range_server_client.select_file(media_id: media.fetch("media_id"), file_index: file_index)
    synced = sync_media!(media.fetch("media_id"))
    ensure_probe(synced)

    if wants_redirect?
      redirect "/media/#{media.fetch("media_id")}"
    else
      json_response(status_payload(media_store.find(media.fetch("media_id"))))
    end
  rescue KeyError => e
    domain_error!(TorrentStreaming::ValidationError.new("missing #{e.key}", code: "missing_field"))
  rescue WebServices::RemoteServiceError => e
    remote_error!(e)
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  post "/media/:media_id/play" do
    media = safe_sync_media(params.fetch("media_id"))
    # Resuming on play makes "download only while watching" reversible: a media
    # paused when the last viewer left continues downloading when playback starts.
    resume_torrent_quietly(media.fetch("media_id"))
    payload = build_play_payload(request_data, media)
    backend_log("play_request", media_id: media.fetch("media_id"), payload: payload)
    if media["selected_file_index"] != payload.fetch(:file_index)
      backend_log("play_select_file_before_start", media_id: media.fetch("media_id"),
                                               previous_file_index: media["selected_file_index"],
                                               requested_file_index: payload.fetch(:file_index))
      range_server_client.select_file(media_id: media.fetch("media_id"), file_index: payload.fetch(:file_index))
      media = sync_media!(media.fetch("media_id"))
      ensure_probe(media)
    end

    session = transcoder_api_client.start_session(
      media_id: media.fetch("media_id"),
      file_index: payload.fetch(:file_index),
      start_time_seconds: payload.fetch(:start_time_seconds),
      selected_audio: payload.fetch(:selected_audio),
      selected_subtitle: payload.fetch(:selected_subtitle)
    )
    backend_log("play_session_response", media_id: media.fetch("media_id"), session_id: session.fetch("session_id"),
                                         state: session["state"], playlist_path: session["playlist_path"])
    json_response(present_session(session, media_id: media.fetch("media_id")), status_code: 202)
  rescue WebServices::RemoteServiceError => e
    remote_error!(e)
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  post "/media/:media_id/seek" do
    media = safe_sync_media(params.fetch("media_id"))
    session_id = WebUI.session_for_seek(media)
    raise TorrentStreaming::ValidationError.new("no playback session available", code: "no_playback_session") if session_id.nil?

    data = request_data
    target_seconds = WebUI.clamp_target(data.fetch("target_seconds"), media["duration_seconds"])
    backend_log("seek_request", media_id: media.fetch("media_id"), session_id: session_id,
                                target_seconds: target_seconds)
    session = transcoder_api_client.seek_session(
      session_id: session_id,
      target_seconds: target_seconds,
      selected_audio: data.key?("selected_audio") ? parse_optional_track(data["selected_audio"], field: "selected_audio") : :unchanged,
      selected_subtitle: data.key?("selected_subtitle") ? parse_optional_track(data["selected_subtitle"], field: "selected_subtitle") : :unchanged
    )
    backend_log("seek_session_response", media_id: media.fetch("media_id"), session_id: session.fetch("session_id"),
                                         state: session["state"], playlist_path: session["playlist_path"])
    json_response(present_session(session, media_id: media.fetch("media_id")), status_code: 202)
  rescue KeyError => e
    domain_error!(TorrentStreaming::ValidationError.new("missing #{e.key}", code: "missing_field"))
  rescue WebServices::RemoteServiceError => e
    remote_error!(e)
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  # Pause downloading for a media (called when the last viewer leaves a not-yet-
  # downloaded movie, so the torrent only progresses while someone is watching).
  post "/media/:media_id/pause" do
    media = load_media_or_raise!(params.fetch("media_id"))
    result = range_server_client.pause_torrent(media_id: media.fetch("media_id"))
    backend_log("pause_torrent", media_id: media.fetch("media_id"))
    json_response(result)
  rescue WebServices::RemoteServiceError => e
    remote_error!(e)
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  post "/media/:media_id/resume" do
    media = load_media_or_raise!(params.fetch("media_id"))
    result = range_server_client.resume_torrent(media_id: media.fetch("media_id"))
    backend_log("resume_torrent", media_id: media.fetch("media_id"))
    json_response(result)
  rescue WebServices::RemoteServiceError => e
    remote_error!(e)
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  post "/sessions/:session_id/stop" do
    session_id = TorrentStreaming::Validation.session_id!(params.fetch("session_id"))
    backend_log("stop_request", session_id: session_id)
    session = transcoder_api_client.stop_session(session_id)
    backend_log("stop_session_response", media_id: session.fetch("media_id"), session_id: session.fetch("session_id"),
                                         state: session["state"])
    json_response(present_session(session, media_id: session.fetch("media_id")), status_code: 202)
  rescue WebServices::RemoteServiceError => e
    remote_error!(e)
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/sessions/:session_id/status.json" do
    session = session_store.find(params.fetch("session_id"))
    backend_log("session_status_response", media_id: session.fetch("media_id"),
                                           session_id: session.fetch("session_id"),
                                           state: session["state"], error: session["error"])
    json_response(present_session(session, media_id: session.fetch("media_id")))
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/active-playlist.json" do
    media = load_media_or_raise!(params.fetch("media_id"))
    payload = active_playlist_payload(media)
    backend_log("active_playlist_response", media_id: media.fetch("media_id"),
                                            active_session_id: media["active_session_id"],
                                            pending_session_id: media["pending_session_id"],
                                            payload: payload)
    json_response(payload)
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/playback" do
    media = load_media_or_raise!(params.fetch("media_id"))
    json_response(active_playlist_payload(media).merge(
                    active_session_id: media["active_session_id"],
                    pending_session_id: media["pending_session_id"]
                  ))
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/sessions/:session_id/hls/playlist.m3u8" do
    _media, session = load_hls_session!(params.fetch("media_id"), params.fetch("session_id"))
    path = safe_playlist_file(session)
    backend_log("hls_playlist_send", media_id: params.fetch("media_id"), session_id: params.fetch("session_id"),
                                     path: path, bytes: File.size(path))
    content_type hls_content_type(path)
    send_file path
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/sessions/:session_id/hls/master.m3u8" do
    _media, session = load_hls_session!(params.fetch("media_id"), params.fetch("session_id"))
    path = safe_master_playlist_file(session)
    backend_log("hls_master_playlist_send", media_id: params.fetch("media_id"), session_id: params.fetch("session_id"),
                                            path: path, bytes: File.size(path))
    content_type hls_content_type(path)
    send_file path
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/sessions/:session_id/hls/subtitles/:filename" do
    _media, session = load_hls_session!(params.fetch("media_id"), params.fetch("session_id"))
    path = safe_hls_subtitle_file(session, params.fetch("filename"))
    backend_log("hls_subtitle_artifact_send", media_id: params.fetch("media_id"), session_id: params.fetch("session_id"),
                                              filename: params.fetch("filename"), path: path, bytes: File.size(path))
    content_type hls_content_type(path)
    send_file path
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/sessions/:session_id/hls/:filename" do
    _media, session = load_hls_session!(params.fetch("media_id"), params.fetch("session_id"))
    path = safe_hls_file(session, params.fetch("filename"))
    backend_log("hls_artifact_send", media_id: params.fetch("media_id"), session_id: params.fetch("session_id"),
                                     filename: params.fetch("filename"), path: path, bytes: File.size(path))
    content_type hls_content_type(path)
    send_file path
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/vod/master.m3u8" do
    media = load_vod_media!(params.fetch("media_id"))
    path = safe_vod_playlist_file(media)
    backend_log("vod_playlist_send", media_id: media.fetch("media_id"), path: path, bytes: File.size(path))
    content_type hls_content_type(path)
    send_file path
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/media/:media_id/vod/*" do
    media = load_vod_media!(params.fetch("media_id"))
    path = safe_vod_file(media, params.fetch("splat").first)
    backend_log("vod_artifact_send", media_id: media.fetch("media_id"), splat: params.fetch("splat").first,
                                   path: path, bytes: File.size(path))
    content_type hls_content_type(path)
    send_file path
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  run! if app_file == $PROGRAM_NAME
end
