# frozen_string_literal: true

module RuboCop
  module Cop
    module Volcano
      # Keeps native RBS nodes when Steep parses a source annotation.
      class AnnotationTypes
        def type(value) = value
        def method_type(value) = value

        def unchecked?(location)
          annotation = Steep::AnnotationParser.new(factory: self).parse(location.source, location: location)
          return untyped?(annotation.type) if annotation.respond_to?(:type)
          return true if Steep::AST::Node::TypeAssertion.parse(location)

          application = Steep::AST::Node::TypeApplication.parse(location)
          application && untyped?(RBS::Parser.parse_type("[#{application.type_str}]", require_eof: true))
        rescue Steep::AnnotationParser::SyntaxError, RBS::ParsingError
          true
        end

        private

        def untyped?(value)
          return true if value.is_a?(RBS::Types::Bases::Any)
          return true if unchecked_callable?(value)
          return true if unchecked_generics?(value)

          value.each_type.any? { |child| untyped?(child) }
        end

        def unchecked_callable?(value)
          return false unless value.is_a?(RBS::MethodType) || value.is_a?(RBS::Types::Proc)

          [value.type, value.block&.type].any?(RBS::Types::UntypedFunction)
        end

        def unchecked_generics?(value)
          return false unless value.respond_to?(:type_params)

          bounds = value.type_params.flat_map { |param| [param.upper_bound_type, param.default_type].compact }
          bounds.any? { |bound| untyped?(bound) }
        end
      end
    end
  end
end
