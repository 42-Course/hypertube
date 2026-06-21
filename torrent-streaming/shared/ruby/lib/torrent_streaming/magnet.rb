# frozen_string_literal: true

# Canonicalizes magnet links and derives stable media IDs. The normalized form
# is persisted with media records, so equivalent magnets must resolve to the
# same identity before any state file is created.
require "digest"
require "uri"

require_relative "errors"

module TorrentStreaming
  module Magnet
    BTIH_HEX_PATTERN = /\A[0-9a-f]{40}\z/
    BTIH_BASE32_PATTERN = /\A[a-z2-7]{32}\z/

    module_function

    # Sorts and normalizes query parameters while requiring a valid btih info
    # hash; this is the boundary between user input and persisted media state.
    def normalize(value)
      raw = value.to_s.strip
      uri = URI(raw)
      raise InvalidMagnetError unless uri.scheme&.downcase == "magnet"
      raise InvalidMagnetError, "magnet query is required" if uri.query.to_s.empty?

      pairs = URI.decode_www_form(uri.query).map do |key, param_value|
        [key.to_s.downcase, normalize_value(key, param_value)]
      end
      xt = pairs.find { |key, _| key == "xt" }&.last
      unless xt&.start_with?("urn:btih:") && valid_btih?(xt.delete_prefix("urn:btih:"))
        raise InvalidMagnetError, "magnet xt=urn:btih is required"
      end

      "magnet:?#{URI.encode_www_form(pairs.sort)}"
    rescue URI::InvalidURIError
      raise InvalidMagnetError
    end

    # Uses the canonical magnet string, not raw user input, to keep media IDs
    # deterministic across services.
    def media_id(value)
      Digest::SHA256.hexdigest(normalize(value))[0, 32]
    end

    def normalize_value(key, value)
      string = value.to_s.strip
      return string.downcase if key.to_s.downcase == "xt" && string.downcase.start_with?("urn:btih:")

      string
    end
    private_class_method :normalize_value

    def valid_btih?(value)
      value.match?(BTIH_HEX_PATTERN) || value.match?(BTIH_BASE32_PATTERN)
    end
    private_class_method :valid_btih?
  end
end
