module Drip
  # Fluent builder for configuring and executing rate-limited operations.
  #
  # ```
  # result = Drip.key("user:42")
  #   .allow(5)
  #   .per(1.second)
  #   .wait(200.milliseconds)
  #   .on_limited { |error, key| Log.warn { "Rate limited #{key}" } }
  #   .on_throttled { |wait, key| Log.info { "Throttled #{key} for #{wait}" } }
  #   .work { fetch_user(42) }
  # ```
  class Builder
    getter key_str : String
    getter allow_val : Int32
    getter per_val : Time::Span
    getter wait_val : Time::Span
    getter count_val : Int32
    getter limited_handlers : Array(Proc(RateLimitError, String, Nil))
    getter throttled_handlers : Array(Proc(Time::Span, String, Nil))
    getter registry : Registry

    def initialize(
      @key_str : String = "default",
      @allow_val : Int32 = 10,
      @per_val : Time::Span = 1.second,
      @wait_val : Time::Span = Time::Span.zero,
      @count_val : Int32 = 1,
      @limited_handlers : Array(Proc(RateLimitError, String, Nil)) = [] of Proc(RateLimitError, String, Nil),
      @throttled_handlers : Array(Proc(Time::Span, String, Nil)) = [] of Proc(Time::Span, String, Nil),
      @registry : Registry = Drip.default_registry,
    )
    end

    # Sets the rate limit key.
    def key(key : String) : Builder
      Registry.validate_key!(key)
      Builder.new(
        key_str: key,
        allow_val: @allow_val,
        per_val: @per_val,
        wait_val: @wait_val,
        count_val: @count_val,
        limited_handlers: @limited_handlers.dup,
        throttled_handlers: @throttled_handlers.dup,
        registry: @registry
      )
    end

    # Alias for `#key`.
    def for(key : String) : Builder
      self.key(key)
    end

    # Sets the maximum allowed tokens per sliding window.
    def allow(count : Int32) : Builder
      Registry.validate_allow!(count)
      Builder.new(
        key_str: @key_str,
        allow_val: count,
        per_val: @per_val,
        wait_val: @wait_val,
        count_val: @count_val,
        limited_handlers: @limited_handlers.dup,
        throttled_handlers: @throttled_handlers.dup,
        registry: @registry
      )
    end

    # Sets the sliding window duration.
    # Accepts native `Time::Span` (e.g. `2.seconds`, `500.milliseconds`, `1.day`),
    # numbers (milliseconds), or duration strings (`"500ms"`, `"1s"`, `"1m"`).
    def per(duration : Time::Span | Number | String) : Builder
      parsed = Drip.parse_duration(duration, "per")
      Builder.new(
        key_str: @key_str,
        allow_val: @allow_val,
        per_val: parsed,
        wait_val: @wait_val,
        count_val: @count_val,
        limited_handlers: @limited_handlers.dup,
        throttled_handlers: @throttled_handlers.dup,
        registry: @registry
      )
    end

    # Sets the maximum wait / throttle budget.
    # Accepts native `Time::Span` (e.g. `500.milliseconds`), numbers, or duration strings.
    def wait(duration : Time::Span | Number | String) : Builder
      parsed = Drip.parse_wait(duration)
      Builder.new(
        key_str: @key_str,
        allow_val: @allow_val,
        per_val: @per_val,
        wait_val: parsed,
        count_val: @count_val,
        limited_handlers: @limited_handlers.dup,
        throttled_handlers: @throttled_handlers.dup,
        registry: @registry
      )
    end

    # Sets the number of tokens to acquire per execution.
    def count(tokens : Int32) : Builder
      Builder.new(
        key_str: @key_str,
        allow_val: @allow_val,
        per_val: @per_val,
        wait_val: @wait_val,
        count_val: tokens,
        limited_handlers: @limited_handlers.dup,
        throttled_handlers: @throttled_handlers.dup,
        registry: @registry
      )
    end

    # Registers a callback invoked when a rate limit is exceeded.
    def on_limited(&block : RateLimitError, String -> Nil) : Builder
      handlers = @limited_handlers.dup
      handlers << block
      Builder.new(
        key_str: @key_str,
        allow_val: @allow_val,
        per_val: @per_val,
        wait_val: @wait_val,
        count_val: @count_val,
        limited_handlers: handlers,
        throttled_handlers: @throttled_handlers.dup,
        registry: @registry
      )
    end

    # Registers a Proc callback invoked when a rate limit is exceeded.
    def on_limited(proc : Proc(RateLimitError, String, Nil)) : Builder
      on_limited(&proc)
    end

    # Registers a single-argument Proc callback invoked when a rate limit is exceeded.
    def on_limited(proc : Proc(RateLimitError, Nil)) : Builder
      on_limited { |err, _| proc.call(err) }
    end

    # Registers a callback invoked when work must be throttled / delayed.
    def on_throttled(&block : Time::Span, String -> Nil) : Builder
      handlers = @throttled_handlers.dup
      handlers << block
      Builder.new(
        key_str: @key_str,
        allow_val: @allow_val,
        per_val: @per_val,
        wait_val: @wait_val,
        count_val: @count_val,
        limited_handlers: @limited_handlers.dup,
        throttled_handlers: handlers,
        registry: @registry
      )
    end

    # Registers a Proc callback invoked when work must be throttled / delayed.
    def on_throttled(proc : Proc(Time::Span, String, Nil)) : Builder
      on_throttled(&proc)
    end

    # Registers a single-argument Proc callback invoked when work must be throttled / delayed.
    def on_throttled(proc : Proc(Time::Span, Nil)) : Builder
      on_throttled { |wait, _| proc.call(wait) }
    end

    # Registers an event handler for `:limited` or `:throttled`.
    def on(event : Symbol | String, &block : RateLimitError | Time::Span, String -> Nil) : Builder
      case event.to_s
      when "limited"
        on_limited { |err, k| block.call(err, k) }
      when "throttled"
        on_throttled { |wait, k| block.call(wait, k) }
      else
        raise ArgumentError.new("Unsupported Drip event '#{event}', expected :limited or :throttled")
      end
    end

    # Returns the remaining tokens for this builder's configured key and window.
    def remaining : Int32
      @registry.remaining(@key_str, @allow_val, @per_val)
    end

    # Consumes tokens without executing a work block, returning the rate limit `Status`.
    def consume(count : Int32? = nil) : Status
      tokens = count || @count_val

      combined_limited = if @limited_handlers.empty?
                           nil
                         else
                           ->(err : RateLimitError, k : String) {
                             @limited_handlers.each(&.call(err, k))
                             nil
                           }
                         end

      combined_throttled = if @throttled_handlers.empty?
                             nil
                           else
                             ->(wait : Time::Span, k : String) {
                               @throttled_handlers.each(&.call(wait, k))
                               nil
                             }
                           end

      @registry.acquire(
        key: @key_str,
        allow: @allow_val,
        per: @per_val,
        wait: @wait_val,
        count: tokens,
        on_limited: combined_limited,
        on_throttled: combined_throttled
      )
    end

    # Executes the given work block protected by this builder's configuration.
    def work(&block : -> T) : T forall T
      execute(&block)
    end

    # Alias for `#work`.
    def run(&block : -> T) : T forall T
      execute(&block)
    end

    # Alias for `#work`.
    def execute(&block : -> T) : T forall T
      consume(@count_val)
      yield
    end

    # Resets the tracked bucket for this builder's key (or an explicit key).
    def reset(key : String? = nil) : Bool
      @registry.reset(key || @key_str)
    end

    # Clears all tracked rate limit buckets in the registry.
    def reset_all : Nil
      @registry.reset_all
    end
  end
end
