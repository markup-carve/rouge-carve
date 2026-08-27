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

# Whether +text+ carries a scope other than Text.
def scoped_text?(source, text)
  tokens(source).any? { |name, val| name != 'Text' && val.include?(text) }
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
