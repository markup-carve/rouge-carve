#!/usr/bin/env ruby
# frozen_string_literal: true

# Print spec/sample highlighted in the terminal. DEBUG=1 shows the token stream.

require 'rouge'
require_relative 'lib/rouge-carve'

source = File.read(File.expand_path(ARGV[0] || 'spec/sample', __dir__))
lexer = Rouge::Lexers::Carve.new

if ENV['DEBUG']
  lexer.lex(source) { |token, value| puts format('%-28s %p', token.qualname, value) }
else
  puts Rouge::Formatters::Terminal256.new(Rouge::Themes::ThankfulEyes.new).format(lexer.lex(source))
end
