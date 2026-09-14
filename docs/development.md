# Development

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
