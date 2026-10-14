# frozen_string_literal: true

require 'spec_helper'

# A line made of openers that never close used to cost time quadratic in its
# length: `*a ` repeated over 96 KB took 25 s, `{{ a ` over 160 KB more than
# 40. The check is the growth rate rather than a stopwatch reading, so a slow
# or busy machine does not fail it: four times the input must cost well under
# the sixteen times a quadratic scan costs.
RSpec.describe Rouge::Lexers::Carve do
  def cpu_seconds(source)
    2.times.map do
      start = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      described_class.new.lex(source).each {}
      Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - start
    end.min
  end

  ['*a ', '/a ', '=a ', '{{ a ', '{*a ', '{~a ', '/*a ', '^[a ', '[^a '].each do |unit|
    it "lexes a line of unclosed #{unit.strip.inspect} in linear time" do
      small = cpu_seconds(unit * 2_000)
      large = cpu_seconds(unit * 8_000)
      expect(large).to be < [small, 0.01].max * 9
    end
  end
end
