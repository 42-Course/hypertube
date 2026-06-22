# frozen_string_literal: true

# Readiness probe for transcoder worker containers. It verifies the broker, ffmpeg,
# and writable shared output roots needed before Sidekiq jobs can safely run.

$LOAD_PATH.unshift(File.expand_path("shared/lib", __dir__))

require "health_helpers"

checks = {
  redis: HealthHelpers.check_redis,
  ffmpeg: HealthHelpers.check_command("ffmpeg", "-version"),
  logs_writable: HealthHelpers.check_writable_dir(File.join(HealthHelpers.storage_root, "logs")),
  hls_writable: HealthHelpers.check_writable_dir(File.join(HealthHelpers.storage_root, "hls"))
}

payload = HealthHelpers.status_payload(service: ENV.fetch("APP_NAME", "transcoder-worker"), checks: checks)
puts JSON.generate(payload)
exit(payload[:status] == "ready" ? 0 : 1)
