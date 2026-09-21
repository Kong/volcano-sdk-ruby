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
      new_cop_errors(configuration) + configuration.flat_map do |cop, settings|
        next [] unless settings.is_a?(Hash)

        disabled_errors(cop, settings) + scope_errors(cop, settings)
      end
    end

    def self.new_cop_errors(configuration)
      return [] if configuration.dig('AllCops', 'NewCops') == 'enable'

      ['.rubocop.yml: AllCops NewCops must be enable']
    end
    private_class_method :new_cop_errors

    def self.disabled_errors(cop, settings)
      disabled = settings['Enabled'] == false || settings['DisabledByDefault'] == true ||
                 settings['EnabledByDefault'] == false
      return [] unless disabled

      [".rubocop.yml: #{cop} disabling settings are forbidden"]
    end
    private_class_method :disabled_errors

    def self.scope_errors(cop, settings)
      return [] if cop == 'AllCops'

      exclusions = Array(settings['Exclude'])
      allowed = CONVENTIONS.fetch(cop, [])
      (exclusions - allowed).map do |scope|
        ".rubocop.yml: #{cop} exclusion #{scope.inspect} is not a permitted test convention"
      end
    end
    private_class_method :scope_errors
  end
end
