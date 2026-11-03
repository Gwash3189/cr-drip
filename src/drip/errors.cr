module Drip
  # Base error class for all `Drip` exceptions.
  class Error < Exception
  end

  # Raised when a rate limit key is invalid (e.g. empty or whitespace-only).
  class KeyError < Error
    getter key : String

    def initialize(@key : String)
      super("Drip key must be a non-empty string, got: #{@key.inspect}")
    end
  end

  # Raised when a rate limit is exceeded and cannot be satisfied within the wait budget.
  class RateLimitError < Error
    getter key : String
    getter retry_after : Time::Span

    def initialize(@key : String, @retry_after : Time::Span)
      ms = (@retry_after.total_milliseconds <= 0 ? 1 : @retry_after.total_milliseconds).ceil.to_i
      super("Rate limit exceeded for key \"#{@key}\". Retry after #{ms}ms.")
    end

    def retry_after_ms : Float64
      @retry_after.total_milliseconds
    end
  end

  # Raised by the builder API when execution is requested without providing a work block.
  class MissingWorkError < Error
    def initialize
      super("No work block provided. Call `.work { ... }` or `.run { ... }` before executing.")
    end
  end
end
