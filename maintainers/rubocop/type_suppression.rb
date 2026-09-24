# frozen_string_literal: true

module RuboCop
  module Cop
    module Volcano
      # Rejects Steep directives that silence type diagnostics.
      class TypeSuppression < Base
        MSG = 'Fix the type error instead of disabling Steep.'
        DIRECTIVE = /\#\s*steep:ignore\b/

        def on_new_investigation
          processed_source.comments.each do |comment|
            add_offense(comment) if comment.text.match?(DIRECTIVE)
          end
        end
      end
    end
  end
end
