# Development

Run `bundle exec rspec` to check the 0.2 scope inventory and package version.

The corpus gates lex every Carve input of the spec repository (its `.crv` files and the 0.2 conformance corpus under `spec/0.2/conformance/`), given a checkout of markup-carve/carve:

```bash
ruby script/corpus_check.rb ../carve        # no Error token, no crash
ruby script/preservation_check.rb ../carve  # the tokens concatenate back to the input
```
