require "./spec_helper"

describe "Drip duration parsing" do
  describe "native Crystal Time::Span durations" do
    it "passes through Time::Span instances directly" do
      Drip.parse_duration(2.seconds).should eq(2.seconds)
      Drip.parse_duration(500.milliseconds).should eq(500.milliseconds)
      Drip.parse_duration(1.minute).should eq(1.minute)
      Drip.parse_duration(3.hours).should eq(3.hours)
      Drip.parse_duration(1.day).should eq(1.day)
    end

    it "handles wait Time::Span durations including zero" do
      Drip.parse_wait(Time::Span.zero).should eq(Time::Span.zero)
      Drip.parse_wait(250.milliseconds).should eq(250.milliseconds)
      Drip.parse_wait(nil).should eq(Time::Span.zero)
    end

    it "rejects non-positive Time::Span for per" do
      expect_raises(ArgumentError, /must be greater than 0/) do
        Drip.parse_duration(Time::Span.zero)
      end

      expect_raises(ArgumentError, /must be greater than 0/) do
        Drip.parse_duration(-1.second)
      end
    end

    it "rejects negative Time::Span for wait" do
      expect_raises(ArgumentError, /must be non-negative/) do
        Drip.parse_wait(-10.milliseconds)
      end
    end
  end

  describe "human-readable duration strings" do
    it "parses ms, s, m, h, and d duration units" do
      Drip.parse_duration("250ms").should eq(250.milliseconds)
      Drip.parse_duration("2s").should eq(2.seconds)
      Drip.parse_duration("1m").should eq(1.minute)
      Drip.parse_duration("1h").should eq(1.hour)
      Drip.parse_duration("1d").should eq(1.day)
    end

    it "supports decimal / fractional values" do
      Drip.parse_duration("1.5s").should eq(1500.milliseconds)
      Drip.parse_duration("0.5m").should eq(30.seconds)
    end

    it "trims leading and trailing whitespace" do
      Drip.parse_duration("  500ms  ").should eq(500.milliseconds)
    end

    it "parses wait duration strings" do
      Drip.parse_wait("0ms").should eq(0.milliseconds)
      Drip.parse_wait("500ms").should eq(500.milliseconds)
    end

    it "rejects invalid duration strings" do
      expect_raises(ArgumentError, /Invalid duration string/) do
        Drip.parse_duration("invalid")
      end

      expect_raises(ArgumentError, /Invalid duration string/) do
        Drip.parse_duration("100years")
      end

      expect_raises(ArgumentError, /Invalid duration string/) do
        Drip.parse_duration("")
      end
    end
  end

  describe "numeric durations (milliseconds)" do
    it "treats numbers as milliseconds" do
      Drip.parse_duration(100).should eq(100.milliseconds)
      Drip.parse_duration(2500).should eq(2500.milliseconds)
    end

    it "parses wait numbers" do
      Drip.parse_wait(0).should eq(0.milliseconds)
      Drip.parse_wait(500).should eq(500.milliseconds)
    end

    it "rejects non-positive numbers for per" do
      expect_raises(ArgumentError, /must be a positive number/) do
        Drip.parse_duration(0)
      end

      expect_raises(ArgumentError, /must be a positive number/) do
        Drip.parse_duration(-5)
      end
    end

    it "rejects negative numbers for wait" do
      expect_raises(ArgumentError, /must be a non-negative number/) do
        Drip.parse_wait(-1)
      end
    end
  end
end
