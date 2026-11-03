require "./drip/version"
require "./drip/errors"
require "./drip/duration"
require "./drip/status"
require "./drip/registry"
require "./drip/builder"
require "./drip/macros"

module Drip
  @@default_registry = Registry.new

  # Returns the global default registry.
  def self.default_registry : Registry
    @@default_registry
  end

  # Internal direct execution with work block.
  def self.__execute_drip(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
    wait : Time::Span | Number | String = Time::Span.zero,
    count : Int32 = 1,
    on_limited : Proc(RateLimitError, String, Nil)? = nil,
    on_throttled : Proc(Time::Span, String, Nil)? = nil,
    &block : -> T
  ) : T forall T
    per_span = parse_duration(per, "per")
    wait_span = parse_wait(wait)

    default_registry.acquire(
      key: key,
      allow: allow,
      per: per_span,
      wait: wait_span,
      count: count,
      on_limited: on_limited,
      on_throttled: on_throttled
    )

    yield
  end

  # Internal direct execution without work block (consumes token).
  def self.__execute_drip(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
    wait : Time::Span | Number | String = Time::Span.zero,
    count : Int32 = 1,
    on_limited : Proc(RateLimitError, String, Nil)? = nil,
    on_throttled : Proc(Time::Span, String, Nil)? = nil,
  ) : Status
    consume(
      key: key,
      allow: allow,
      per: per,
      wait: wait,
      count: count,
      on_limited: on_limited,
      on_throttled: on_throttled
    )
  end

  # Executes the given work block protected by sliding window rate limiting.
  def self.drip(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
    wait : Time::Span | Number | String = Time::Span.zero,
    count : Int32 = 1,
    on_limited : Proc(RateLimitError, String, Nil)? = nil,
    on_throttled : Proc(Time::Span, String, Nil)? = nil,
    &block : -> T
  ) : T forall T
    __execute_drip(
      key: key,
      allow: allow,
      per: per,
      wait: wait,
      count: count,
      on_limited: on_limited,
      on_throttled: on_throttled,
      &block
    )
  end

  # Consumes tokens without executing a work block, returning the rate limit `Status`.
  def self.drip(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
    wait : Time::Span | Number | String = Time::Span.zero,
    count : Int32 = 1,
    on_limited : Proc(RateLimitError, String, Nil)? = nil,
    on_throttled : Proc(Time::Span, String, Nil)? = nil,
  ) : Status
    __execute_drip(
      key: key,
      allow: allow,
      per: per,
      wait: wait,
      count: count,
      on_limited: on_limited,
      on_throttled: on_throttled
    )
  end

  # Alias for `Drip.drip`.
  def self.rate_limit(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
    wait : Time::Span | Number | String = Time::Span.zero,
    count : Int32 = 1,
    on_limited : Proc(RateLimitError, String, Nil)? = nil,
    on_throttled : Proc(Time::Span, String, Nil)? = nil,
    &block : -> T
  ) : T forall T
    __execute_drip(
      key: key,
      allow: allow,
      per: per,
      wait: wait,
      count: count,
      on_limited: on_limited,
      on_throttled: on_throttled,
      &block
    )
  end

  # Alias for `Drip.drip` without work block.
  def self.rate_limit(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
    wait : Time::Span | Number | String = Time::Span.zero,
    count : Int32 = 1,
    on_limited : Proc(RateLimitError, String, Nil)? = nil,
    on_throttled : Proc(Time::Span, String, Nil)? = nil,
  ) : Status
    __execute_drip(
      key: key,
      allow: allow,
      per: per,
      wait: wait,
      count: count,
      on_limited: on_limited,
      on_throttled: on_throttled
    )
  end

  # Consumes `count` tokens without a work block and returns current `Status`.
  def self.consume(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
    wait : Time::Span | Number | String = Time::Span.zero,
    count : Int32 = 1,
    on_limited : Proc(RateLimitError, String, Nil)? = nil,
    on_throttled : Proc(Time::Span, String, Nil)? = nil,
  ) : Status
    per_span = parse_duration(per, "per")
    wait_span = parse_wait(wait)

    default_registry.acquire(
      key: key,
      allow: allow,
      per: per_span,
      wait: wait_span,
      count: count,
      on_limited: on_limited,
      on_throttled: on_throttled
    )
  end

  # Returns the remaining available tokens for `key` within its sliding window.
  def self.remaining(
    key : String,
    allow : Int32 = 10,
    per : Time::Span | Number | String = 1.second,
  ) : Int32
    per_span = parse_duration(per, "per")
    default_registry.remaining(key, allow, per_span)
  end

  # Resets the tracked bucket for `key`.
  def self.reset(key : String) : Bool
    default_registry.reset(key)
  end

  # Clears all tracked rate limit buckets across all keys.
  def self.reset_all : Nil
    default_registry.reset_all
  end

  # Starts a fluent `Builder` targeting `key`.
  def self.key(key : String) : Builder
    Builder.new(registry: default_registry).key(key)
  end

  # Alias for `Drip.key`.
  def self.for(key : String) : Builder
    self.key(key)
  end
end

# Alias matching TypeScript Drip package
RateLimit = Drip
