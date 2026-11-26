# frozen_string_literal: true

require 'spec_helper'

# The check is the growth rate rather than a stopwatch reading, so a slow or
# busy machine does not fail it: eight times the input must cost well under
# the 64 times a quadratic scan costs.
RSpec.describe Rouge::Lexers::Carve do
  def cpu_seconds(source)
    2.times.map do
      start = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      described_class.new.lex(source).each {}
      Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - start
    end.min
  end

  # Every `<` tried the autolink body to the end of the line (CC-1485, CC-1486).
  [['<', ''], ['<', 'a'], ['a<', '']].each do |unit, tail|
    it "lexes a line of #{unit.inspect} runs#{" before #{tail.inspect}" unless tail.empty?} in linear time" do
      small = cpu_seconds("#{unit * 4_000}#{tail}\n")
      large = cpu_seconds("#{unit * 32_000}#{tail}\n")
      expect(large).to be < [small, 0.01].max * 20
    end
  end

  it 'keeps a `<` out of an autolink body (C2-I-122, C2-I-123)' do
    tokens = described_class.new.lex("a <b <https://x.y> c <d<e@f.gh>\n").map { |t, v| [t.qualname, v] }
    expect(tokens).to include(['Name.Tag', 'https://x.y'], ['Name.Tag', 'e@f.gh'])
    expect(tokens.map(&:last).join).to eq("a <b <https://x.y> c <d<e@f.gh>\n")
  end
end
