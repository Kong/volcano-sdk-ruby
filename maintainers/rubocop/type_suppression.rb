# frozen_string_literal: true

require 'steep'
require_relative 'annotation_types'

module RuboCop
  module Cop
    module Volcano
      # Rejects Steep directives and annotations that erase checked types.
      class TypeSuppression < Base
        MSG = 'Use checked types instead of silencing Steep or asserting a type.'
        DIRECTIVE = /\#\s*steep:ignore\b/

        def on_new_investigation
          processed_source.comments.each do |comment|
            add_offense(comment) if suppression?(comment)
          end
        end

        private

        def suppression?(comment)
          comment.text.match?(DIRECTIVE) || unchecked_annotation?(comment)
        end

        def unchecked_annotation?(comment)
          return false unless comment.inline?

          content = comment.text.delete_prefix('#').strip
          buffer = RBS::Buffer.new(name: processed_source.path, content: content)
          location = RBS::Location.new(buffer, 0, content.length)
          AnnotationTypes.new.unchecked?(location)
        end
      end
    end
  end
end
