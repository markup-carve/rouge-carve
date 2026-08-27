#!/usr/bin/env ruby
# frozen_string_literal: true

# Lex every Carve document under the given root and fail on an Error token.
#
# A lexer emitting Error is telling the reader its own rules ran out, and the
# shapes that do it are never the ones in the spec suite - they are the blank
# line inside a comment fence and the `---` that was a thematic break. Both of
# those were found this way rather than by writing another example.

require 'rouge'
require_relative '../lib/rouge-carve'

root = ARGV[0] || '.'
files = Dir.glob(File.join(root, '**', '*.crv')).reject { |f| f.include?('/node_modules/') }

abort "no .crv files found under #{root}" if files.empty?

failures = Hash.new { |h, k| h[k] = [] }
crashes = []

files.each do |path|
  source = begin
    File.read(path, encoding: 'utf-8')
  rescue StandardError
    next
  end

  begin
    Rouge::Lexers::Carve.new.lex(source).each do |token, value|
      failures[path] << value if token.qualname == 'Error'
    end
  rescue StandardError => e
    crashes << "#{path}: #{e.class}: #{e.message}"
  end
end

puts "lexed #{files.size} document(s)"

unless crashes.empty?
  puts "CRASHED on #{crashes.size}:"
  crashes.first(20).each { |c| puts "  #{c}" }
end

unless failures.empty?
  puts "ERROR tokens in #{failures.size} file(s):"
  failures.first(20).each { |path, values| puts "  #{path}: #{values.first(5).map(&:inspect).join(', ')}" }
end

exit 1 unless crashes.empty? && failures.empty?
puts 'no error tokens'
