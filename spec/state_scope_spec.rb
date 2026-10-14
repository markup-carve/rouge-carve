# frozen_string_literal: true

require 'spec_helper'

# States that must end where the construct ends, not run on into the blocks
# after it.
RSpec.describe Rouge::Lexers::Carve do
  def lex(source)
    described_class.new.lex(source).map { |tok, val| [tok.qualname, val] }
  end

  def token_for(source, text)
    lex(source).find { |_, val| val == text }&.first
  end

  def kind_at(source, needle)
    at = source.index(needle)
    offset = 0
    described_class.new.lex(source).each do |kind, value|
      offset += value.length
      return kind.qualname if offset > at
    end
    raise "No token for #{needle}"
  end

  describe 'definition lines' do
    it 'ends a footnote definition at its line' do
      expect(token_for("[^1]: note\n\n# Heading\n", 'Heading')).to eq 'Generic.Heading'
    end

    it 'ends an abbreviation definition at its line' do
      expect(token_for("*[HTML]: Hyper\n\n# Heading\n", 'Heading')).to eq 'Generic.Heading'
    end

    it 'still lexes the definition text inline' do
      expect(token_for("[^1]: a *b* c\n", 'b')).to eq 'Generic.Strong'
      expect(token_for("*[HTML]: Hyper\n", 'HTML')).to eq 'Name.Entity'
    end
  end

  describe 'unclosed inline openers' do
    it 'does not open an inline footnote without a closing bracket' do
      source = "a ^[unclosed\n\n# H\n"
      expect(token_for(source, 'H')).to eq 'Generic.Heading'
      expect(kind_at(source, 'unclosed')).to eq 'Text'
    end

    it 'does not open an extension body without a closing bracket' do
      source = ":kbd[Ctrl\n\n# H\n"
      expect(token_for(source, 'H')).to eq 'Generic.Heading'
      expect(kind_at(source, 'Ctrl')).to eq 'Text'
    end

    it 'finds the closing bracket after multibyte text' do
      expect(kind_at("éé ^[x] y\n", 'x')).to eq 'Generic.Emph'
    end

    it 'keeps an inline footnote that spans lines of one paragraph' do
      expect(kind_at("a ^[x\ny] z\n", 'y')).to eq 'Generic.Emph'
    end

    it 'ends an inline footnote at a blank line when its bracket was consumed' do
      expect(token_for("a ^[x `]`\n\n# H\n", 'H')).to eq 'Generic.Heading'
    end

    it 'does not count a bracket inside a code span' do
      source = "a ^[x `]`\n\n- item\n"
      expect(kind_at(source, 'x')).to eq 'Text'
      expect(token_for(source, '-')).to eq 'Punctuation'
    end

    it 'ends the search at a block that interrupts the paragraph' do
      source = "a ^[unclosed\n# H\ntext]\n"
      expect(kind_at(source, 'unclosed')).to eq 'Text'
      expect(token_for(source, 'H')).to eq 'Generic.Heading'
      expect(kind_at(":kbd[x\n> q]\n", 'x')).to eq 'Text'
    end

    it 'ends the search at a closed fence but not at an unclosed one' do
      expect(kind_at("a ^[x\n~~~\ny]\n", 'y')).to eq 'Generic.Emph'
      expect(kind_at("a ^[x\n~~~\ny]\n~~~\n", 'x')).to eq 'Text'
    end

    it 'keeps a heading body on its line' do
      source = "# a ^[x\ny]\n"
      expect(kind_at(source, 'x')).to eq 'Generic.Heading'
      expect(kind_at(source, 'y]')).to eq 'Text'
    end

    it 'ends a list item body at the next item' do
      source = "- a ^[x\n- b]\n"
      expect(kind_at(source, 'x')).to eq 'Text'
      expect(kind_at(source, 'b]')).to eq 'Text'
    end
  end

  describe 'blocks inside a blockquote' do
    it 'reads a heading' do
      expect(token_for("> # Heading\n", 'Heading')).to eq 'Generic.Heading'
    end

    it 'reads a list marker' do
      expect(token_for("> - item\n", '-')).to eq 'Punctuation'
    end

    it 'reads nested quote markers' do
      expect(token_for("> > # Deep\n", 'Deep')).to eq 'Generic.Heading'
    end

    it 'keeps plain quoted text as before' do
      expect(kind_at("> quoted\n", 'quoted')).to eq 'Generic.Emph'
    end

    it 'reads a fence and closes it on a quoted closer' do
      source = "> ```ruby\n> x = 1\n> ```\nafter *b* c\n"
      expect(lex(source).map(&:first)).to include 'Literal.Number.Integer'
      expect(token_for(source, 'b')).to eq 'Generic.Strong'
    end

    it 'ends a quoted fence at a line that leaves the quote' do
      source = "> ```\n> code\nlazy *b* c\n"
      expect(kind_at(source, 'code')).to eq 'Literal.String.Backtick'
      expect(token_for(source, 'b')).to eq 'Generic.Strong'
    end

    it 'ends a quoted fence at a line whose marker has no space' do
      source = "> ```\n> code\n>foo\n# Heading\n"
      expect(kind_at(source, 'foo')).to eq 'Text'
      expect(token_for(source, 'Heading')).to eq 'Generic.Heading'
    end

    it 'reads a doubled marker without a space as text' do
      expect(kind_at(">> # x\n", '>>')).to eq 'Text'
    end

    it 'ends a nested quoted fence at a shallower line' do
      source = "> > ```\n> > a\n> ```\n> > b\n"
      expect(kind_at(source, 'a')).to eq 'Literal.String.Backtick'
      expect(kind_at(source, 'b')).to eq 'Literal.String.Backtick'
    end

    it 'keeps a deeper marker inside a quoted fence as payload' do
      expect(kind_at("> ```\n> > a\n> ```\n", '> a')).to eq 'Literal.String.Backtick'
    end

    it 'round-trips a quoted fence' do
      source = "> ```ruby\n> x = 1\n>\n> ```\n> > ~~~\n> > raw <1>\n> > ~~~\n"
      out = +''
      described_class.new.lex(source) { |_, value| out << value }
      expect(out).to eq source
    end
  end

  describe 'comment fences' do
    it 'does not close on a longer run' do
      source = "%%%\nx\n%%%%\ny\n%%%\nafter\n"
      expect(kind_at(source, 'y')).to start_with 'Comment'
      expect(kind_at(source, 'after')).to eq 'Text'
    end

    it 'does not close on a shorter run' do
      source = "%%%%\nx\n%%%\ny\n%%%%\nafter\n"
      expect(kind_at(source, 'y')).to start_with 'Comment'
      expect(kind_at(source, 'after')).to eq 'Text'
    end

    it 'finds the closer after multibyte text' do
      source = "#{'é' * 30}\n\n%%%\nsecret\n%%%\n"
      expect(kind_at(source, 'secret')).to start_with 'Comment'
    end

    it 'closes on a run of its width followed by text' do
      source = "%%% html\nsecret\n%%% end\n\nafter\n"
      expect(kind_at(source, 'secret')).to start_with 'Comment'
      expect(kind_at(source, 'after')).to eq 'Text'
    end

    it 'reads an opener without a closer of its width as a one-line comment' do
      source = "%%%\nx\n%%%%\ny\n"
      expect(kind_at(source, 'x')).to eq 'Text'
      expect(kind_at(source, 'y')).to eq 'Text'
    end
  end

  describe 'standalone attribute lines' do
    it 'does not cross a blank line' do
      expect(kind_at("{.cls\n\npara}\n", 'para')).not_to eq 'Name.Attribute'
    end

    it 'still spans lines inside one block' do
      source = "{.a\n.b}\n# H\n"
      expect(token_for(source, "{.a\n.b}")).to eq 'Name.Attribute'
    end
  end
end
