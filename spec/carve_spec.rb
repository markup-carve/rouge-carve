# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rouge::Lexers::Carve do
  let(:lexer) { described_class.new }

  # The token stream as [qualname, value] pairs, which is what every assertion
  # here is really about.
  def lex(source)
    described_class.new.lex(source).map { |tok, val| [tok.qualname, val] }
  end

  # Every token a construct produces, without the values.
  def names(source)
    lex(source).map(&:first)
  end

  # The token carrying a given piece of text.
  def token_for(source, text)
    lex(source).find { |_, val| val == text }&.first
  end

  describe 'registration' do
    it 'answers to its tag and alias' do
      expect(Rouge::Lexer.find('carve')).to eq described_class
      expect(Rouge::Lexer.find('crv')).to eq described_class
    end

    it 'is found by filename' do
      expect(Rouge::Lexer.guess(filename: 'doc.crv')).to eq described_class
      expect(Rouge::Lexer.guess(filename: 'doc.carve')).to eq described_class
    end

    it 'is found by mimetype' do
      expect(Rouge::Lexer.guess(mimetype: 'text/x-carve')).to eq described_class
    end

    it 'ships the demo rouge requires of every lexer' do
      demo = File.expand_path('../lib/rouge/demos/carve', __dir__)
      expect(File.exist?(demo)).to be true
      expect(File.read(demo)).not_to be_empty
    end

    it 'lexes its own demo without an error token' do
      demo = File.read(File.expand_path('../lib/rouge/demos/carve', __dir__))
      expect(names(demo)).not_to include 'Error'
    end
  end

  # The reason this lexer exists. Lexing Carve as Markdown is not merely
  # imprecise, it inverts three of these.
  describe 'the delimiters Carve swapped' do
    it 'reads a single asterisk as strong, not emphasis' do
      expect(token_for('a *bold* b', 'bold')).to eq 'Generic.Strong'
    end

    it 'reads a slash as emphasis, which Markdown leaves as literal text' do
      expect(token_for('a /it/ b', 'it')).to eq 'Generic.Emph'
    end

    it 'reads a tilde as strikethrough' do
      expect(token_for('a ~s~ b', 's')).to eq 'Generic.Deleted'
    end

    it 'reads a single equals as highlight' do
      expect(token_for('a =m= b', 'm')).to eq 'Generic.Inserted'
    end

    # Rouge has no underline token, so the content shares Generic::Emph with
    # italic. The DELIMITER still distinguishes them, which is the most the
    # vocabulary allows - see the note at the top of the lexer.
    it 'marks up underline, and keeps its delimiter distinguishable' do
      expect(token_for('a _u_ b', 'u')).to eq 'Generic.Emph'
      expect(token_for('a _u_ b', '_')).to eq 'Punctuation'
    end

    it 'treats a bare caret as literal text, because sup is braced-only' do
      expect(names('a ^x^ b')).not_to include 'Generic.Emph'
    end

    it 'reads the braced sup and sub forms' do
      expect(token_for('H{,2,}O', '2')).to eq 'Generic.Emph'
      expect(token_for('mc{^2^}', '2')).to eq 'Generic.Emph'
    end
  end

  describe 'inline constructs' do
    it 'separates a link label from its destination' do
      expect(lex('[t](/u)')).to eq [
        ['Name.Entity', '[t]'],
        ['Punctuation', '('],
        ['Name.Tag', '/u'],
        ['Punctuation', ')']
      ]
    end

    it 'distinguishes an image from a link' do
      expect(token_for('![alt](i.png)', '![alt]')).to eq 'Literal.String.Other'
    end

    it 'reads a cross-reference' do
      expect(token_for('see </#sec>', '#sec')).to eq 'Name.Namespace'
    end

    it 'keeps an attribute block whole' do
      expect(lex('{#id .cls key="v"}')).to eq [['Name.Attribute', '{#id .cls key="v"}']]
    end

    it 'reads an include directive by part' do
      # The selector is the point: `#intro` is genuinely tag syntax, and was
      # coloured as one inside a path before the directive had a rule of its
      # own (PART 9 section 19). It is a LABEL here - a selector into another
      # document - and the path reads as a path.
      expect(lex('{{ ch.crv #intro }}')).to eq [
        ['Punctuation', '{{'],
        ['Text', ' '],
        ['Name.Namespace', 'ch.crv'],
        ['Text', ' '],
        ['Name.Label', '#intro'],
        ['Text', ' '],
        ['Punctuation', '}}']
      ]
      expect(lex('{{ "a b.crv" }}')).to eq [
        ['Punctuation', '{{'],
        ['Text', ' '],
        ['Name.Namespace', '"a b.crv"'],
        ['Text', ' '],
        ['Punctuation', '}}']
      ]
    end

    it 'reads an option slot as a name and a value' do
      expect(lex('{{ ch.crv @shift:auto }}')).to eq [
        ['Punctuation', '{{'],
        ['Text', ' '],
        ['Name.Namespace', 'ch.crv'],
        ['Text', ' '],
        ['Name.Attribute', '@shift'],
        ['Punctuation', ':'],
        ['Literal', 'auto'],
        ['Text', ' '],
        ['Punctuation', '}}']
      ]
    end

    it 'leaves an unterminated directive alone' do
      # The closer is required in the opener's lookahead, so a stray `{{` never
      # opens the state and the rest of the line keeps its own markup.
      expect(token_for('{{ unterminated *bold* here', '*')).to eq 'Punctuation'
    end

    it 'leaves an include directive in a code span verbatim' do
      expect(lex('`{{ x.crv }}`')).to eq [
        ['Punctuation', '`'],
        ['Literal.String.Backtick', '{{ x.crv }}'],
        ['Punctuation', '`']
      ]
    end

    it 'reads a mention and a tag as one token each, sigil included' do
      expect(token_for('hi @user', '@user')).to eq 'Name.Variable.Magic'
      expect(token_for('a #tag', '#tag')).to eq 'Name.Variable.Instance'
    end

    it 'reads the literal code span, whose ! is a prefix rather than text' do
      expect(lex('!`x`')).to eq [
        ['Operator', '!'],
        ['Punctuation', '`'],
        ['Literal', 'x'],
        ['Punctuation', '`']
      ]
    end

    it 'reads a citation rather than a link label' do
      expect(token_for('[@knuth1984]', '@knuth1984')).to eq 'Name.Variable'
    end

    it 'reads a critic substitution as two sides' do
      expect(token_for('{~old~>new~}', 'old')).to eq 'Generic.Deleted'
      expect(token_for('{~old~>new~}', 'new')).to eq 'Generic.Inserted'
    end

    it 'lets an escape win over the delimiter after it' do
      expect(names('a \\*not bold\\*')).not_to include 'Generic.Strong'
    end
  end

  describe 'block constructs' do
    it 'reads a heading' do
      expect(token_for("## Title\n", 'Title')).to eq 'Generic.Heading'
    end

    it 'reads a blockquote marker' do
      expect(token_for("> quoted\n", '>')).to eq 'Punctuation'
    end

    it 'reads an ordered marker as a number' do
      expect(token_for("3. item\n", '3.')).to eq 'Literal.Number.Integer'
    end

    it 'reads a task state as its own token' do
      expect(token_for("- [x] done\n", '[x]')).to eq 'Name.Constant'
    end

    it 'reads a header cell marker as one construct including its pipe' do
      expect(token_for("|= A |= B |\n", '|=')).to eq 'Operator'
    end

    it 'reads attributes on a row closing pipe' do
      expect(token_for("| a | b |{.ok}\n", '{.ok}')).to eq 'Name.Attribute'
    end

    it 'reads a container word' do
      expect(token_for(%(::: note "T"\n), 'note')).to eq 'Keyword.Namespace'
      expect(token_for(%(::: note "T"\n), '"T"')).to eq 'Literal.String.Double'
    end

    it 'reads a caption line' do
      expect(token_for("^ Figure 1\n", 'Figure 1')).to eq 'Generic.Subheading'
    end
  end

  describe 'fenced blocks' do
    it 'highlights the payload with a lexer for the declared language' do
      names = names("```ruby\nx = 1\n```\n")
      expect(names).to include 'Literal.Number.Integer'
      expect(names).not_to include 'Error'
    end

    it 'leaves a raw block opaque, because a format is not a language' do
      expect(token_for("```=html\n<b>hi</b>\n```\n", '=html')).to eq 'Keyword.Type'
      expect(names("```=html\n<b>hi</b>\n```\n")).not_to include 'Name.Tag'
    end

    # A Rouge state cannot carry the opener's width across rules, so the width
    # is closed over instead. Getting this wrong ends the block early and lexes
    # the rest of the document as prose.
    it 'does not let a shorter inner fence close a wider one' do
      source = "````\n```\nstill inside\n````\n"
      inside = lex(source).find { |_, val| val.include?('still inside') }
      expect(inside.first).to eq 'Literal.String.Backtick'
    end

    it 'closes on a fence at least as long as the opener' do
      expect(names("```\nbody\n````\n")).not_to include 'Error'
    end
  end

  describe 'frontmatter' do
    it 'reads a terminated block' do
      expect(token_for("---\ntitle: x\n---\n", 'title: x\n')).to be_nil
      expect(names("---\ntitle: x\n---\n")).to include 'Comment.Special'
    end

    # A lone `---` at the top of a document is a thematic break. Opening
    # frontmatter on it swallowed the rest of the file as comment.
    it 'does not open on a `---` with no terminator' do
      expect(names("---\n\n# Real heading\n")).not_to include 'Comment.Special'
      expect(token_for("---\n\n# Real heading\n", 'Real heading')).to eq 'Generic.Heading'
    end
  end

  # Rouge's own plugin template names this the property worth testing: a lexer
  # that drops or duplicates a character is broken in a way no scope check sees.
  describe 'input preservation' do
    def round_trips?(source)
      out = +''
      described_class.new.lex(source) { |_, value| out << value }
      out == source
    end

    it 'reproduces every construct exactly' do
      File.read(File.expand_path('../lib/rouge/demos/carve', __dir__)).then do |demo|
        expect(round_trips?(demo)).to be true
      end
    end

    # The margin was dropped here: the rule consumed it without capturing it, so
    # `groups` never emitted it.
    it 'keeps the indent in front of an indented comment' do
      expect(round_trips?("x\n  %% indented comment\ny\n")).to be true
      expect(round_trips?("- - a\n %% c\n b\n")).to be true
    end

    it 'keeps the indent on both fences of an indented comment block' do
      expect(round_trips?("  %%%\n    body\n  %%%\n")).to be true
    end

    it 'reproduces a document that mixes every block kind' do
      source = File.read(File.expand_path('sample', __dir__))
      expect(round_trips?(source)).to be true
    end
  end

  # A lexer that emits Error is telling the reader its own rules ran out.
  describe 'robustness' do
    it 'never emits an error token on any construct in the demo' do
      demo = File.read(File.expand_path('../lib/rouge/demos/carve', __dir__))
      expect(names(demo)).not_to include 'Error'
    end

    it 'survives a blank line inside a comment fence' do
      expect(names("%%%\na\n\nb\n%%%\n")).not_to include 'Error'
    end

    it 'survives an unterminated fence at end of input' do
      expect(names("```ruby\nx = 1\n")).not_to include 'Error'
    end

    it 'lexes an empty document' do
      expect(lex('')).to eq []
    end
  end
end
