#!/usr/bin/env ruby
# frozen_string_literal: true

# Lex every Carve source of the spec checkout and fail on an Error token.
#
# A lexer emitting Error is telling the reader its own rules ran out, and the
# shapes that do it are never the ones in the spec suite - they are the blank
# line inside a comment fence and the `---` that was a thematic break. Both of
# those were found this way rather than by writing another example.

require 'rouge'
require_relative '../lib/rouge-carve'
require_relative 'corpus'

root = ARGV[0] || '.'
failures = Hash.new { |h, k| h[k] = [] }
crashes = []
count = 0

CorpusSources.each(root) do |label, source|
  count += 1
  begin
    Rouge::Lexers::Carve.new.lex(source).each do |token, value|
      failures[label] << value if token.qualname == 'Error'
    end
  rescue StandardError => e
    crashes << "#{label}: #{e.class}: #{e.message}"
  end
end

puts "lexed #{count} source(s)"

unless crashes.empty?
  puts "CRASHED on #{crashes.size}:"
  crashes.first(20).each { |c| puts "  #{c}" }
end

unless failures.empty?
  puts "ERROR tokens in #{failures.size} source(s):"
  failures.first(20).each { |label, values| puts "  #{label}: #{values.first(5).map(&:inspect).join(', ')}" }
end

exit 1 unless crashes.empty? && failures.empty?
puts 'no error tokens'
