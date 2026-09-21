# frozen_string_literal: true

module Quality
  # Test examples and shared scenarios are blocks, and their prose is documentation.
  class CopScopePolicy
    CONVENTIONS = {
      'Metrics/BlockLength' => ['features/step_definitions/**/*', 'spec/**/*'],
      'Style/Documentation' => ['features/**/*', 'spec/**/*']
    }.freeze
    private_constant :CONVENTIONS

    def self.check(configuration)
      configuration.flat_map do |cop, settings|
        next [] if cop == 'AllCops' || !settings.is_a?(Hash)

        exclusions = Array(settings['Exclude'])
        allowed = CONVENTIONS.fetch(cop, [])
        (exclusions - allowed).map do |scope|
          ".rubocop.yml: #{cop} exclusion #{scope.inspect} is not a permitted test convention"
        end
      end
    end
  end
end
