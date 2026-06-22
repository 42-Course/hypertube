# frozen_string_literal: true

require "faraday"
require "json"

# Server-to-server client for the torrent streaming service.
#
# The API uses it to resolve a movie into a prepared streaming "media" (which
# also starts the torrent download) and to obtain the deterministic media_id it
# then binds into the viewer's stream ticket. Authenticated with a short-lived
# service token (StreamTicket.service_token) the streaming service verifies
# locally, so no shared session or DB is needed.
#
# Two URLs are involved: the API reaches the streaming service over the internal
# network (STREAMING_SERVICE_INTERNAL_URL), while the browser reaches it at the
# public URL (STREAMING_SERVICE_URL) returned to the SPA.
class StreamingService
  Error = Class.new(StandardError)

  # Public base URL the browser uses to reach the streaming service.
  def self.public_base_url
    ENV["STREAMING_SERVICE_URL"].presence
  end

  def initialize(base_url: nil)
    @base_url = (base_url || internal_base_url)&.chomp("/")
  end

  def configured?
    @base_url.present?
  end

  # Create-or-fetch the media for a magnet and return its media_id. Idempotent:
  # the streaming service keys media by a hash of the magnet, so repeated calls
  # return the same id without re-adding the torrent.
  def ensure_media(magnet:)
    raise Error, "streaming service URL is not configured" unless configured?

    response = connection.post("/media") do |req|
      req.headers["Content-Type"]  = "application/json"
      req.headers["Accept"]        = "application/json"
      req.headers["Authorization"] = "Bearer #{StreamTicket.service_token}"
      req.body = JSON.generate(magnet: magnet)
    end

    raise Error, "streaming service returned #{response.status}" unless response.success?

    media_id = parse_media_id(response.body)
    raise Error, "streaming service response missing media_id" if media_id.blank?

    media_id
  rescue Faraday::Error => e
    raise Error, "streaming service unreachable: #{e.message}"
  end

  private

  def internal_base_url
    ENV["STREAMING_SERVICE_INTERNAL_URL"].presence || ENV["STREAMING_SERVICE_URL"].presence
  end

  def parse_media_id(body)
    data = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
    data["media_id"] || data.dig("media", "media_id")
  rescue JSON::ParserError
    nil
  end

  def connection
    @connection ||= Faraday.new(url: @base_url) do |f|
      f.options.timeout      = 10
      f.options.open_timeout = 4
    end
  end
end
