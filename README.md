# rouge-carve

Rouge lexer for Carve 0.2 syntax. It registers `carve` and `crv` for `.crv` and `.carve` files.

```ruby
require 'rouge-carve'
Rouge::Lexer.find('carve')
```

See the [Carve documentation](https://markup-carve.github.io/carve/) for source syntax.
