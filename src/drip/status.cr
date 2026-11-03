module Drip
  # Represents the current rate limit status of a key.
  struct Status
    getter key : String
    getter remaining : Int32
    getter retry_after : Time::Span

    def initialize(@key : String, @remaining : Int32, @retry_after : Time::Span = Time::Span.zero)
    end

    # Returns the retry after duration in milliseconds.
    def retry_after_ms : Float64
      @retry_after.total_milliseconds
    end
  end
end
