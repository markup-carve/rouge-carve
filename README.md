# rouge-carve

A [Rouge](https://github.com/rouge-ruby/rouge) lexer for the
[Carve](https://markup-carve.github.io/carve/) markup language.

```bash
gem install rouge-carve
```

```ruby
require 'rouge-carve'

Rouge::Lexer.find('carve')                    # => Rouge::Lexers::Carve
Rouge::Lexer.guess(filename: 'notes.crv')     # => Rouge::Lexers::Carve
```

Requiring the gem registers the lexer. Anything that already highlights with
Rouge - GitLab, Jekyll, Redcarpet, most Ruby static site generators - then
handles `.crv` and `.carve` files, and ` ```carve ` fenced blocks, without
further configuration.

## Why not just use the Markdown lexer

Because it is not close enough to be wrong quietly. Carve deliberately changed
the delimiters Markdown got backwards, and three of them **invert**:

| Carve | means | Markdown reads it as |
| --- | --- | --- |
| `*bold*` | strong | emphasis |
| `/italic/` | emphasis | literal slashes |
| `_under_` | underline | emphasis |
| `~strike~` | strikethrough | subscript, or literal |
| `{=mark=}` | highlight | literal braces |
| `{^sup^}` | superscript | literal braces |

Highlighting a Carve document as Markdown does not degrade to plain text. It
shows bold where the author wrote emphasis.

## What it covers

Every construct in the language: headings, containers (`::: note`), fenced and
raw blocks, tables with alignment and per-row attributes, definition lists,
footnotes, citations, cross-references, attribute blocks, task items, critic
markup, symbol shortcodes, mentions, tags and the typographic runs.

**Fenced code is delegated.** A ` ```ruby ` block inside a `.crv` file is lexed
as Ruby, because that is what a reader expects. A ` ```=html ` raw block is not:
its info string names an output format, not a language, so the payload stays
opaque.

**Fence widths are respected.** A three-backtick line inside a four-backtick
fence is content, not a closer. The width is closed over per block rather than
approximated, which the sibling grammars in other ecosystems cannot do.

## What it cannot say

Rouge has no underline token - the vocabulary stops at `Generic::Emph`,
`Generic::Strong` and `Generic::EmphStrong`. Carve's `_x_` is underline, so its
content shares `Generic::Emph` with italic. The delimiters stay `Punctuation`,
so a consumer can still tell the two apart by the delimiter each carries.

Block openers are matched at any indent. Carve opens a block at column 0 or at
an enclosing container's content column and nowhere in between, which needs a
container model this lexer does not carry. The trade-off is deliberate and
shared with the Prism, highlight.js and Pygments grammars, so the four agree:
it over-colours an indented-at-document-level opener rather than
under-colouring the far more common indented construct inside a list item.

## Testing

```bash
bundle install
bundle exec rspec
```

Two gates, and the second is the one that finds things:

- `spec/carve_spec.rb` pins the constructs, including each inverted delimiter.
- `script/corpus_check.rb` lexes every `.crv` document in the Carve spec
  repository and fails on a single `Error` token. A lexer emitting `Error` is
  telling the reader its own rules ran out. Both bugs found during development -
  a blank line inside a comment fence, and a `---` thematic break opening
  frontmatter that never closed - came from this and not from an example
  anybody thought to write.

## Related

- [carve](https://github.com/markup-carve/carve) - the language and its spec
- [pygments-carve](https://github.com/markup-carve/pygments-carve) - the same
  grammar for Pygments, which this was ported from
- [carve-grammars](https://github.com/markup-carve/carve-grammars) - TextMate,
  Prism and highlight.js
- [carve-css](https://github.com/markup-carve/carve-css) - styles for the HTML
  Carve renders

## License

MIT.
