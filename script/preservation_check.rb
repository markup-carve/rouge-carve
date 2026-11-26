#!/usr/bin/env ruby
# frozen_string_literal: true

# Concatenating a lexer's token values must reproduce its input exactly.
# A dropped or duplicated character is invisible in a scope check.

require 'rouge'
require_relative '../lib/rouge-carve'
require_relative 'corpus'

root = ARGV[0] || '.'
bad = []
count = 0

CorpusSources.each(root) do |label, source|
  count += 1
  out = +''
  Rouge::Lexers::Carve.new.lex(source) { |_, value| out << value }
  next if out == source

  i = 0
  i += 1 while i < source.length && i < out.length && source[i] == out[i]
  bad << [label, source.length, out.length, source[[i - 20, 0].max, 60].inspect, out[[i - 20, 0].max, 60].inspect]
end

puts "checked #{count} source(s)"
if bad.empty?
  puts 'every source round-trips exactly'
  exit 0
end

puts "#{bad.size} source(s) did NOT round-trip:"
bad.first(10).each do |label, from, to, want, got|
  puts "  #{label} (#{from} -> #{to})"
  puts "    want #{want}"
  puts "    got  #{got}"
end
exit 1
