# frozen_string_literal: true

# Shared readiness helpers for service endpoints. The checks return small,
# serializable result hashes so each service can report dependency health
# without sharing controller code.
require "fileutils"
require "json"
require "net/http"
require "timeout"
require "uri"

module HealthHelpers
  module_function

  # Services agree on STORAGE_ROOT as the writable application data boundary.
  def storage_root
    ENV.fetch("STORAGE_ROOT", "/app/storage")
  end

  def check_writable_dir(path)
    FileUtils.mkdir_p(path)
    probe = File.join(path, ".healthcheck-#{Process.pid}")
    File.write(probe, "ok")
    File.delete(probe)
    { ok: true }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def check_http(url, timeout_seconds: 2)
    uri = URI(url)
    response = nil
    Net::HTTP.start(uri.host, uri.port, open_timeout: timeout_seconds, read_timeout: timeout_seconds) do |http|
      response = http.get(uri.request_uri)
    end
    { ok: response.is_a?(Net::HTTPSuccess), status: response.code.to_i }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def check_redis
    require "redis"

    redis = Redis.new(url: ENV.fetch("REDIS_URL"))
    pong = redis.ping
    { ok: pong == "PONG", response: pong }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def check_command(*command)
    system(*command, out: File::NULL, err: File::NULL)
    { ok: $?.success? }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def status_payload(service:, checks:)
    ready = checks.values.all? { |result| result[:ok] }
    {
      service: service,
      status: ready ? "ready" : "not_ready",
      checks: checks
    }
  end
end
