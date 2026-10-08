# Changelog

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
