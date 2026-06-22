# frozen_string_literal: true

# Central validation boundary for IDs, numeric inputs, and persisted paths.
# These helpers reject traversal and malformed values before records are written
# or file paths are derived from user-controlled input.
require "pathname"

require_relative "errors"

module TorrentStreaming
  # Validators return normalized strings or numbers so callers can safely use
  # the result in state file names, HLS paths, and persisted JSON fields.
  module Validation
    MEDIA_ID_PATTERN = /\A[0-9a-f]{32}\z/
    SESSION_ID_PATTERN = /\Asess_[0-9a-f]{32}\z/
    SAFE_COMPONENT_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/

    module_function

    def media_id!(value)
      string = value.to_s
      raise InvalidIdError, "invalid media_id" unless string.match?(MEDIA_ID_PATTERN)

      string
    end

    def session_id!(value)
      string = value.to_s
      raise InvalidIdError, "invalid session_id" unless string.match?(SESSION_ID_PATTERN)

      string
    end

    # Safe components are stricter than general relative paths because callers
    # may use them as one filesystem segment.
    def safe_component!(value, field: "path component")
      string = value.to_s
      unless string.match?(SAFE_COMPONENT_PATTERN) && string != "." && string != ".."
        raise InvalidIdError, "invalid #{field}"
      end

      string
    end

    # Persisted paths must stay relative and segment-safe. Service code can then
    # resolve them under an expected root without accepting absolute paths,
    # parent traversal, empty segments, or embedded NUL bytes.
    def relative_path!(value, field: "path")
      string = value.to_s
      raise ValidationError.new("#{field} must not be empty", code: "invalid_path") if string.empty?
      raise ValidationError.new("#{field} must be relative", code: "invalid_path") if Pathname.new(string).absolute?
      raise ValidationError.new("#{field} contains NUL", code: "invalid_path") if string.include?("\0")

      parts = string.split("/")
      if parts.empty? || parts.any? { |part| part.empty? || part == "." || part == ".." }
        raise ValidationError.new("#{field} contains unsafe path traversal", code: "invalid_path")
      end

      string
    end

    def non_negative_number!(value, field:)
      unless value.is_a?(Numeric) && value >= 0
        raise ValidationError.new("#{field} must be a non-negative number", code: "invalid_number")
      end

      value
    end

    def non_negative_integer!(value, field:)
      unless value.is_a?(Integer) && value >= 0
        raise ValidationError.new("#{field} must be a non-negative integer", code: "invalid_integer")
      end

      value
    end
  end
end
