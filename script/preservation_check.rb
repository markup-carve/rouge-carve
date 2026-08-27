#!/usr/bin/env ruby
# frozen_string_literal: true

# Concatenating a lexer's token values must reproduce its input exactly.
# A dropped or duplicated character is invisible in a scope check.

require 'rouge'
require_relative '../lib/rouge-carve'

root = ARGV[0] || '.'
files = Dir.glob(File.join(root, '**', '*.crv')).reject { |f| f.include?('/node_modules/') }
abort "no .crv files found under #{root}" if files.empty?

bad = []
files.each do |path|
  source = begin
    File.read(path, encoding: 'utf-8')
  rescue StandardError
    next
  end

  out = +''
  Rouge::Lexers::Carve.new.lex(source) { |_, value| out << value }
  next if out == source

  i = 0
  i += 1 while i < source.length && i < out.length && source[i] == out[i]
  bad << [path, source.length, out.length, source[[i - 20, 0].max, 60].inspect, out[[i - 20, 0].max, 60].inspect]
end

puts "checked #{files.size} document(s)"
if bad.empty?
  puts 'every document round-trips exactly'
  exit 0
end

puts "#{bad.size} document(s) did NOT round-trip:"
bad.first(10).each do |path, from, to, want, got|
  puts "  #{path} (#{from} -> #{to})"
  puts "    want #{want}"
  puts "    got  #{got}"
end
exit 1
