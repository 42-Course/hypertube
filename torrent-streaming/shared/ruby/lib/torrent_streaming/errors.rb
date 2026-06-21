# frozen_string_literal: true

# Shared domain exceptions for the Ruby contract layer. Errors carry stable
# codes so API responses, workers, and tests can distinguish validation,
# persistence, and missing-record failures without parsing messages.
module TorrentStreaming
  class DomainError < StandardError
    attr_reader :code

    def initialize(message, code:)
      super(message)
      @code = code
    end
  end

  class ValidationError < DomainError
    def initialize(message, code: "validation_error")
      super(message, code: code)
    end
  end

  class InvalidMagnetError < ValidationError
    def initialize(message = "invalid magnet")
      super(message, code: "invalid_magnet")
    end
  end

  class InvalidIdError < ValidationError
    def initialize(message = "invalid id")
      super(message, code: "invalid_id")
    end
  end

  class InvalidTransitionError < ValidationError
    def initialize(message = "invalid state transition")
      super(message, code: "invalid_transition")
    end
  end

  class CorruptJsonError < DomainError
    attr_reader :path, :corrupt_path

    def initialize(path:, corrupt_path:, cause_message:)
      super("corrupt JSON at #{path}: #{cause_message}", code: "corrupt_json")
      @path = path
      @corrupt_path = corrupt_path
    end
  end

  class SchemaVersionError < DomainError
    def initialize(message = "unsupported schema_version")
      super(message, code: "unsupported_schema_version")
    end
  end

  class NotFoundError < DomainError
    def initialize(message = "record not found")
      super(message, code: "not_found")
    end
  end
end
