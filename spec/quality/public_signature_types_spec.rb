# frozen_string_literal: true

require 'rbs'

class PublicSignatureTypes < RBS::AST::Visitor
  attr_reader :untyped, :unchecked

  def initialize
    super
    @untyped = []
    @unchecked = []
  end

  def visit(node)
    inspect_node_type(node)
    inspect_generics(node)
    inspect_overloads(node) if node.respond_to?(:overloads)
    super
  end

  private

  def inspect_node_type(node)
    inspect_type(node.type) if node.respond_to?(:type)
    inspect_types(node.args) if node.respond_to?(:args)
  end

  def inspect_generics(node)
    inspect_bounds(node.type_params) if node.respond_to?(:type_params)
    inspect_superclass(node.super_class) if node.respond_to?(:super_class)
    inspect_self_types(node.self_types) if node.respond_to?(:self_types)
  end

  def inspect_types(types) = types.each { |type| inspect_type(type) }

  def inspect_bounds(params)
    inspect_types(params.flat_map { |param| [param.upper_bound, param.default_type].compact })
  end

  def inspect_superclass(parent)
    inspect_types(parent.args) if parent
  end

  def inspect_self_types(types) = types.each { |type| inspect_types(type.args) }

  def inspect_overloads(node)
    @unchecked << node.location if node.overloading
    node.overloads.each do |overload|
      overload.method_type.each_type { |type| inspect_type(type) }
      inspect_bounds(overload.method_type.type_params)
    end
  end

  def inspect_type(type)
    return unless type.respond_to?(:each_type)

    @untyped << type.location if type.is_a?(RBS::Types::Bases::Any)
    type.each_type { |child| inspect_type(child) }
  end
end

RSpec.describe PublicSignatureTypes do
  let(:root) { File.expand_path('../..', __dir__) }

  def inspect_signature(source, name)
    buffer = RBS::Buffer.new(name: name, content: source)
    visitor = described_class.new
    visitor.visit_all(RBS::Parser.parse_signature(buffer).last)
    visitor
  end

  it 'ships no untyped or unchecked public declarations' do
    signatures = Dir.glob(File.join(root, 'sig/**/*.rbs'))
    expect(signatures).not_to be_empty

    violations = signatures.flat_map do |path|
      result = inspect_signature(File.read(path), path)
      (result.untyped + result.unchecked).map { |location| "#{path}:#{location.start_line}" }
    end
    expect(violations).to be_empty
  end

  it 'rejects nested untyped values without mistaking a comment for a signature' do
    source = <<~RBS
      # untyped here is explanatory text, not a type.
      class Probe
        def call: (Array[Hash[String, untyped]]) -> String
      end
    RBS
    result = inspect_signature(source, 'probe.rbs')

    expect(result.untyped.map(&:start_line)).to eq([3])
  end

  it 'rejects untyped aliases, attributes, and unchecked overloads' do
    source = <<~RBS
      type payload = Hash[String, untyped]
      class Probe
        attr_reader value: untyped
        def call: (String) -> String
                | ...
      end
    RBS
    result = inspect_signature(source, 'probe.rbs')

    expect(result.untyped.map(&:start_line)).to eq([1, 3])
    expect(result.unchecked.map(&:start_line)).to eq([4])
  end

  it 'rejects untyped generic ancestors and module self types' do
    source = <<~RBS
      interface _Interface[T]
      end
      class Base[T]
      end
      class Child < Base[untyped]
      end
      module Provider : _Interface[untyped]
      end
    RBS
    result = inspect_signature(source, 'probe.rbs')

    expect(result.untyped.map(&:start_line)).to eq([5, 7])
  end

  it 'rejects untyped generic defaults' do
    result = inspect_signature("class Probe[T = untyped]\nend\n", 'probe.rbs')

    expect(result.untyped.map(&:start_line)).to eq([1])
  end
end
