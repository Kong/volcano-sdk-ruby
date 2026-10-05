# frozen_string_literal: true

require 'rubocop'

module SpecSupport
  # Resolves real annotation comments against Ruby's lexical namespaces.
  class DynamicAnnotationSource
    DIRECTIVE = /\A\#\s*@dynamic(?:\s+|\z)(.*)\z/
    SCOPES = %i[class module sclass def defs block].freeze

    def initialize(source, path)
      @source = RuboCop::ProcessedSource.new(source, 3.2, path)
      @path = path
    end

    def entries
      annotations.flat_map do |comment, names|
        scope = namespace(comment)
        names.map { |name| [@path, scope, name] }
      end
    end

    def without_annotations
      corrector = RuboCop::Cop::Corrector.new(@source)
      annotations.each { |entry| corrector.remove(entry.first.source_range) }
      corrector.rewrite
    end

    private

    def annotations
      @source.comments.filter_map do |comment|
        match = DIRECTIVE.match(comment.text)
        next unless match

        names = match[1].split(/\s*,\s*/)
        raise "Empty dynamic annotation in #{@path}" if names.empty?

        [comment, names]
      end
    end

    def namespace(comment)
      node = containing_scopes(comment).min_by { |scope| scope.source_range.size }
      raise "Dynamic annotation outside a class/module body in #{@path}" unless namespace_node?(node)

      qualified_scope(node)
    end

    def namespace_node?(node)
      node && (node.class_type? || node.module_type?)
    end

    def qualified_scope(node)
      parent = node.parent_module_name
      [parent == 'Object' ? nil : parent, node.defined_module_name].compact.join('::')
    end

    def containing_scopes(comment)
      return [] unless @source.ast

      @source.ast.each_node(*SCOPES).select do |node|
        node.source_range.contains?(comment.source_range)
      end
    end
  end
end
