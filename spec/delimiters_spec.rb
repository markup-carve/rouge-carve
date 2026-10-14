# frozen_string_literal: true

require 'spec_helper'

# Bare delimiters follow Carve's flanking rules, and what they enclose is
# lexed as inline content rather than one flat token.
RSpec.describe Rouge::Lexers::Carve do
  def lex(source)
    described_class.new.lex(source).map { |tok, val| [tok.qualname, val] }
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

  def kinds(source)
    lex(source).map(&:first)
  end

  describe 'word boundaries' do
    {
      'an identifier' => ['call snake_case_name here', 'Generic.Emph'],
      'a path' => ['A path like /usr/local/bin here.', 'Generic.Emph'],
      'an assignment' => ['x=1 and y=2', 'Generic.Inserted'],
      'a product' => ['2*3*4', 'Generic.Strong'],
      'a word glued to the opener' => ['word*b* x', 'Generic.Strong'],
      'a closer glued to a word' => ['a *b*c d', 'Generic.Strong'],
      'a tilde in a word' => ['a~b~c', 'Generic.Deleted']
    }.each do |what, (source, scope)|
      it "leaves #{what} as text" do
        expect(kinds(source)).not_to include scope
      end
    end

    it 'leaves the text between arrows alone' do
      source = 'a ==> b ==> c'
      expect(kinds(source)).not_to include 'Generic.Inserted'
      expect(kind_at(source, '==>')).to eq 'Operator'
    end

    it 'closes at the delimiter that can close, past one inside a word' do
      expect(kind_at('a _b_c_ d', 'b_c')).to eq 'Generic.Emph'
    end

    it 'still reads delimiters next to punctuation' do
      expect(kind_at('(*b*), and /i/.', 'b')).to eq 'Generic.Strong'
      expect(kind_at('(*b*), and /i/.', 'i')).to eq 'Generic.Emph'
    end

    it 'reads intraword bold italic, as the engine does' do
      expect(kind_at('x/*b*/y', 'b')).to eq 'Generic.Strong'
    end

    it 'leaves an opener with no closer on its line as text' do
      expect(kinds("a *b c\nd* e\n")).not_to include 'Generic.Strong'
    end
  end

  describe 'emphasis content' do
    it 'lets an escape inside emphasis stay an escape' do
      source = '*a \\* b* c'
      expect(kind_at(source, '\\*')).to eq 'Literal.String.Escape'
      expect(kind_at(source, ' b')).to eq 'Generic.Strong'
      expect(kind_at(source, ' c')).to eq 'Text'
    end

    it 'lets a code span inside emphasis hold the delimiter' do
      source = '*b `c*` d* e'
      expect(kind_at(source, 'c*')).to eq 'Literal.String.Backtick'
      expect(kind_at(source, ' d')).to eq 'Generic.Strong'
      expect(kind_at(source, ' e')).to eq 'Text'
    end

    it 'nests another kind of emphasis' do
      source = 'a /b *c* d/ e'
      expect(kind_at(source, 'b ')).to eq 'Generic.Emph'
      expect(kind_at(source, 'c')).to eq 'Generic.Strong'
      expect(kind_at(source, ' e')).to eq 'Text'
    end

    it 'reads a same-kind delimiter that cannot close as content' do
      source = 'a *b *c* d* e'
      expect(kind_at(source, '*c')).to eq 'Generic.Strong'
      expect(kind_at(source, ' d')).to eq 'Text'
    end

    it 'keeps a link inside emphasis a link' do
      expect(kind_at('*see [t](/u) now*', '/u')).to eq 'Name.Tag'
    end

    it 'does not open a run whose closer lies past the enclosing one' do
      source = '*a /b* c/'
      expect(kind_at(source, '/b')).to eq 'Generic.Strong'
      expect(kind_at(source, ' c/')).to eq 'Text'
      expect(kind_at('_a *b_ c*', '*b')).to eq 'Generic.Emph'
    end

    it 'still nests a run that closes inside the enclosing one' do
      expect(kind_at('*a /b/ c*', '/b')).to eq 'Punctuation'
    end
  end
end
