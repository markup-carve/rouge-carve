# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rouge::Lexers::Carve do
  def kind_at(source, needle)
    at = source.index(needle)
    offset = 0
    described_class.new.lex(source).each do |kind, value|
      offset += value.length
      return kind.qualname if offset > at
    end
    raise "No token for #{needle}"
  end

  ['# a ', '> # a ', "![alt](x.png)\n^ cap ", "> ![alt](x.png)\n> ^ cap "].each do |prefix|
    ['`x %% b` c', '``x %% b`` c', '!`x %% b` c', '$`x %% b` c', '`x %% b', '` x `` y %% hidden', '``x```y %% hidden'].each do |body|
      it "protects the percent run in #{prefix.inspect}#{body}" do
        source = prefix + body + "\n\nplain tail"
        expect(kind_at(source, '%%')).to start_with('Literal')
        expect(kind_at(source, 'plain tail')).not_to match(/Literal.String|Comment/)
      end
    end
    [' ', "\t"].each do |gap|
      it "scopes a trailing comment after code in #{prefix.inspect} with #{gap.inspect}" do
        source = prefix + '`x`' + gap + '%% hidden'
        expect(kind_at(source, '%%')).to start_with('Comment')
      end
    end
  end
  ['# a ', '> # a ', "![alt](x.png)\n^ cap ", "> ![alt](x.png)\n> ^ cap "].each do |prefix|
    [1, 2, 3, 4].each do |slashes|
      it "respects #{slashes} backslashes before code in #{prefix.inspect}" do
        source = prefix + 92.chr * slashes + '`x %% hidden'
        expect(kind_at(source, '%%').start_with?('Comment')).to eq(slashes.odd?)
      end
    end
  end

end
