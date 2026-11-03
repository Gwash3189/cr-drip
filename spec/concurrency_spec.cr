require "./spec_helper"

describe "Drip concurrency" do
  describe "concurrent token acquisition" do
    it "safely limits concurrent requests across multiple fibers" do
      key = "concurrent-limit"
      allow = 5
      total_fibers = 15
      channel = Channel(Bool).new(total_fibers)

      total_fibers.times do
        spawn do
          begin
            Drip.drip(key, allow: allow, per: 1.second) do
              channel.send(true)
            end
          rescue Drip::RateLimitError
            channel.send(false)
          end
        end
      end

      results = Array.new(total_fibers) { channel.receive }
      successes = results.count(true)
      failures = results.count(false)

      successes.should eq(allow)
      failures.should eq(total_fibers - allow)
    end

    it "staggers concurrent fibers with wait budget" do
      key = "concurrent-stagger"
      allow = 2
      total_fibers = 4
      channel = Channel(Int32).new(total_fibers)

      total_fibers.times do |i|
        spawn do
          Drip.drip(key, allow: allow, per: 50.milliseconds, wait: 250.milliseconds) do
            channel.send(i)
          end
        end
      end

      results = Array.new(total_fibers) { channel.receive }
      results.size.should eq(total_fibers)
    end

    it "safely isolates distinct keys across concurrent fibers" do
      channel = Channel(String).new(10)

      5.times do |i|
        spawn do
          res = Drip.drip("key-A", allow: 5, per: 1.second) { "A-#{i}" }
          channel.send(res)
        end
      end

      5.times do |i|
        spawn do
          res = Drip.drip("key-B", allow: 5, per: 1.second) { "B-#{i}" }
          channel.send(res)
        end
      end

      results = Array.new(10) { channel.receive }
      results.count { |r| r.starts_with?("A-") }.should eq(5)
      results.count { |r| r.starts_with?("B-") }.should eq(5)
    end
  end
end
