# frozen_string_literal: true

require 'json'

# Every Carve source in the spec checkout at +root+: the .crv files, and the
# inputs (and served include files) of the 0.2 conformance corpus.
module CorpusSources
  CONFORMANCE = %w[examples.json clause-cases.json extensions.json].freeze

  def self.each(root)
    return enum_for(:each, root) unless block_given?

    Dir.glob(File.join(root, '**', '*.crv')).reject { |f| f.include?('/node_modules/') }.each do |path|
      yield path, File.read(path, encoding: 'utf-8')
    end

    dir = File.join(root, 'spec', '0.2', 'conformance')
    CONFORMANCE.each do |name|
      path = File.join(dir, name)
      abort "missing #{path}: the 0.2 conformance corpus is the gate's input" unless File.file?(path)

      doc = JSON.parse(File.read(path, encoding: 'utf-8'), max_nesting: false)
      entries = doc['examples'] || doc['cases'] or abort "#{path} holds no examples or cases"
      entries.each do |entry|
        yield "#{name}##{entry['id']}", entry['input'] if entry['input'].is_a?(String)
        (entry['files'] || {}).each do |file, body|
          yield "#{name}##{entry['id']}:#{file}", body['text'] if body.is_a?(Hash) && body['text'].is_a?(String)
        end
      end
    end
  end
end
