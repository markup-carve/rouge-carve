# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rouge::Lexers::Carve do
  def lex(source)
    described_class.new.lex(source).map { |token, value| [token.qualname, value] }
  end

  cases = [
    ['U-001', "text\n# Heading\n", nil, 'Generic.Heading'],
    ['U-014', "- first\n+\n> note\n", 'Punctuation', 'Operator'],
    ['U-031', "{.note}\n\nParagraph.\n", nil, 'Name.Attribute'],
    ['U-032', "{.a\n .b}\nParagraph.\n", nil, 'Name.Attribute'],
    ['U-044', "para\n\n___\n", nil, 'Operator'],
    ['U-045', "* * *\n\n- - -\n", 'Punctuation', nil],
    ['U-049', "```\ncode\n   ```\nafter\n", 'Literal.String.Backtick', nil],
    ['U-050', "%%%\nhidden\n%%% visible?\nafter\n", 'Comment', nil],
    ['U-055', "| a | b |\n|---|--:|\n| 1 | 2 |\n", 'Punctuation', 'Operator'],
    ['U-056', "|=< a |=> b |=~ c |\n", 'Operator', 'Name.Attribute'],
    ['U-063', "| a | b |\n\n^ Caption\n", 'Punctuation', nil],
    ['U-065', "an _underlined_ word\n", nil, 'Generic.Emph'],
    ['U-066', "a ~struck~ word\n", nil, 'Generic.Deleted'],
    ['U-067', "a =marked= word\n", nil, 'Generic.Inserted'],
    ['U-068', "/*bold italic*/ and */bold italic/*\n", 'Generic.Strong', nil],
    ['U-069', "{~old~>new~}\n", 'Generic.Deleted', 'Operator'],
    ['U-101', "= Heading\n", 'Generic.Heading', nil],
    ['U-103', "a. one\nb. two\n", 'Literal.Number.Integer', nil],
    ['U-104', "::: > \"T\"\nquoted\n:::\n", 'Literal.String.Double', nil],
    ['U-105', "```=html \"T\"\n<b>x</b>\n```\n", 'Keyword.Type', nil],
    ['U-106', ":: term\nmore term text\n: first description\n", 'Generic.Heading', nil],
    ['U-107', "| a | b |\n^ first\n^ second\n", 'Generic.Subheading', nil],
    ['U-289', "{{ a.crv @shift:1 }}\n", 'Name.Namespace', nil],
    ['CC-112', "a\n%% #region x\nb", 'Comment.Special', nil],
    ['CC-893', "|=< a |\n", 'Operator', 'Name.Attribute'],
    ['CC-894', "|={<} a |\n", 'Name.Attribute', nil]
  ]

  cases.each do |id, source, present, absent|
    it "follows #{id}" do
      names = lex(source).map(&:first)
      expect(names).to include(present) if present
      expect(names).not_to include(absent) if absent
    end
  end

  it 'keeps a false comment closer and following text in the comment' do
    tokens = lex("%%%\nhidden\n%%% visible?\nafter\n%%%\n")
    expect(tokens.count { |name, _| name == 'Comment.Preproc' }).to eq 2
    expect(tokens.any? { |name, value| name == 'Comment' && value.include?('after') }).to be true
  end

  it 'does not end a fence at a different indentation' do
    tokens = lex("```\ncode\n   ```\nafter\n")
    expect(tokens.any? { |name, value| name == 'Literal.String.Backtick' && value.include?('after') }).to be true
  end

  it 'keeps a plus on a marker line as text' do
    ["- +\n```\nx\n```\n", "> +\n- item\n"].each do |source|
      expect(lex(source).any? { |name, value| name == 'Operator' && value == '+' }).to be false
    end
  end

  it 'colors the retained combined emphasis order' do
    expect(lex('*/bold italic/*').map(&:first)).to include 'Generic.Strong'
  end

  it 'treats a second caret as caption content' do
    tokens = lex("| a | b |\n^ first\n^ second\n")
    expect(tokens.count { |name, value| name == 'Punctuation' && value == '^' }).to eq 1
    expect(tokens.any? { |name, value| name == 'Generic.Subheading' && value.include?('^ second') }).to be true
  end

  it 'registers the public Carve grammar' do
    expect(Rouge::Lexer.find('carve')).to eq described_class
    expect(Rouge::Lexer.find('crv')).to eq described_class
    expect(lex('_u_').map(&:first)).not_to include 'Generic.Emph'
  end

  {
    "***\n" => 'Punctuation',
    '{^sup^}' => 'Generic.Emph',
    '{,sub,}' => 'Generic.Emph',
    '{_under_}' => 'Generic.Emph',
    '{~strike~}' => 'Generic.Deleted',
    '{=mark=}' => 'Generic.Inserted'
  }.each do |source, scope|
    it "colors the 0.2 positive form #{source.inspect}" do
      expect(lex(source).map(&:first)).to include scope
    end
  end
end
