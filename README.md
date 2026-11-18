# rouge-carve

Rouge lexer for Carve 0.1 syntax. It registers `.crv`, `.carve`, and Carve fenced code for Rouge 3.30 or later. Read the [Carve documentation](https://markup-carve.github.io/carve/) for the language syntax.

## Install

```sh
gem install rouge-carve
```

## Usage

```ruby
require 'rouge-carve'
Rouge::Lexer.find('carve')
```

For Carve 0.2 documents, select the separate lexer:

```ruby
Rouge::Lexer.find('carve2')
```

The `crv2` alias selects the same 0.2 lexer. The `carve` and `crv` entries
continue to use the 0.1 rules.

## Documentation

- [Carve documentation](https://markup-carve.github.io/carve/)
- [Documentation index](docs/README.md)
- [Development](docs/development.md)

## License

[MIT](LICENSE)
