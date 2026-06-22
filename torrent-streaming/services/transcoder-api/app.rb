# frozen_string_literal: true

# Internal transcoder control plane. This Sinatra wrapper validates JSON, mutates the
# durable media/session state files, and enqueues worker jobs; HLS serving and the
# long-running ffmpeg lifecycle belong to the web and worker services.

[
  File.expand_path("shared/lib", __dir__),
  File.expand_path("../../shared/ruby/lib", __dir__)
].each { |path| $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path) }

require "sinatra/base"
require "health_helpers"
require "torrent_streaming"
require "torrent_streaming/transcoder"

class TranscoderApiApp < Sinatra::Base
  BACKEND_LOG_PREFIX = "[backend:transcoder-api]"
  # Keep mutating request bodies small before JSON parsing, because this API is an
  # internal state/queue boundary rather than a bulk upload endpoint.
  MAX_JSON_BODY_BYTES = Integer(ENV.fetch("TRANSCODER_API_MAX_JSON_BODY_BYTES", "65536"))

  set :bind, "0.0.0.0"
  set :port, ENV.fetch("PORT", "4568").to_i
  set :host_authorization,
      permitted_hosts: ENV.fetch(
        "PERMITTED_HOSTS",
        "localhost,127.0.0.1,0.0.0.0,web,transcoder-api"
      ).split(",").map(&:strip)

  before do
    content_type :json
    enforce_json_body_limit! if %w[POST PUT PATCH].include?(request.request_method)
  end

  helpers do
    def backend_debug_enabled?
      ENV.fetch("BACKEND_DEBUG_STDERR", "1") != "0" && ENV["APP_ENV"] != "test"
    end

    def backend_log(event, payload = nil, level: "debug", **kwargs)
      return unless backend_debug_enabled?

      payload = payload.is_a?(Hash) ? payload.merge(kwargs) : kwargs
      record = {
        service: "transcoder-api",
        level: level,
        event: event,
        method: request.request_method,
        path: request.path_info,
        request_id: request.env["HTTP_X_REQUEST_ID"]
      }.merge(payload)
      STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate(record)}")
      STDERR.flush
    rescue StandardError => e
      STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate({ service: "transcoder-api", level: "error", event: "backend_log_failed", error_class: e.class.name, message: e.message })}")
      STDERR.flush
    end

    def backend_error(event, payload = nil, **kwargs)
      backend_log(event, payload, level: "error", **kwargs)
    end

    def debug_request_path?
      request.path_info.start_with?("/media") || request.path_info.start_with?("/sessions")
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

    def session_manager
      @session_manager ||= TorrentStreaming::Transcoder::SessionManager.new(state_root: state_root)
    end

    def metadata_cache
      @metadata_cache ||= TorrentStreaming::Transcoder::FfprobeMetadataCache.new(
        storage_root: HealthHelpers.storage_root
      )
    end

    def vod_packager
      @vod_packager ||= TorrentStreaming::Transcoder::VodPackager.new(
        storage_root: HealthHelpers.storage_root
      )
    end

    def json_body
      enforce_json_body_limit!

      request.body.rewind
      # Read one byte past the limit so chunked requests without Content-Length are
      # rejected by the same contract as oversized fixed-length requests.
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

    # Clients have used a few field names for the same global playback offset; keep
    # the aliases here so the route layer passes one normalized value downstream.
    def start_time_from(body, required: false)
      key = %w[start_time_seconds start_time target_seconds].find { |candidate| body.key?(candidate) }
      if key.nil?
        raise TorrentStreaming::ValidationError.new("missing start_time_seconds", code: "missing_field") if required

        return 0
      end

      body.fetch(key)
    end

    def halt_json_error!(status_code, error, message)
      status status_code
      halt({ error: error, message: message }.to_json)
    end

    def domain_error!(error)
      # Corrupt or unknown-schema durable state is a conflict with the persisted
      # record, not bad client syntax, so callers can distinguish it from 400s.
      status(
        case error
        when TorrentStreaming::NotFoundError
          404
        when TorrentStreaming::CorruptJsonError, TorrentStreaming::SchemaVersionError
          409
        else
          400
        end
      )
      message = error.is_a?(TorrentStreaming::CorruptJsonError) ? "corrupt JSON state" : error.message
      payload = { error: error.code, message: message }
      backend_error("domain_error_response", status: response.status, code: error.code, message: message,
                                             error_class: error.class.name)
      halt payload.to_json
    end
  end

  before do
    backend_log("request", content_length: request.content_length) if debug_request_path?
  end

  after do
    backend_log("response", status: response.status, content_type: response["Content-Type"]) if debug_request_path?
  end

  get "/health" do
    status 200
    { service: "transcoder-api", status: "ok" }.to_json
  end

  get "/health/live" do
    status 200
    { service: "transcoder-api", status: "live" }.to_json
  end

  get "/health/ready" do
    # Readiness means this wrapper can accept state-mutating requests and enqueue
    # follow-up work, not just that the Sinatra process is alive.
    checks = {
      redis: HealthHelpers.check_redis,
      ffprobe: HealthHelpers.check_command(ENV.fetch("FFPROBE_BIN", "ffprobe"), "-version"),
      state_writable: HealthHelpers.check_writable_dir(File.join(HealthHelpers.storage_root, "state"))
    }
    payload = HealthHelpers.status_payload(service: "transcoder-api", checks: checks)
    status(payload[:status] == "ready" ? 200 : 503)
    payload.to_json
  end

  # Creates a durable pending playback session and enqueues worker-side ffmpeg
  # startup; the old active session stays publishable until the worker promotes the
  # replacement.
  post "/sessions" do
    body = json_body
    backend_log("session_create_request", media_id: body["media_id"], file_index: body["file_index"],
                                          start_time_seconds: start_time_from(body),
                                          selected_audio: body["selected_audio"],
                                          selected_subtitle: body["selected_subtitle"])
    session = session_manager.start(
      media_id: body.fetch("media_id"),
      file_index: body.fetch("file_index"),
      start_time_seconds: start_time_from(body),
      selected_audio: body["selected_audio"],
      selected_subtitle: body["selected_subtitle"]
    )
    backend_log("session_create_response", media_id: session.fetch("media_id"), session_id: session.fetch("session_id"),
                                           state: session["state"], playlist_path: session["playlist_path"])
    status 201
    session.to_json
  rescue KeyError => e
    domain_error!(TorrentStreaming::ValidationError.new("missing #{e.key}", code: "missing_field"))
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  get "/sessions/:session_id" do
    session = session_store.find(params.fetch("session_id"))
    backend_log("session_get_response", media_id: session.fetch("media_id"), session_id: session.fetch("session_id"),
                                        state: session["state"], error: session["error"])
    session.to_json
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  # Metadata probes either update the media record immediately or first mark it
  # pending before queueing, so Redis is never the only record of requested work.
  post "/media/:media_id/probe" do
    body = json_body
    file_index = body.fetch("file_index")
    force = body.fetch("force", false)
    complete_file = body.fetch("complete_file", false)
    async_probe = body.fetch("async", false)
    backend_log("probe_request", media_id: params.fetch("media_id"), file_index: file_index,
                                 force: force, complete_file: complete_file, async: async_probe)
    media = if async_probe
              pending = metadata_cache.mark_probe_pending!(
                params.fetch("media_id"),
                file_index,
                complete_file: complete_file
              )
              jid = TorrentStreaming::Transcoder::JobClient.enqueue(
                "ProbeMediaJob",
                args: [pending.fetch("media_id"), file_index, force, complete_file],
                queue: :interactive
              )
              backend_log("probe_async_enqueued", media_id: pending.fetch("media_id"),
                                                  file_index: file_index,
                                                  jid: jid,
                                                  queue: :interactive)
              pending
            else
              metadata_cache.probe_media!(
                params.fetch("media_id"),
                file_index,
                force: force,
                complete_file: complete_file
              )
            end
    backend_log("probe_response", media_id: media.fetch("media_id"),
                                  status: media.dig("metadata_probe", "status"),
                                  error: media.dig("metadata_probe", "error"),
                                  duration_seconds: media.dig("metadata_probe", "duration_seconds"))
    status 202
    media.to_json
  rescue KeyError => e
    domain_error!(TorrentStreaming::ValidationError.new("missing #{e.key}", code: "missing_field"))
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  # VOD requests only schedule packaging after the shared packager verifies durable
  # media state; final HLS publication is handled later by the VOD worker.
  post "/media/:media_id/vod" do
    json_body
    backend_log("vod_schedule_request", media_id: params.fetch("media_id"))
    media = vod_packager.schedule(params.fetch("media_id"))
    backend_log("vod_schedule_response", media_id: media.fetch("media_id"),
                                         vod_packaging: media["vod_packaging"])
    status 202
    media.to_json
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  # Stop records intent in the session state and enqueues process cleanup; missing
  # sessions fail before any worker side effect is created.
  post "/sessions/:session_id/stop" do
    json_body
    backend_log("session_stop_request", session_id: params.fetch("session_id"))
    session = session_manager.request_stop(params.fetch("session_id"))
    backend_log("session_stop_response", media_id: session.fetch("media_id"),
                                         session_id: session.fetch("session_id"),
                                         state: session["state"])
    status 202
    session.to_json
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  # Seek creates a replacement session at a new global offset. Audio/subtitle
  # choices are only changed when explicitly supplied by the caller.
  post "/sessions/:session_id/seek" do
    body = json_body
    args = {
      session_id: params.fetch("session_id"),
      start_time_seconds: start_time_from(body, required: true)
    }
    args[:selected_audio] = body["selected_audio"] if body.key?("selected_audio")
    args[:selected_subtitle] = body["selected_subtitle"] if body.key?("selected_subtitle")
    backend_log("session_seek_request", args)
    session = session_manager.seek(**args)
    backend_log("session_seek_response", media_id: session.fetch("media_id"),
                                         session_id: session.fetch("session_id"),
                                         state: session["state"],
                                         playlist_path: session["playlist_path"])
    status 201
    session.to_json
  rescue TorrentStreaming::DomainError => e
    domain_error!(e)
  end

  run! if app_file == $PROGRAM_NAME
end
