module Drip
  DURATION_REGEX = /^(\d+(?:\.\d+)?)\s*(ms|s|m|h|d)$/

  # Parses and normalizes a duration input into a strictly positive `Time::Span`.
  # Accepts native Crystal durations (`2.seconds`, `500.milliseconds`, `1.day`),
  # numbers (interpreted as milliseconds), and duration strings (`"500ms"`, `"2s"`, `"1m"`, `"1h"`, `"1d"`).
  def self.parse_duration(input : Time::Span | Number | String, field_name : String = "per") : Time::Span
    span = case input
           when Time::Span
             input
           when Number
             if (input.is_a?(Float) && !input.finite?) || input <= 0
               raise ArgumentError.new("#{field_name} must be a positive number")
             end
             input.milliseconds
           when String
             trimmed = input.strip
             match = DURATION_REGEX.match(trimmed)
             unless match
               raise ArgumentError.new("Invalid duration string for #{field_name}: #{input.inspect}")
             end
             val = match[1].to_f
             unit = match[2]
             case unit
             when "ms" then val.milliseconds
             when "s"  then val.seconds
             when "m"  then val.minutes
             when "h"  then val.hours
             when "d"  then val.days
             else
               raise ArgumentError.new("Unsupported duration unit '#{unit}' in #{input.inspect}")
             end
           else
             raise ArgumentError.new("Unsupported #{field_name} type: #{input.class}")
           end

    if span <= Time::Span.zero
      raise ArgumentError.new("#{field_name} duration must be greater than 0")
    end

    span
  end

  # Parses and normalizes a wait duration into a non-negative `Time::Span`.
  # Accepts native Crystal durations (`500.milliseconds`, `Time::Span.zero`),
  # numbers (interpreted as milliseconds), and duration strings.
  def self.parse_wait(input : Time::Span | Number | String | Nil) : Time::Span
    return Time::Span.zero if input.nil?

    span = case input
           when Time::Span
             input
           when Number
             if (input.is_a?(Float) && !input.finite?) || input < 0
               raise ArgumentError.new("wait must be a non-negative number")
             end
             input.milliseconds
           when String
             trimmed = input.strip
             match = DURATION_REGEX.match(trimmed)
             unless match
               raise ArgumentError.new("Invalid duration string for wait: #{input.inspect}")
             end
             val = match[1].to_f
             unit = match[2]
             case unit
             when "ms" then val.milliseconds
             when "s"  then val.seconds
             when "m"  then val.minutes
             when "h"  then val.hours
             when "d"  then val.days
             else
               raise ArgumentError.new("Unsupported duration unit '#{unit}' in #{input.inspect}")
             end
           else
             raise ArgumentError.new("Unsupported wait type: #{input.class}")
           end

    if span < Time::Span.zero
      raise ArgumentError.new("wait duration must be non-negative")
    end

    span
  end
end
