require "./spec_helper"

class UserService
  include Drip

  getter calls = 0
  getter limited_events = [] of String
  getter throttled_events = [] of String

  drip :fetch_user,
    allow: 2,
    per: 50.milliseconds,
    wait: 100.milliseconds,
    key: ->(id : String) { "user:#{id}" },
    on_limited: :on_fetch_limited,
    on_throttled: :on_fetch_throttled

  def fetch_user(id : String) : String
    @calls += 1
    "user_#{id}"
  end

  def on_fetch_limited(error : Drip::RateLimitError, key : String)
    @limited_events << key
  end

  def on_fetch_throttled(wait : Time::Span, key : String)
    @throttled_events << key
  end
end

class FallbackService
  include Drip

  getter calls = 0

  drip :fetch_data,
    allow: 1,
    per: 1.second,
    fallback: :rate_limit_fallback

  def fetch_data(id : String) : String
    @calls += 1
    "live_#{id}"
  end

  def rate_limit_fallback(error : Drip::RateLimitError) : String
    "fallback_for_#{error.key}"
  end
end

class NoArgFallbackService
  include Drip

  getter calls = 0

  drip :compute,
    allow: 1,
    per: 1.second,
    fallback: :fallback_compute

  def compute : Int32
    @calls += 1
    100
  end

  def fallback_compute : Int32
    -1
  end
end

class SymbolKeyService
  include Drip

  getter calls = 0

  drip :process, key: :build_key, allow: 2, per: 1.second

  def process(tenant : String, id : Int32) : String
    @calls += 1
    "#{tenant}:#{id}"
  end

  def build_key(tenant : String, id : Int32) : String
    "tenant-key:#{tenant}:#{id}"
  end
end

class DefaultKeyService
  include Drip

  getter calls = 0

  drip :calculate, allow: 2, per: 1.second

  def calculate(x : Int32, y : Int32 = 10) : Int32
    @calls += 1
    x + y
  end
end

class ComplexArgsService
  include Drip

  getter calls = 0

  drip :search,
    allow: 5,
    per: 1.second,
    key: ->(query : String, tags : Array(String)) { "#{query}:#{tags.join(",")}" }

  def search(query : String, tags : Array(String), *, page : Int32 = 1, **options) : String
    @calls += 1
    "query=#{query},tags=#{tags.size},page=#{page},opt=#{options.size}"
  end
end

class BlockService
  include Drip

  drip :transform, allow: 2, per: 1.second

  def transform(value : String, &)
    yield value.upcase
  end
end

class ConstructedService
  include Drip

  getter prefix : String

  drip :greet, allow: 2, per: 1.second

  def initialize(@prefix : String)
  end

  def greet(name : String) : String
    "#{@prefix}, #{name}!"
  end
end

describe "Drip macro inclusion (includes-based API)" do
  describe "instance method wrapping with proc key" do
    it "allows calls within the configured rate limit" do
      service = UserService.new
      service.fetch_user("1").should eq("user_1")
      service.fetch_user("1").should eq("user_1")
      service.calls.should eq(2)
    end

    it "throttles calls within wait budget and triggers callbacks" do
      service = UserService.new
      service.fetch_user("42")
      service.fetch_user("42")

      # Third call should throttle within 100ms wait budget
      start_time = Time.instant
      res = service.fetch_user("42")
      elapsed = Time.instant - start_time

      res.should eq("user_42")
      (elapsed >= 20.milliseconds).should be_true
      service.throttled_events.should contain("user:42")
    end

    it "isolates limits by distinct generated keys" do
      service = UserService.new
      service.fetch_user("A")
      service.fetch_user("A")

      # Different key "user:B" should not be limited
      service.fetch_user("B").should eq("user_B")
    end
  end

  describe "fallback execution on rate limit" do
    it "invokes fallback taking RateLimitError" do
      service = FallbackService.new
      service.fetch_data("item-1").should eq("live_item-1")

      # Second call exceeds limit without wait budget
      result = service.fetch_data("item-1")
      result.should contain("fallback_for_")
    end

    it "invokes fallback taking zero arguments" do
      service = NoArgFallbackService.new
      service.compute.should eq(100)

      # Exceeded limit invokes 0-arg fallback
      service.compute.should eq(-1)
    end
  end

  describe "symbol key generator" do
    it "derives key from instance method" do
      service = SymbolKeyService.new
      service.process("acme", 101).should eq("acme:101")
      service.process("acme", 101).should eq("acme:101")

      expect_raises(Drip::RateLimitError) do
        service.process("acme", 101)
      end
    end
  end

  describe "default key generator" do
    it "generates default key from class name, method, and arguments" do
      service = DefaultKeyService.new
      service.calculate(5).should eq(15)
      service.calculate(5).should eq(15)

      expect_raises(Drip::RateLimitError) do
        service.calculate(5)
      end

      # Different argument has different default key
      service.calculate(7).should eq(17)
    end
  end

  describe "complex method signatures" do
    it "preserves positional, named, and double-splat parameters" do
      service = ComplexArgsService.new
      res = service.search("crystal", ["fast", "typed"], page: 2, sort: "desc")
      res.should eq("query=crystal,tags=2,page=2,opt=1")
    end
  end

  describe "block forwarding" do
    it "preserves yield-based blocks" do
      service = BlockService.new
      transformed = service.transform("crystal") { |val| "#{val}!" }
      transformed.should eq("CRYSTAL!")
    end
  end

  describe "class constructor preservation" do
    it "preserves custom initialize on including class" do
      service = ConstructedService.new("Welcome")
      service.greet("Alice").should eq("Welcome, Alice!")
    end
  end
end
