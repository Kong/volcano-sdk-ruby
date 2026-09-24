# frozen_string_literal: true

require_relative '../support/dynamic_annotation_source'

RSpec.describe SpecSupport::DynamicAnnotationSource do
  def parse(source)
    described_class.new(source, 'lib/probe.rb')
  end

  it 'distinguishes namespaces and singleton methods without consuming string contents' do
    source = <<~RUBY
      module Outer
        class First
          # @dynamic call, self.build
          def text = '# @dynamic not_an_annotation'
        end
        module Second
          # @dynamic call
        end
      end
    RUBY
    expect(parse(source).entries).to contain_exactly(
      ['lib/probe.rb', 'Outer::First', 'call'], ['lib/probe.rb', 'Outer::First', 'self.build'],
      ['lib/probe.rb', 'Outer::Second', 'call']
    )
  end

  it 'preserves duplicate names so inventory matching rejects repeated exceptions' do
    expect(parse("class Probe\n  # @dynamic call, call\nend\n").entries).to eq(
      [['lib/probe.rb', 'Probe', 'call'], ['lib/probe.rb', 'Probe', 'call']]
    )
  end

  it 'exposes an unauthorized scope or method instead of silently discarding it' do
    expect(parse("class Unknown\n  # @dynamic invented\nend\n").entries).to eq(
      [['lib/probe.rb', 'Unknown', 'invented']]
    )
  end

  it 'rejects an empty annotation' do
    expect { parse("class Probe\n  # @dynamic\nend\n").entries }.to raise_error(/Empty dynamic annotation/)
  end

  it 'rejects annotations outside a namespace or nested inside a method' do
    sources = ["# @dynamic call\n", "class Probe\n  def call\n    # @dynamic call\n  end\nend\n"]
    sources.each do |source|
      expect { parse(source).entries }.to raise_error(%r{outside a class/module body})
    end
  end

  it 'removes only actual annotation comments while preserving code and line numbers' do
    source = "class Probe\n  # @dynamic call\n  def text = '# @dynamic literal'\nend\n"
    expected = "class Probe\n  \n  def text = '# @dynamic literal'\nend\n"
    expect(parse(source).without_annotations).to eq(expected)
  end
end
