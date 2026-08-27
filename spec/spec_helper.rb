# frozen_string_literal: true

require 'rouge'
require_relative '../lib/rouge-carve'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
end
