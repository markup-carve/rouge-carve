# frozen_string_literal: true

require 'spec_helper'

# A block marker opens a block only where the engine lets it: list markers and
# captions do not interrupt a paragraph, and some markers need more than their
# first character.
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

  describe 'under a paragraph line' do
    it 'reads a bullet as text' do
      expect(kind_at("para\n- not a list\n", '-')).to eq 'Text'
    end

    it 'reads an ordered marker as text' do
      expect(kind_at("see\n2. not a list\n", '2.')).to eq 'Text'
    end

    it 'reads a caption marker as text' do
      expect(kind_at("para\n^ not a caption\n", 'not')).to eq 'Text'
    end

    it 'reads an unclosed fence as text' do
      expect(kind_at("intro\n```js\ncode\n", 'code')).to eq 'Text'
    end

    {
      'a heading' => ["para\n# H\n", 'H', 'Generic.Heading'],
      'a quote' => ["para\n> q\n", '>', 'Punctuation'],
      'a table row' => ["para\n| a | b |\n", '|', 'Punctuation'],
      'a container' => ["para\n::: note\nx\n:::\n", 'note', 'Keyword.Namespace'],
      'a closed fence' => ["para\n```js\ncode\n```\n", 'js', 'Name.Builtin'],
      'a thematic break' => ["para\n---\n", '---', 'Punctuation'],
      'a definition term' => ["para\n:: term\n", 'term', 'Generic.Heading']
    }.each do |what, (source, needle, scope)|
      it "lets #{what} interrupt it" do
        expect(kind_at(source, needle)).to eq scope
      end
    end

    it 'opens a list again after a blank line' do
      expect(kind_at("para\n\n- item\n", '-')).to eq 'Punctuation'
    end
  end

  describe 'under a list item' do
    it 'reads a caption marker as item text' do
      expect(kind_at("- item\n^ not a caption\n", 'not')).to eq 'Text'
    end

    it 'opens the next item' do
      expect(kind_at("- a\n- b\n", '- b')).to eq 'Punctuation'
    end

    it 'opens the next item after a lazy line' do
      expect(kind_at("- a\nlazy\n- b\n", '- b')).to eq 'Punctuation'
    end

    it 'lets a heading interrupt it' do
      expect(kind_at("- a\n# H\n", 'H')).to eq 'Generic.Heading'
    end
  end

  describe 'definition lists' do
    it 'reads a definition after a term that wraps' do
      expect(kind_at(":: A term that\nwraps\n: its definition\n", ': its')).to eq 'Punctuation'
    end

    it 'reads a colon under a paragraph as text' do
      expect(kind_at("para\n: x\n", ': x')).to eq 'Text'
    end
  end

  describe 'paragraphs inside a container' do
    it 'lets a marker at the paragraph column open a sublist' do
      expect(kind_at("- first\n\n  second\n  - nested\n", '- nested')).to eq 'Punctuation'
    end

    it 'lets the next item follow a paragraph inside an item' do
      expect(kind_at("- item\n\n  second para\n- next\n", '- next')).to eq 'Punctuation'
    end

    it 'keeps an indented marker under a document paragraph as text' do
      expect(kind_at("para\n  - c\n", '- c')).to eq 'Text'
    end
  end

  describe 'captions where they attach' do
    it 'reads a caption under an image' do
      expect(kind_at("![alt](i.png)\n^ Caption\n", 'Caption')).to eq 'Generic.Subheading'
    end

    it 'reads a caption under display math' do
      expect(kind_at("$$`E = mc^2`\n^ Equation\n", 'Equation')).to eq 'Generic.Subheading'
    end

    it 'reads a caret line under a paragraph that ends in an image as text' do
      expect(kind_at("Text\n![a](a.jpg)\n^ Figure\n", 'Figure')).to eq 'Text'
    end

    it 'reads a caption under a table' do
      expect(kind_at("| a | b |\n^ cap\n", 'cap')).to eq 'Generic.Subheading'
    end
  end

  describe 'marker shapes' do
    it 'needs a closing pipe for a table row' do
      expect(kind_at("| not a table\n", '|')).to eq 'Text'
      expect(kind_at("|= H | x\n", '|=')).to eq 'Text'
    end

    it 'reads a plus as text, because it is not a bullet' do
      expect(kind_at("+ not item\n", '+')).to eq 'Text'
    end

    it 'reads a word with a period as text, not an alphabetic marker' do
      expect(kind_at("Body.\n", 'Body.')).to eq 'Text'
      expect(kind_at("ab. x\n", 'ab.')).to eq 'Text'
    end

    it 'still reads single-letter and roman markers' do
      expect(kind_at("B. x\n", 'B.')).to eq 'Literal.Number.Integer'
      expect(kind_at("xiv) y\n", 'xiv)')).to eq 'Literal.Number.Integer'
    end
  end
end
