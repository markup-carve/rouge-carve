# Changelog

## Unreleased

Initial lexer.

- Every Carve construct: headings, containers, fenced and raw blocks, tables
  with alignment and per-row attributes, definition lists, footnotes,
  citations, cross-references, attribute blocks, task items, critic markup,
  symbol shortcodes, mentions, tags and typographic runs.
- Fenced code is delegated to a lexer for its declared language; a `=FORMAT`
  raw block stays opaque, because a format is not a language.
- Fence widths are closed over per block, so a shorter inner fence does not
  end a wider one.
