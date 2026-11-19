# Rouge Carve guide

Use `Rouge::Lexer.find('carve')` to highlight Carve 0.2 source. The lexer keeps delimiter punctuation separate from content tokens and delegates CSV and TSV fence bodies to specialized lexers. Its scope inventory is checked in `spec/carve_inventory_spec.rb`.
