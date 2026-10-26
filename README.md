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

## Documentation

- [Carve documentation](https://markup-carve.github.io/carve/)
- [Documentation index](docs/README.md)
- [Development](docs/development.md)

## License

[MIT](LICENSE)
