# cr-drip

[![CI](https://github.com/Gwash3189/cr-drip/actions/workflows/ci.yml/badge.svg)](https://github.com/Gwash3189/cr-drip/actions/workflows/ci.yml)

A lightweight, thread-safe sliding window rate limiting and throttling shard for Crystal with fluent builder, wait budgets, and declarative macro-wrapped instance methods. Zero external dependencies.

## Features

- **Includes-Based Declarative API**: Wrap instance methods with `drip` or `rate_limit` macros including sliding window durations, wait budgets, fallbacks, and lifecycle hooks.
- **Fluent Builder API**: Chain `.key()`, `.allow()`, `.per()`, `.wait()`, `.count()`, `.on_limited()`, `.on_throttled()`, and `.work { ... }`.
- **Direct Function API**: Call `Drip.drip(key, ...)` or `Drip.consume(key, ...)` directly.
- **First-Class Crystal Durations**: Native support for `Time::Span` (e.g. `2.seconds`, `500.milliseconds`, `1.day`), duration strings (`"500ms"`, `"1s"`, `"1m"`, `"1h"`, `"1d"`), or numeric milliseconds.
- **Fail-Fast or Wait Budget**: Reject immediately with `Drip::RateLimitError` or configure `wait:` to throttle/queue callers until the next token arrives.
- **Lifecycle Hooks**: Observe `:limited` and `:throttled` events with custom handlers.
- **Thread-Safe**: Monotonic timing (`Time.instant`) with `Mutex` synchronization across concurrent fibers.

## Installation

Add it to your `shard.yml`:

```yaml
dependencies:
  cr-drip:
    github: Gwash3189/cr-drip
    version: ~> 0.1.0
```

Then run:

```bash
shards install
```

And require it:

```crystal
require "cr-drip"
```

## Usage

### 1. Includes-Based API (Declarative Method Wrapping)

Include `Drip` into your class to wrap instance methods declaratively:

```crystal
class ApiClient
  include Drip

  drip :fetch_user,
    allow: 10,
    per: 1.second,
    wait: 500.milliseconds,
    key: ->(id : String) { "user:#{id}" },
    fallback: :rate_limit_fallback,
    on_limited: :alert_limited,
    on_throttled: :log_throttled

  def fetch_user(id : String) : String
    # Remote HTTP call or database operation
    "user_#{id}"
  end

  def rate_limit_fallback(error : Drip::RateLimitError) : String
    "cached_fallback"
  end

  def alert_limited(error : Drip::RateLimitError, key : String)
    Log.warn { "Rate limited on #{key}, retry after #{error.retry_after_ms}ms" }
  end

  def log_throttled(wait : Time::Span, key : String)
    Log.info { "Throttling #{key} for #{wait.total_milliseconds}ms" }
  end
end
```

The macro `rate_limit` is also available as an alias for `drip`.

### 2. Fluent Builder API

```crystal
result = Drip.key("api:org-42")
  .allow(100)
  .per(1.minute) # or "1m", 60_000
  .wait(5.seconds)
  .on_throttled { |wait, key| Log.info { "Throttled #{key} for #{wait}" } }
  .on_limited { |err, key| Log.warn { "Exceeded #{key}: #{err.message}" } }
  .work do
    call_external_api
  end
```

### 3. Direct Function API

```crystal
# With a work block:
result = Drip.drip("api:org-42", allow: 10, per: 1.second, wait: 500.milliseconds) do
  call_external_api
end

# Alias RateLimit also supported:
RateLimit.rate_limit("api:org-42", allow: 10, per: 1.second) do
  call_external_api
end
```

### 4. Consuming Tokens Without a Block

```crystal
# Via builder
status = Drip.key("user:123").allow(10).per(1.minute).consume(1)
puts status.remaining # 9

# Direct module call
next_status = Drip.consume("user:123", allow: 10, per: 1.minute, count: 2)
puts next_status.remaining # 7
```

### 5. Resetting State

```crystal
# Reset a specific key
Drip.reset("api:org-42")
Drip.key("api:org-42").reset

# Reset all rate limit buckets
Drip.reset_all
```

## Options Reference

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `allow` | `Int32` | `10` | Maximum number of allowed tokens within the window. |
| `per` | `Time::Span \| Number \| String` | `1.second` | Duration of the sliding window (`2.seconds`, `500.milliseconds`, `"1s"`, `1000`). |
| `wait` | `Time::Span \| Number \| String` | `0.seconds` | Maximum time to wait for a token before rejecting. |
| `count` | `Int32` | `1` | Token cost per invocation. |
| `key` | `Proc \| Symbol \| String` | `ClassName#method` | Custom rate limit key or key generator. |
| `fallback` | `Symbol \| Proc` | none | Method or proc invoked when rate limited instead of raising. |
| `on_limited` | `Symbol \| Proc` | none | Callback invoked when rate limit is exceeded. |
| `on_throttled` | `Symbol \| Proc` | none | Callback invoked when execution is delayed within wait budget. |

## Handlers and Fallbacks

Lifecycle handlers (`on_limited`, `on_throttled`) and fallbacks can be declared with flexible argument signatures:

```crystal
# on_limited: (error, key), (error), or 0 args
def alert_limited(error : Drip::RateLimitError, key : String); end
def alert_limited(error : Drip::RateLimitError); end
def alert_limited; end

# on_throttled: (wait, key), (wait), or 0 args
def log_throttled(wait : Time::Span, key : String); end
def log_throttled(wait : Time::Span); end
def log_throttled; end

# fallback: (error) or 0 args
def rate_limit_fallback(error : Drip::RateLimitError); end
def rate_limit_fallback; end
```

## Supported Method Shapes

The includes-based macro wraps methods while completely preserving:
- Positional, optional, and default arguments
- Named arguments and keyword arguments
- Splat (`*args`) and double-splat (`**options`) parameters
- Yield-based blocks and typed captured blocks
- Private and protected method visibilities
- Method names ending in `?` or `!`

## Development

```bash
shards install
crystal spec --error-on-warnings
crystal tool format --check src spec
```

## License

MIT License. Copyright (c) 2026 Adam Beck.
