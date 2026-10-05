# frozen_string_literal: true

module RuboCop
  module Cop
    module Volcano
      # Rejects SimpleCov directives that hide runtime code from coverage.
      class CoverageSuppression < Base
        MSG = 'Cover the code instead of disabling coverage.'
        DIRECTIVE = /\#\s*(?:simplecov\s*:\s*disable\b|:nocov:)/

        def on_new_investigation
          processed_source.comments.each do |comment|
            add_offense(comment) if comment.text.match?(DIRECTIVE)
          end
        end
      end
    end
  end
end
