# frozen_string_literal: true

# Internal-service clients used by the web gateway.
# They keep upstream HTTP details out of route handlers and normalize failures into one error shape.

require "json"
require "net/http"
require "uri"

module WebServices
  BACKEND_LOG_PREFIX = "[backend:web-client]"

  def self.backend_debug_enabled?
    ENV.fetch("BACKEND_DEBUG_STDERR", "1") != "0" && ENV["APP_ENV"] != "test"
  end

  def self.backend_log(event, payload = nil, level: "debug", **kwargs)
    return unless backend_debug_enabled?

    payload = payload.is_a?(Hash) ? payload.merge(kwargs) : kwargs
    record = { service: "web-client", level: level, event: event }.merge(payload)
    STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate(record)}")
    STDERR.flush
  rescue StandardError => e
    STDERR.puts("#{BACKEND_LOG_PREFIX} #{JSON.generate({ service: "web-client", level: "error", event: "backend_log_failed", error_class: e.class.name, message: e.message })}")
    STDERR.flush
  end

  def self.backend_error(event, payload = nil, **kwargs)
    backend_log(event, payload, level: "error", **kwargs)
  end

  # Carries the public HTTP status plus the upstream error payload for logging and response mapping.
  class RemoteServiceError < StandardError
    attr_reader :status, :code, :payload

    def initialize(status:, code:, message:, payload: nil)
      super(message)
      @status = status
      @code = code
      @payload = payload || {}
    end
  end

  # Shared JSON-over-HTTP wrapper for internal services. It accepts a test
  # adapter, logs request/response metadata, requires object-shaped JSON
  # responses, and raises RemoteServiceError for any upstream failure.
  class JsonServiceClient
    class << self
      attr_accessor :adapter
    end

    attr_reader :base_url

    def initialize(base_url:, adapter: nil)
      @base_url = base_url.to_s.delete_suffix("/")
      @adapter = adapter || self.class.adapter
    end

    private

    def get_json(path)
      perform(:get, path)
    end

    def post_json(path, payload)
      perform(:post, path, payload: payload)
    end

    def perform(method, path, payload: nil)
      request = {
        method: method,
        path: path,
        url: "#{base_url}#{path}",
        payload: payload
      }
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      WebServices.backend_log(
        "upstream_request",
        method: method,
        path: path,
        url: request.fetch(:url),
        payload_keys: payload.is_a?(Hash) ? payload.keys : []
      )

      response_payload =
        if @adapter
          @adapter.call(**request)
        else
          perform_http(request)
        end

      normalized = normalize_response(response_payload)
      WebServices.backend_log(
        "upstream_response",
        method: method,
        path: path,
        url: request.fetch(:url),
        status: response_payload[:status],
        elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1),
        response_keys: normalized.keys
      )
      normalized
    rescue RemoteServiceError => e
      WebServices.backend_error(
        "upstream_error",
        method: method,
        path: path,
        url: request.fetch(:url),
        status: e.status,
        code: e.code,
        message: e.message,
        elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1),
        payload: e.payload
      )
      raise
    end

    def perform_http(request)
      uri = URI.parse(request.fetch(:url))
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 30

      net_request =
        case request.fetch(:method)
        when :get
          Net::HTTP::Get.new(uri.request_uri)
        when :post
          req = Net::HTTP::Post.new(uri.request_uri)
          req["Content-Type"] = "application/json"
          req.body = JSON.generate(request.fetch(:payload))
          req
        else
          raise ArgumentError, "unsupported HTTP method #{request.fetch(:method)}"
        end

      response = http.request(net_request)
      payload = parse_body(response.body)
      { status: response.code.to_i, payload: payload }
    rescue JSON::ParserError => e
      raise RemoteServiceError.new(status: 502, code: "invalid_upstream_json", message: e.message)
    rescue StandardError => e
      raise RemoteServiceError.new(status: 502, code: "upstream_unavailable", message: e.message)
    end

    def normalize_response(response)
      status = Integer(response.fetch(:status))
      payload = response[:payload]
      payload = {} if payload.nil?

      unless payload.is_a?(Hash)
        raise RemoteServiceError.new(status: 502, code: "invalid_upstream_payload",
                                     message: "upstream payload must be a JSON object")
      end

      return payload if (200..299).cover?(status)

      raise RemoteServiceError.new(
        status: status,
        code: payload["error"] || "upstream_error",
        message: payload["message"] || "upstream request failed",
        payload: payload
      )
    end

    def parse_body(body)
      return {} if body.nil? || body.empty?

      JSON.parse(body)
    end
  end

  # Client for the range-server, which owns torrent metadata, file lists, and file priority.
  class RangeServerClient < JsonServiceClient
    DEFAULT_URL = ENV.fetch("RANGE_SERVER_URL", "http://range-server:7000")

    def initialize(base_url: DEFAULT_URL, adapter: nil)
      super
    end

    def create_torrent(media_id:, magnet:)
      post_json("/torrents", { "media_id" => media_id, "magnet" => magnet })
    end

    def fetch_torrent(media_id)
      get_json("/torrents/#{media_id}")
    end

    def fetch_files(media_id)
      get_json("/torrents/#{media_id}/files")
    end

    def select_file(media_id:, file_index:)
      post_json("/torrents/#{media_id}/select-file", { "file_index" => file_index })
    end
  end

  # Client for transcoder-api commands that create sessions, seek, probe metadata, and schedule VOD work.
  class TranscoderApiClient < JsonServiceClient
    DEFAULT_URL = ENV.fetch("TRANSCODER_API_URL", "http://transcoder-api:4568")

    def initialize(base_url: DEFAULT_URL, adapter: nil)
      super
    end

    def start_session(media_id:, file_index:, start_time_seconds:, selected_audio:, selected_subtitle:)
      payload = {
        "media_id" => media_id,
        "file_index" => file_index,
        "start_time_seconds" => start_time_seconds
      }
      payload["selected_audio"] = selected_audio if !selected_audio.nil? || payload.key?("selected_audio")
      payload["selected_subtitle"] = selected_subtitle if !selected_subtitle.nil? || payload.key?("selected_subtitle")
      post_json("/sessions", payload)
    end

    # Seek can also carry explicit track choices. Omitted track fields mean the transcoder keeps its current selection.
    def seek_session(session_id:, target_seconds:, selected_audio: :unchanged, selected_subtitle: :unchanged)
      payload = { "target_seconds" => target_seconds }
      payload["selected_audio"] = selected_audio unless selected_audio == :unchanged
      payload["selected_subtitle"] = selected_subtitle unless selected_subtitle == :unchanged
      post_json("/sessions/#{session_id}/seek", payload)
    end

    def stop_session(session_id)
      post_json("/sessions/#{session_id}/stop", {})
    end

    # Metadata probes may be interactive-range probes or complete-file probes for final VOD eligibility.
    def probe_media(media_id:, file_index:, force: false, complete_file: false, async: false)
      post_json("/media/#{media_id}/probe", {
                  "file_index" => file_index,
                  "force" => force,
                  "complete_file" => complete_file,
                  "async" => async
                })
    end

    # VOD scheduling is idempotent on the API side; the web layer only sends it when media state qualifies.
    def schedule_vod(media_id:)
      post_json("/media/#{media_id}/vod", {})
    end
  end
end
