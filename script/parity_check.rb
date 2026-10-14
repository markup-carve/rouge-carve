#!/usr/bin/env ruby
# frozen_string_literal: true

# The construct inventory the highlight.js grammar is held to, applied here, so
# the two grammars answer to one standard rather than each to its own list.

require 'rouge'
require_relative '../lib/rouge-carve'

def tokens(source)
  Rouge::Lexers::Carve.new.lex(source).map { |tok, val| [tok.qualname, val] }
end

def scoped?(source)
  tokens(source).any? { |name, val| name != 'Text' && !val.strip.empty? }
end

# Whether any character of +text+ carries a scope other than Text. Checking
# for one token that holds the whole of +text+ missed a span split across
# several tokens, so `/usr/local/bin` painted as `/usr/` + `local/bin` passed.
def scoped_text?(source, text)
  from = source.index(text) or raise "#{text.inspect} is not in #{source.inspect}"
  to = from + text.length
  at = 0
  tokens(source).any? do |name, val|
    start = at
    at += val.length
    name != 'Text' && start < to && at > from && !val[[from - start, 0].max...(to - start)].strip.empty?
  end
end

CONSTRUCTS = {
  'strong' => 'a *bold* b', 'emphasis' => 'a /it/ b', 'underline' => 'a _u_ b',
  'strikethrough' => 'a ~s~ b', 'highlight' => 'a =m= b',
  'superscript' => 'H{^2^}O', 'subscript' => 'H{,2,}O',
  'inline code' => 'a `x` b', 'literal code span' => 'a !`x` b',
  'inline math' => 'a $`e=mc` b', 'display math' => 'a $$`x` b',
  'link' => '[t](/u)', 'image' => '![alt](i.png)',
  'autolink' => 'see <https://example.com>', 'cross-reference' => 'see </#sec>',
  'attribute block' => '{#id .cls key="v"}',
  'mention' => 'hi @user', 'tag' => 'a #tag',
  'footnote reference' => 'x[^1]', 'inline footnote' => 'x ^[note]',
  'citation' => '[@knuth1984]', 'symbol shortcode' => 'a :smile: b',
  'inline extension' => ':kbd[Ctrl]', 'code callout' => "```\na <1>\n```\n",
  'heading' => "# Title\n", 'blockquote' => "> quoted\n",
  'bullet item' => "- item\n", 'ordered item' => "3. item\n",
  'task item' => "- [x] done\n",
  'table header row' => "|= A |= B |\n", 'row attributes' => "| a | b |{.ok}\n",
  'container' => %(::: note "T"\n), 'caption' => "^ Figure 1\n",
  'thematic break' => "---\n\ntext\n", 'definition term' => ":: term\n",
  'code fence' => "```php\n$x = 1;\n```\n", 'raw fence' => "```=html\n<b>x</b>\n```\n",
  'frontmatter' => "---\ntitle: x\n---\n\n# H\n",
  'trailing comment' => 'x %% note', 'comment fence' => "%%%\nhidden\n%%%\n",
  'critic insertion' => '{+added+}', 'critic deletion' => '{-removed-}',
  'critic substitution' => '{~old~>new~}', 'forced emphasis' => 'my{*x*}word',
  'abbreviation definition' => "*[HTML]: HyperText\n",
  'link reference definition' => "[ref]: /url\n",
  'footnote definition' => "[^1]: note text\n",
}.freeze

NEGATIVES = {
  'a path is not emphasis' => ['A path like /usr/local/bin here.', '/usr/local/bin'],
  'a range is not strikethrough' => ['A range 10-20 here.', '10-20'],
  'a bare caret is not superscript' => ['x ^2^ y', '^2^'],
  'a bare comma is not subscript' => ['typo ,oops, happens', ',oops,'],
  'an identifier is not underline' => ['call snake_case_name here', 'snake_case_name'],
  'an assignment is not highlight' => ['x=1 and y=2', 'x=1 and y=2'],
  'a product is not strong' => ['2*3*4', '2*3*4'],
  'text between arrows is not highlight' => ['a ==> b ==> c', ' b '],
}.freeze

missing = CONSTRUCTS.reject { |_, src| scoped?(src) }
painted = NEGATIVES.select { |_, (src, text)| scoped_text?(src, text) }

puts "constructs checked : #{CONSTRUCTS.size}"
puts "unscoped           : #{missing.size}"
missing.each_key { |k| puts "   #{k}: #{CONSTRUCTS[k].inspect}" }
puts "negatives checked  : #{NEGATIVES.size}"
puts "wrongly painted    : #{painted.size}"
painted.each_key { |k| puts "   #{k}" }

exit(missing.empty? && painted.empty? ? 0 : 1)
