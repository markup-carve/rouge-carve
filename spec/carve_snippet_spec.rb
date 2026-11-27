# frozen_string_literal: true

require 'spec_helper'

# Snippet definitions and uses (C2-B-236, C2-B-237, C2-I-128).
RSpec.describe Rouge::Lexers::Carve do
  def lex(source)
    described_class.new.lex(source).map { |token, value| [token.qualname, value] }
  end

  def scoped(source, name)
    lex(source).select { |token, _| token == name }.map(&:last)
  end

  it 'scopes the issue reproduction' do
    source = <<~CRV
      {$ver}: 0.2.3

      Release {{ $ver }} of the tool, with *strong* after.

      {{ $ver }}

      Text after the block use with *strong*.
    CRV
    expect(lex(source)).to eq [
      %w[Punctuation {], ['Name.Variable', '$ver'], %w[Punctuation }:],
      ['Text', " 0.2.3\n\nRelease "],
      %w[Punctuation {{], ['Text', ' '], ['Name.Variable', '$ver'], ['Text', ' '], %w[Punctuation }}],
      ['Text', ' of the tool, with '], %w[Punctuation *], %w[Generic.Strong strong], %w[Punctuation *],
      ['Text', " after.\n\n"],
      %w[Punctuation {{], ['Text', ' '], ['Name.Variable', '$ver'], ['Text', ' '], %w[Punctuation }}],
      ['Text', "\n\nText after the block use with "],
      %w[Punctuation *], %w[Generic.Strong strong], %w[Punctuation *], ['Text', ".\n"]
    ]
  end

  it 'scopes the marker parts and glued blocks of a definition and lexes its value inline' do
    tokens = lex("{$brand .badge}{.x}: *b*\nnext\n")
    expect(tokens.first(6)).to eq [
      %w[Punctuation {], ['Name.Variable', '$brand'], ['Name.Attribute', ' .badge'],
      %w[Punctuation }], ['Name.Attribute', '{.x}'], %w[Punctuation :]
    ]
    expect(tokens).to include(%w[Generic.Strong b])
    expect(tokens.last).to eq ['Text', "\nnext\n"]
  end

  it 'lets a definition take the attribute line above it' do
    expect(lex("{.k}\n{$v}: x\n").first(3)).to eq [
      ['Name.Attribute', '{.k}'], ['Text', "\n"], %w[Punctuation {]
    ]
  end

  it 'leaves the shapes that make no definition as text' do
    [
      "{$v #x}: a\n", "{$v}:x\n", "{$v}:\n", "{$v}: \n", "{$v}\n",
      "\\{$v}: a\n", "para\n{$v}: a\n", "  {$v}: a\n", "> {$v}: a\n", "- {$v}: a\n"
    ].each do |source|
      expect(scoped(source, 'Name.Variable')).to be_empty, source
    end
  end

  it 'reads a use in every inline host' do
    ["# H {{ $v }}\n", "| a {{ $v }} |\n", "> q {{ $v }}\n", "- i {{ $v }}\n",
     "x *a {{ $v }} b* y\n", "para\nlazy {{ $v }}\n"].each do |source|
      expect(scoped(source, 'Name.Variable')).to eq(['$v']), source
    end
  end

  it 'ends the block at a lone use' do
    tokens = lex("{{ $v }}\n- item\n")
    expect(tokens).to include(%w[Punctuation -])
    expect(scoped("  {{ $v }}  \n", 'Name.Variable')).to eq ['$v']
  end

  it 'keeps a lone use under an open paragraph as a lazy line' do
    expect(lex("para\n{{ $v }}\n- x\n").last).to eq ['Text', "\n- x\n"]
  end

  it 'reads an attribute block glued after a use as text' do
    expect(lex('{{ $v }}{.c} x')).to eq [
      %w[Punctuation {{], ['Text', ' '], ['Name.Variable', '$v'], ['Text', ' '], %w[Punctuation }}],
      ['Text', '{.c} x']
    ]
  end

  it 'gives an attribute line above a lone use no attribute scope (carve#6896)' do
    source = "{$v}: X\n\n{.k :en}\n{{ $v }}\n"
    expect(scoped(source, 'Name.Attribute')).to be_empty
    expect(lex(source)).to include(['Text', " X\n\n{.k :en}\n"])
    expect(scoped(source, 'Name.Variable')).to eq ['$v', '$v']
    expect(scoped("{.a}{.b}\n{{ $v }}\n", 'Name.Attribute')).to be_empty
    # A line holding more than the use is a paragraph, which the line takes.
    expect(scoped("{.k}\n{{ $v }} tail\n", 'Name.Attribute')).to eq ['{.k}']
  end

  it 'makes no use of an escaped brace, a quoted include path or another shape' do
    ["\\{{ $v }}\n", "{{ \"a {{ $v }}.crv\" }}\n", "{{ $a.crv }}\n",
     "{{ $v @shift:1 }}\n", "{{$v}}\n", "`{{ $v }}`\n", "%% {{ $v }}\n",
     "[a]({{ $v }})\n"].each do |source|
      expect(scoped(source, 'Name.Variable')).to be_empty, source
    end
    expect(scoped("{{ $a.crv }}\n", 'Name.Namespace')).to eq ['$a.crv']
    expect(scoped("{{ \"a {{ $v }}.crv\" }}\n", 'Name.Namespace')).to eq ['"a {{ $v }}.crv"']
  end
end
