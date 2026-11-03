require "./spec_helper"

describe "Drip module methods" do
  describe ".drip with work block" do
    it "acquires a token and returns the block result" do
      result = Drip.drip("direct-block", allow: 3, per: 1.second) do
        "hello-drip"
      end

      result.should eq("hello-drip")
    end

    it "supports duration strings and numbers" do
      result = Drip.drip("string-durations", allow: 2, per: "500ms", wait: 100) do
        "parsed"
      end

      result.should eq("parsed")
    end

    it "invokes on_limited and on_throttled callbacks" do
      events = [] of String
      key = "module-events"

      Drip.drip(key, allow: 1, per: 30.milliseconds) { "first" }

      Drip.drip(
        key,
        allow: 1,
        per: 30.milliseconds,
        wait: 100.milliseconds,
        on_throttled: ->(_w : Time::Span, _k : String) {
          events << "throttled"
          nil
        }
      ) { "second" }

      begin
        Drip.drip(
          key,
          allow: 1,
          per: 5.seconds,
          on_limited: ->(_err : Drip::RateLimitError, _k : String) {
            events << "limited"
            nil
          }
        ) { "third" }
      rescue Drip::RateLimitError
      end

      events.should eq(["throttled", "limited"])
    end
  end

  describe ".drip without work block" do
    it "consumes a token and returns Status" do
      status = Drip.drip("without-block", allow: 4, per: 10.seconds)
      status.should be_a(Drip::Status)
      status.key.should eq("without-block")
      status.remaining.should eq(3)
    end
  end

  describe ".rate_limit alias" do
    it "acts as an alias for .drip" do
      result = RateLimit.rate_limit("alias-key", allow: 2, per: 1.second) do
        "alias-result"
      end
      result.should eq("alias-result")

      status = RateLimit.rate_limit("alias-key", allow: 2, per: 1.second)
      status.remaining.should eq(0)
    end
  end

  describe ".consume and .remaining" do
    it "consumes specified number of tokens" do
      status = Drip.consume("consume-test", allow: 10, per: 1.second, count: 4)
      status.remaining.should eq(6)

      Drip.remaining("consume-test", allow: 10, per: 1.second).should eq(6)
    end
  end

  describe ".reset and .reset_all" do
    it "resets a specific key" do
      Drip.consume("to-reset", allow: 2, per: 1.hour, count: 2)
      Drip.remaining("to-reset", allow: 2, per: 1.hour).should eq(0)

      Drip.reset("to-reset").should be_true
      Drip.remaining("to-reset", allow: 2, per: 1.hour).should eq(2)
    end

    it "resets all keys" do
      Drip.consume("to-reset-1", allow: 2, per: 1.hour, count: 2)
      Drip.consume("to-reset-2", allow: 2, per: 1.hour, count: 2)

      Drip.reset_all
      Drip.remaining("to-reset-1", allow: 2, per: 1.hour).should eq(2)
      Drip.remaining("to-reset-2", allow: 2, per: 1.hour).should eq(2)
    end
  end

  describe "key validation" do
    it "rejects empty or whitespace keys" do
      expect_raises(Drip::KeyError) do
        Drip.drip("", allow: 1, per: 1.second) { }
      end

      expect_raises(Drip::KeyError) do
        Drip.drip("   ", allow: 1, per: 1.second) { }
      end
    end
  end
end
