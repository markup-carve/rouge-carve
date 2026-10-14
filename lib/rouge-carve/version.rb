# frozen_string_literal: true

# Kept apart from the entry file so the gemspec can read it without loading
# Rouge, which is not installed yet when Bundler evaluates the gemspec.
module RougeCarve
  VERSION = '0.1.3'
end
