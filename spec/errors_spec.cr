require "./spec_helper"

describe "Drip errors" do
  describe Drip::Error do
    it "inherits from Exception" do
      err = Drip::Error.new("something went wrong")
      err.should be_a(Exception)
    end
  end

  describe Drip::KeyError do
    it "exposes the invalid key" do
      err = Drip::KeyError.new("")
      err.key.should eq("")
      err.message.not_nil!.should contain("must be a non-empty string")
    end
  end

  describe Drip::RateLimitError do
    it "exposes key and retry_after metadata" do
      err = Drip::RateLimitError.new("user:123", 250.milliseconds)
      err.key.should eq("user:123")
      err.retry_after.should eq(250.milliseconds)
      err.retry_after_ms.should eq(250.0)
      err.message.should eq("Rate limit exceeded for key \"user:123\". Retry after 250ms.")
    end

    it "rounds up retry_after_ms ceiling in message" do
      err = Drip::RateLimitError.new("test", 12.3.milliseconds)
      err.message.should eq("Rate limit exceeded for key \"test\". Retry after 13ms.")
    end
  end

  describe Drip::MissingWorkError do
    it "provides a descriptive error message" do
      err = Drip::MissingWorkError.new
      err.message.not_nil!.should contain("No work block provided")
    end
  end
end
