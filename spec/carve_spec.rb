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
      expect(lex('{{ ch.crv#intro }}')).to eq [
        ['Punctuation', '{{'],
        ['Text', ' '],
        ['Name.Namespace', 'ch.crv'],
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

    # Since carve 0.1.8 the selector is `id_attribute`, whose
    # `explicit_identifier` admits a leading ASCII digit.
    {
      'spaced' => '{{ ch.crv #2024-plan }}',
      'adjacent' => '{{ ch.crv#2024-plan }}'
    }.each do |spelling, source|
      it "reads a digit-leading selector as a selector (#{spelling})" do
        tokens = lex(source)
        expect(tokens).to include ['Name.Namespace', 'ch.crv']
        expect(tokens).to include ['Name.Label', '#2024-plan']
      end
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

    it 'leaves a checkbox without task content as list text' do
      expect(token_for("- [ ]\n", '[ ]')).not_to eq 'Name.Constant'
      expect(token_for("- [ ]   \n", '[ ]')).not_to eq 'Name.Constant'
      expect(token_for("- [ ] done\n", '[ ]')).to eq 'Name.Constant'
      expect(token_for("- [ ] \tdone\n", '[ ]')).to eq 'Name.Constant'
    end

    it 'leaves contentless markers and tab-separated markers as text' do
      ['- ', '* ', '1. ', '. ', '# ', '^ ', ':: ', ': ',
       "-\titem", "1.\titem", "#\tTitle", ">\tquote"].each do |source|
        expect(names("#{source}\n")).to eq(['Text']), source.inspect
      end
      expect(token_for("> quote\n", '>')).to eq 'Punctuation'
      expect(token_for(">\n", '>')).to eq 'Punctuation'
    end

    it 'requires a leading space before a first-block continuation' do
      ["-\t+", "1.\t+"].each do |source|
        expect(names("#{source}\n")).to eq(['Text']), source.inspect
      end
      expect(lex("- [ ]\t+\n")).not_to include ['Name.Constant', '[ ]'], ['Operator', '+']
      expect(lex("- [ ] \t+\nnext\n")).to include ['Name.Constant', '[ ]'], ['Operator', '+']
      expect(lex("- \t+\nnext\n")).to include ['Punctuation', '-'], ['Operator', '+']
    end

    it 'does not treat a contentless nested marker as another item' do
      expect(lex("- - \n")).to eq [['Punctuation', '-'], ['Text', " - \n"]]
    end

    it 'distinguishes a task continuation from its list marker' do
      tokens = lex("- [ ] +\n```sh\nnpm test\n```\n")
      expect(tokens).to include ['Punctuation', '-'], ['Name.Constant', '[ ]'], ['Operator', '+']
    end

    it 'distinguishes a first-block continuation from bullet and ordered markers' do
      {'-' => 'Punctuation', '*' => 'Punctuation', '1.' => 'Literal.Number.Integer', '.' => 'Literal.Number.Integer'}.each do |marker, kind|
        tokens = lex("#{marker} +\n```sh\nnpm test\n```\n")
        expect(tokens).to include [kind, marker], ['Operator', '+']
      end
    end

    it 'colors a standalone continuation inside a list' do
      expect(token_for("- item\n+\n> note\n", '+')).to eq 'Operator'
      expect(token_for("+ x\n", "+ x\n")).to eq 'Text'
    end

    it 'scopes root-relative first-block continuations in each container' do
      [
        "- +\nnext\n", "- [ ] +\nnext\n", "1. +\nnext\n",
        ":: term\n: +\nnext\n", ":: term\n\n: +\nnext\n",
        "> :: term\n> : +\n> next\n",
        "- - +\nnext\n", "- > +\nnext\n", "> - +\n> next\n",
        "1. - +\nnext\n", "-{.c} +\nnext\n",
        "- + \nnext\n", "  - +\nnext\n", "- +\n", "- +\n  indented\n",
        "- item\n  > +\nnext\n", "> +\nnext\n", ">+\nnext\n", ">>+\nnext\n",
        ">> +\nnext\n", "[^a]: +\nnext\n", "> - +\nnext\n", "> - +\n>   x\n"
      ].each do |source|
        expect(lex(source)).to(include(['Operator', '+']), source.inspect)
      end
    end

    it 'scopes a separate continuation after a list, quote, or footnote' do
      ["- item\n+\nnext\n", "> quote\n+\nnext\n",
       "[^a]: note\n+\nnext\n", "- item\n+ \nnext\n"].each do |source|
        expect(lex(source)).to(include(['Operator', '+']), source.inspect)
      end
    end

    it 'keeps the host through a lazy line or an attached block' do
      [
        "> quoted\n+\npara\n+\n# H\n",
        "[^a]: note\n+\npara\n+\nmore\n",
        "> quote\nlazy\n+\nnext\n",
        "[^a]: note\n  more\n+\nnext\n",
        "1. item\n+\n```\ncode\n```\n+\nnext\n",
        ":: term\n: body\n+\npara\n"
      ].each do |source|
        expect(lex(source).count { |kind, value| kind == 'Operator' && value == '+' })
          .to eq(source.lines.count { |line| line.start_with?('+') }), source.inspect
      end
    end

    it 'scopes a continuation at the marker column of the container it reaches' do
      {
        "- a\n  - b\n  +\n  > q\n" => [3, 2],
        "- x\n  - y\n    - a\n\t+\n\t> q\n" => [4, 1],
        " - a\n +\n > q\n" => [2, 1],
        "> - a\n>   - b\n> +\n> para\n" => [3, 2],
        "> > q\n> +\n> para\n" => [2, 2],
        "- a\n  > q\n  +\n  p\n" => [3, 2],
        "> q\n+\n| a |\n" => [2, 0]
      }.each do |source, (line, col)|
        offset = source.lines.first(line - 1).sum(&:length) + col
        pos = 0
        scope = nil
        lex(source).each do |kind, value|
          scope = kind if offset >= pos && offset < pos + value.length && value[offset - pos] == '+'
          pos += value.length
        end
        expect(scope).to eq('Operator'), source.inspect
      end
    end

    # Each count is how many `+` carve-js main reads as a marker.
    it 'counts the markers carve-js reads in quotes, footnotes and fences' do
      {
        "> - a\n>+\n> > q\n" => 1,
        "x[^a]\n\n[^a]: +\n- a\n" => 0,
        "x[^a]\n\n[^a]: +\n1. a\n" => 0,
        "x[^a]\n\n[^a]: +\n  - a\n" => 0,
        "x[^a]\n\n[^a]: +\n> q\n" => 1,
        "> > q\n> +\n> > para\n" => 0,
        "> - a\n> +\n> > r\n" => 0,
        "> - a\n>   - b\n>   +\n>   > q\n" => 1,
        "> > q\n>+\n> para\n" => 0,
        "> > q\n>+\npara\n" => 0,
        "> - a\n>+\n> para\n" => 1,
        "> - a\n>+\npara\n" => 0,
        "> q\n>+\npara\n" => 0,
        "> 1. a\n>+\n> > r\n" => 1,
        "> - a\n>\n>+\n> para\n" => 1,
        "> > - a\n> >+\n> > para\n" => 1,
        "- a\n  > - b\n  >+\n  > para\n" => 1,
        "> - a\n>+\n> - b\n" => 0,
        "- a\n  - b\n  +\n  > q\n\n  +\n  > r\n" => 2,
        "- a\n  - b\n  +\n  > q\n  > q2\n  +\n  para\n" => 2,
        "```\n- a\n+\n> q\n```\n" => 0,
        "- a\n  ```\n  +\n  ```\n" => 0,
        "-{.c} item\n  > q\n  +\n  next\n" => 1,
        "1.{.c} item\n   > q\n   +\n   next\n" => 1,
        "- a\n| t |\n+\nnext\n" => 0,
        "> a\n| t |\n+\nnext\n" => 0,
        ":: t\n: a\n+\n- b\n" => 1,
        ":: t\n: a\n+\n1. b\n" => 1,
        "> :: t\n> : a\n> +\n> - b\n" => 1,
        "x[^a]\n\n[^a]: n\n+\n- b\n" => 1,
        "> q\n+\n- a\n" => 1,
        ":: t\n: d\n\n+\nnext\n" => 0,
        "x[^a]\n\n[^a]: n\n\n+\nnext\n" => 0,
        ":: t\n: a\n\n  more\n+\nnext\n" => 1
      }.each do |source, count|
        expect(lex(source).count { |kind, value| kind == 'Operator' && value == '+' })
          .to eq(count), source.inspect
      end
    end

    it 'keeps a `+` in a comment payload a comment' do
      expect(lex("%%%\n\n- item\n+\nnext\n%%%\n")).not_to include(['Operator', '+'])
    end

    # carve-js main reads `: b` as a definition only under a term.
    it 'scopes a description marker only under a term' do
      {
        "> a\n: b\n" => 0, "a\n: b\n" => 0, ": b\n" => 0, "- a\n: b\n" => 0,
        ":: t\n> a\n: b\n" => 0, "> :: t\n: b\n" => 0, ":: t\n: a\n# h\n: b\n" => 1,
        ":: t\n: a\n: b\n" => 2, ":: t\n: a\n\n: b\n" => 2, ":: t\n: a\n- x\n: b\n" => 2,
        ":: t\n: a\n\npara\n\n: b\n" => 1, ":: t\n: a\n---\n: b\n" => 1
      }.each do |source, count|
        expect(lex(source).count { |kind, value| kind == 'Punctuation' && value == ':' })
          .to eq(count), source.inspect
      end
    end

    it 'keeps continuations literal outside the root-relative positions' do
      [
        "+\nnext\n", "+ text\n", "  +\nnext\n", ": + \nnext\n",
        "- item\n  +\nnext\n", "> +\n",
        ">   +\nnext\n", "> quote\n\n+\nnext\n",
        "  > +\nnext\n", "  > - +\nnext\n", "- >   +\nnext\n",
        "> +\n>\n", "> +\n>   x\n", "> +\n> next\n", "> +\n- x\n",
        "> text\n> +\n> para\n", "> text\nlazy\n> +\n> para\n",
        "> > q\n> > +\n> > p\n", "- a\n+\n- b\n", "- a\n  - b\n  +\npara\n",
        "- a\n  - b\n  +\n> q\n", "> - a\n  +\nq\n", "1. [ ] +\nnext\n",
        "- > +\n  next\n", "- a\n  - ```\n    +\n    ```\n",
        "> :: term\n: +\nnext\n",
        "> quote\n# H\n+\nnext\n",
        "> quote\n```\ncode\n```\n+\nnext\n",
        "text\n- item\n+\nnext\n",
        ": +\nnext\n", ":: term\n+\nnext\n"
      ].each do |source|
        expect(lex(source)).not_to(include(['Operator', '+']), source.inspect)
      end
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
    it 'highlights CSV separators and quoted fields' do
      source = "```csv\nPlan,Seats,Price per month\nStarter,1,\"$0\"\nTeam,10,\"$49, billed yearly\"\n```\n"
      tokens = lex(source)
      expect(tokens).to include ['Keyword', ',']
      expect(tokens).to include ['Name.Attribute', 'Plan']
      expect(tokens).to include ['Name.Variable', 'Starter']
      expect(tokens).to include ['Name.Variable', '1']
      expect(tokens).to include ['Literal.String', '"$0"']
      expect(tokens).to include ['Literal.String', '"$49, billed yearly"']
      expect(names(source)).not_to include 'Error'
    end

    it 'types every field of a CSV or TSV body, leaving no plain text' do
      { 'csv' => ',', 'tsv' => "\t" }.each do |lang, sep|
        rows = ["Plan#{sep}Seats", "Starter#{sep}\"a\"\"b\"", "x\"y#{sep}\"z\"tail"]
        tokens = lex("```#{lang}\n#{rows.join("\n")}\n```\n")
        body = tokens.drop_while { |_, v| v != "\n" }.drop(1).take_while { |_, v| v != '```' }
        body.reject { |_, v| v == "\n" }.each do |name, value|
          expect(name).not_to eq('Text'), "#{lang}: #{value.inspect} left plain"
        end
        expect(body.map(&:last).join).to eq "#{rows.join("\n")}\n"
      end
    end

    it 'keeps a quoted newline and escaped quote inside a CSV field' do
      tokens = lex("```csv\n\"first\nsecond \"\"quote\"\"\",end\n```\n")
      expect(tokens).to include ['Literal.String.Escape', '""']
      expect(tokens).to include ['Keyword', ',']
      expect(tokens).to include ['Name.Attribute', 'end']
      expect(tokens.select { |name, _| name == 'Literal.String' }.map(&:last).join).to eq "\"first\nsecond quote\""
    end

    it 'uses tabs but not commas as TSV separators' do
      tokens = lex("```tsv\na,b\t\"c\td\"\te\n```\n")
      expect(tokens).to include ['Name.Attribute', 'a,b']
      expect(tokens).to include ['Keyword', "\t"]
      expect(tokens).to include ['Literal.String', "\"c\td\""]
      expect(tokens).not_to include ['Keyword', ',']
    end

    it 'types a quote in an unquoted field and handles an unclosed quote' do
      tokens = lex("```csv\na\"b,\"open\nmore\n```")
      expect(tokens).to include ['Name.Attribute', 'a"b']
      expect(tokens).to include ['Literal.String', "\"open\nmore\n"]
      expect(tokens).not_to include ['Error', anything]
    end

    it 'types text after a closing quote as a field' do
      tokens = lex("```csv\n\"a\"tail,next\n```\n")
      expect(tokens).to include ['Literal.String', '"a"']
      expect(tokens).to include ['Name.Attribute', 'tail']
      expect(tokens).to include ['Keyword', ',']
    end

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
