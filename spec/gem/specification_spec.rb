# frozen_string_literal: true

require 'bundler'

RSpec.describe Gem::Specification do
  let(:root) { File.expand_path('../..', __dir__) }

  it 'pins every runtime dependency to the version Gemfile.lock tests' do
    locked = Bundler::LockfileParser.new(File.read(File.join(root, 'Gemfile.lock'))).specs.to_h do |spec|
      [spec.name, "= #{spec.version}"]
    end
    pins = described_class.load(File.join(root, 'volcano-sdk.gemspec')).runtime_dependencies.to_h do |dependency|
      [dependency.name, dependency.requirement.to_s]
    end
    expect(pins).to eq(locked.slice(*pins.keys))
  end
end
