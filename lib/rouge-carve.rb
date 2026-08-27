# frozen_string_literal: true

require 'rouge'
require_relative 'rouge/lexers/carve'

# A Rouge lexer for the Carve markup language.
#
# Requiring this file is the whole interface: defining the lexer class
# registers it, so `Rouge::Lexer.find('carve')` and
# `Rouge::Lexer.guess(filename: 'x.crv')` work from that point on.
module RougeCarve
  VERSION = '0.1.0'
end
