# Changelog

## [Unreleased]

## [0.1.4] - 2026-10-23

- `csv` and `tsv` fence bodies are highlighted: every field has its own token type and the separator is an operator, colored apart from the fields in the default styles (#25, #26, #27, #28).
- A lone `+` is a continuation marker, tokenized as an operator, only where the engine reads one: at an open container's marker column with a non-list block below, or as the first block after an opener (#29, #30, #32). A prose line ending in `+` is not scoped (#31).
- A quote-prefixed `+` needs one space after each `>`: `>+`, `>>+` and `>> +` are paragraph text (#33).
- A quote opened on a list item line (`- > q`) scopes its `>`, and `- > +` is a marker when the next line starts a non-list block at column 0, at the line's column or at the owning quote's column (markup-carve/carve#3421). A stacked `> > +` takes its follower only at column 0 or the first quote's column (#34).
- A `:` left of the `::` column of the definition list it would continue is paragraph text (markup-carve/carve#3458) (#34).

## [0.1.3] - 2026-10-14

0.1.2 was tagged without its `RougeCarve::VERSION` bump, so it never reached RubyGems. 0.1.3 is the first published release with its change.

- An include selector whose id starts with a digit is lexed as a selector. `{{ ch.crv #2024-plan }}` used to fall through to plain text (#15, #16).
- A footnote or abbreviation definition ends with its line. It used to turn the rest of the file into plain text, so no later heading, list or fence was recognized (#22).
- An inline footnote `^[` or extension `:name[` with no closing `]` in its block stays text instead of swallowing the blocks after it. A `]` inside a code span does not count, and a heading, caption or table cell keeps the body on its line (#22, #24).
- A blockquote line can open a block: `> # Heading`, `> - item`, and a fence whose lines carry the `>` prefix (#22).
- A `>` marks a quote only when a space or the line end follows it, so `>> x` is paragraph text and `> > x` nests, as in the engine (#22).
- A comment fence closes only on a `%` run of its own length, which may be followed by text. An opener with no such closer is a one-line comment, as in the engine (#22).
- A standalone attribute block no longer runs across a blank line (#22).
- Bare delimiters follow Carve's flanking rules, so `snake_case_name`, `/usr/local/bin`, `x=1 and y=2`, `2*3*4` and the text between `==>` arrows stay text (#23).
- Emphasis content is lexed inline: an escape, a code span, a link or another kind of emphasis inside a run keeps its own token, and `*a \* b*` closes where the engine closes it (#23). A run opened inside another must close before it, so `*a /b* c/` is strong `a /b` (#24).
- A list marker or a caption under a paragraph line stays text, as in the engine; headings, quotes, tables, containers and closed fences still interrupt it. A wrapped definition term keeps its definition (#23).
- A table row needs its closing pipe, `+` is no longer read as a bullet, and an alphabetic ordered marker is one letter or a roman numeral, so `Body.` is a word (#23).
- Lexing a long line of unclosed openers (`*a *a *a ...`, `{{ a {{ a ...`) is linear in its length; it used to be quadratic (#23).
- The gem now requires Rouge 3.30 or later. Rouge 3.0, which the old constraint admitted, cannot load the lexer (#23).

## [0.1.2] - 2026-10-08

- An include selector whose id starts with a digit is lexed as a selector. `{{ ch.crv #2024-plan }}` used to fall through to plain text, because the lexer required a letter or underscore first while the spec's `explicit_identifier` has admitted a leading digit since carve 0.1.8 (#15).

## [0.1.1] - 2026-09-21

- The reserved include directive `{{ path #section @key:value }}` (PART 9
  section 19, markup-carve/carve#291) is lexed BY PART: the path as
  `Name.Namespace`, the selector as `Name.Label`, and each option as
  `Name.Attribute` plus its value. It used to shred into the constructs its own
  selector is spelled with, so `#intro` in a path was colored as a hashtag.

## [0.1.0] - 2026-08-27

First release.

- Every Carve construct: headings, containers, fenced and raw blocks, tables
  with alignment and per-row attributes, definition lists, footnotes,
  citations, cross-references, attribute blocks, task items, critic markup,
  symbol shortcodes, mentions, tags and typographic runs.
- Fenced code is delegated to a lexer for its declared language; a `=FORMAT`
  raw block stays opaque, because a format is not a language.
- Fence widths are closed over per block, so a shorter inner fence does not
  end a wider one.
- Input preservation is gated: concatenating the token values reproduces the
  source exactly, checked over every document in the Carve corpus.
- Construct parity with the sibling grammars is gated against the same
  inventory the highlight.js definition answers to.
