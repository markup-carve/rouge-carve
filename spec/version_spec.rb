# frozen_string_literal: true

require 'spec_helper'

# The release gate compares VERSION with the tag, so a cut that dates a
# CHANGELOG section without moving VERSION only fails after the tag exists.
RSpec.describe 'RougeCarve::VERSION' do
  it 'matches the newest dated CHANGELOG section' do
    changelog = File.read(File.expand_path('../CHANGELOG.md', __dir__), encoding: 'UTF-8')
    newest = changelog[/^## \[?(\d+\.\d+\.\d+)\]? - \d{4}-\d{2}-\d{2}$/, 1]

    expect(newest).not_to be_nil
    expect(RougeCarve::VERSION).to eq(newest)
  end
end
