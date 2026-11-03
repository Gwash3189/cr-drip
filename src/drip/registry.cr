module Drip
  # Thread-safe coordinator for keyed sliding window rate limiting.
  class Registry
    def initialize
      @mutex = Mutex.new
      @buckets = Hash(String, Array(Time::Instant)).new
    end

    # Validates that a rate limit key is a non-empty, non-whitespace string.
    def self.validate_key!(key : String) : Nil
      if key.empty? || key.strip.empty?
        raise KeyError.new(key)
      end
    end

    # Validates that allow is at least 1.
    def self.validate_allow!(allow : Int32) : Nil
      if allow < 1
        raise ArgumentError.new("allow must be an integer of at least 1")
      end
    end

    # Validates that requested token count is valid.
    def self.validate_count!(count : Int32, allow : Int32) : Nil
      if count < 1
        raise ArgumentError.new("token count must be an integer of at least 1")
      end
      if count > allow
        raise ArgumentError.new("token count (#{count}) cannot exceed allow (#{allow})")
      end
    end

    # Attempts to acquire `count` tokens for `key` within the sliding window.
    # If available, tokens are consumed immediately.
    # If unavailable but within `wait`, the calling fiber is throttled until tokens become available.
    # If unavailable and exceeds `wait`, raises `RateLimitError`.
    def acquire(
      key : String,
      allow : Int32,
      per : Time::Span,
      wait : Time::Span = Time::Span.zero,
      count : Int32 = 1,
      on_limited : Proc(RateLimitError, String, Nil)? = nil,
      on_throttled : Proc(Time::Span, String, Nil)? = nil,
    ) : Status
      Registry.validate_key!(key)
      Registry.validate_allow!(allow)
      Registry.validate_count!(count, allow)

      action, error, retry_after, remaining = @mutex.synchronize do
        timestamps = (@buckets[key] ||= [] of Time::Instant)
        now = Time.instant

        # Prune expired timestamps
        cutoff = now - per
        timestamps.reject! { |t| t <= cutoff }

        active_count = timestamps.size
        if active_count + count <= allow
          count.times { timestamps << now }
          rem = Math.max(0, allow - timestamps.size)
          {:immediate, nil, Time::Span.zero, rem}
        else
          unblock_index = active_count + count - allow - 1
          blocking_time = timestamps[unblock_index]? || now
          available_at = blocking_time + per
          diff = available_at - now
          diff = 1.millisecond if diff <= Time::Span.zero

          if wait <= Time::Span.zero || diff > wait
            err = RateLimitError.new(key, diff)
            {:limited, err, diff, 0}
          else
            count.times { timestamps << available_at }
            {:throttled, nil, diff, 0}
          end
        end
      end

      case action
      when :immediate
        Status.new(key, remaining, Time::Span.zero)
      when :limited
        err = error.not_nil!
        on_limited.try &.call(err, key)
        raise err
      when :throttled
        wait_duration = retry_after.not_nil!
        on_throttled.try &.call(wait_duration, key)
        sleep wait_duration

        rem = @mutex.synchronize do
          if ts = @buckets[key]?
            now_after = Time.instant
            cutoff_after = now_after - per
            ts.reject! { |t| t <= cutoff_after }
            Math.max(0, allow - ts.size)
          else
            allow
          end
        end

        Status.new(key, rem, wait_duration)
      else
        raise "Unexpected action #{action}"
      end
    end

    # Returns the remaining available tokens for `key` without consuming any.
    def remaining(key : String, allow : Int32, per : Time::Span) : Int32
      Registry.validate_key!(key)
      Registry.validate_allow!(allow)

      @mutex.synchronize do
        if timestamps = @buckets[key]?
          now = Time.instant
          cutoff = now - per
          timestamps.reject! { |t| t <= cutoff }
          Math.max(0, allow - timestamps.size)
        else
          allow
        end
      end
    end

    # Evicts tracked bucket for `key`. Returns true if it existed.
    def reset(key : String) : Bool
      Registry.validate_key!(key)
      @mutex.synchronize do
        !@buckets.delete(key).nil?
      end
    end

    # Clears all tracked rate limit buckets across all keys.
    def reset_all : Nil
      @mutex.synchronize do
        @buckets.clear
      end
    end

    # Returns the count of currently tracked keys.
    def size : Int32
      @mutex.synchronize { @buckets.size }
    end
  end
end
