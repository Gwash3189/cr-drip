require "./spec_helper"

describe "Drip::Builder" do
  describe "immediate execution and remaining tokens" do
    it "executes the work block and returns the result immediately" do
      result = Drip.key("allow-immediate")
        .allow(5)
        .per(1.second)
        .work { "ok" }

      result.should eq("ok")
    end

    it "decrements the remaining tokens count" do
      builder = Drip.key("decrement-remaining").allow(3).per(5.seconds)

      builder.work { "first" }
      builder.remaining.should eq(2)

      builder.work { "second" }
      builder.remaining.should eq(1)
    end

    it "isolates rate limits across distinct keys" do
      Drip.key("isolated-key-a")
        .allow(1)
        .per(5.seconds)
        .work { "a" }

      result_b = Drip.key("isolated-key-b")
        .allow(1)
        .per(5.seconds)
        .work { "b" }

      result_b.should eq("b")
    end

    it "replenishes tokens once the sliding window elapses" do
      key = "replenish-after-window"

      Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .work { "first" }

      sleep 40.milliseconds

      second = Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .work { "second" }

      second.should eq("second")
    end
  end

  describe "rate limit exceeded without wait budget" do
    it "rejects immediately with Drip::RateLimitError" do
      key = "exceed-no-wait"

      Drip.key(key)
        .allow(1)
        .per(5.seconds)
        .work { "first" }

      expect_raises(Drip::RateLimitError) do
        Drip.key(key)
          .allow(1)
          .per(5.seconds)
          .work { "second" }
      end
    end

    it "exposes key and positive retry_after on Drip::RateLimitError" do
      key = "error-metadata"

      Drip.key(key)
        .allow(1)
        .per(5.seconds)
        .work { "first" }

      begin
        Drip.key(key)
          .allow(1)
          .per(5.seconds)
          .work { "second" }
        fail "expected RateLimitError"
      rescue ex : Drip::RateLimitError
        ex.key.should eq(key)
        (ex.retry_after > Time::Span.zero).should be_true
        (ex.retry_after_ms > 0).should be_true
      end
    end

    it "does not execute the work block when rejected" do
      key = "no-work-on-reject"
      work_count = 0

      Drip.key(key)
        .allow(1)
        .per(5.seconds)
        .work { work_count += 1 }

      begin
        Drip.key(key)
          .allow(1)
          .per(5.seconds)
          .work { work_count += 1 }
      rescue Drip::RateLimitError
      end

      work_count.should eq(1)
    end

    it "invokes the limited event handler with error and key" do
      key = "limited-event-handler"
      limited_key = ""
      captured_error = nil.as(Drip::RateLimitError?)

      Drip.key(key)
        .allow(1)
        .per(5.seconds)
        .work { "first" }

      begin
        Drip.key(key)
          .allow(1)
          .per(5.seconds)
          .on_limited { |err, k|
            captured_error = err
            limited_key = k
          }
          .work { "second" }
      rescue Drip::RateLimitError
      end

      limited_key.should eq(key)
      captured_error.should_not be_nil
    end

    it "supports .on(:limited) syntax" do
      key = "on-symbol-limited"
      limited_key = ""

      Drip.key(key)
        .allow(1)
        .per(5.seconds)
        .work { "first" }

      begin
        Drip.key(key)
          .allow(1)
          .per(5.seconds)
          .on(:limited) { |_err, k| limited_key = k }
          .work { "second" }
      rescue Drip::RateLimitError
      end

      limited_key.should eq(key)
    end
  end

  describe "rate limit exceeded with wait budget" do
    it "waits for the next available token and executes work when within wait budget" do
      key = "wait-within-budget"

      Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .work { "first" }

      second_result = Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .wait(200.milliseconds)
        .work { "after-wait" }

      second_result.should eq("after-wait")
    end

    it "invokes on_throttled handler with wait duration and key" do
      key = "throttled-handler-test"
      throttled_key = ""
      throttled_wait = Time::Span.zero

      Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .work { "first" }

      Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .wait(200.milliseconds)
        .on_throttled { |wait, k|
          throttled_wait = wait
          throttled_key = k
        }
        .work { "second" }

      throttled_key.should eq(key)
      (throttled_wait > Time::Span.zero).should be_true
    end

    it "supports .on(:throttled) syntax" do
      key = "on-symbol-throttled"
      throttled_key = ""

      Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .work { "first" }

      Drip.key(key)
        .allow(1)
        .per(30.milliseconds)
        .wait(200.milliseconds)
        .on(:throttled) { |_wait, k| throttled_key = k }
        .work { "second" }

      throttled_key.should eq(key)
    end

    it "rejects when wait budget is shorter than required wait" do
      key = "wait-exceeded"

      Drip.key(key)
        .allow(1)
        .per(500.milliseconds)
        .work { "first" }

      expect_raises(Drip::RateLimitError) do
        Drip.key(key)
          .allow(1)
          .per(500.milliseconds)
          .wait(10.milliseconds)
          .work { "second" }
      end
    end
  end

  describe "token consumption without work block (.consume)" do
    it "consumes 1 token by default and returns status" do
      status = Drip.key("consume-default")
        .allow(5)
        .per(1.second)
        .consume

      status.key.should eq("consume-default")
      status.remaining.should eq(4)
      status.retry_after.should eq(Time::Span.zero)
    end

    it "consumes multiple tokens at once" do
      status = Drip.key("consume-multi")
        .allow(5)
        .per(1.second)
        .consume(3)

      status.remaining.should eq(2)
    end

    it "raises ArgumentError when consuming count > allow" do
      expect_raises(ArgumentError, /cannot exceed allow/) do
        Drip.key("consume-too-many")
          .allow(3)
          .per(1.second)
          .consume(4)
      end
    end
  end

  describe "reset and reset_all" do
    it "restores full capacity for a single key with reset" do
      builder = Drip.key("reset-single").allow(1).per(1.day)
      builder.consume
      builder.remaining.should eq(0)

      builder.reset
      builder.remaining.should eq(1)
    end

    it "clears all keys when reset_all is called" do
      b1 = Drip.key("reset-all-1").allow(1).per(1.hour)
      b2 = Drip.key("reset-all-2").allow(1).per(1.hour)

      b1.consume
      b2.consume
      b1.remaining.should eq(0)
      b2.remaining.should eq(0)

      b1.reset_all
      b1.remaining.should eq(1)
      b2.remaining.should eq(1)
    end
  end
end
