# frozen_string_literal: true

require_relative 'lib/rouge-carve'

Gem::Specification.new do |spec|
  spec.name = 'rouge-carve'
  spec.version = RougeCarve::VERSION
  spec.authors = ['Mark Scherer']
  spec.summary = 'A Rouge lexer for the Carve markup language.'
  spec.description = <<~DESC.strip
    Syntax highlighting for Carve (.crv) wherever Rouge is the highlighter -
    GitLab, Jekyll, Redcarpet and most Ruby static site generators. Carve
    swaps several of Markdown's delimiters, so lexing it as Markdown is not
    merely imprecise, it inverts them.
  DESC
  spec.homepage = 'https://github.com/markup-carve/rouge-carve'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'documentation_uri' => 'https://markup-carve.github.io/carve/',
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.require_paths = ['lib']

  spec.add_dependency 'rouge', '>= 3.0', '< 6.0'
end
