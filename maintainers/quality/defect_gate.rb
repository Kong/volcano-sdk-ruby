# frozen_string_literal: true

require_relative 'defect_check'

module Quality
  # A deliberately limited mutation catalog complements the Ruby property suite.
  class DefectGate
    REQUIRED = %w[
      credential-leakage stale-session-overwrite incorrect-lock-ownership binary-corruption premature-realtime-cursor
    ].freeze

    def initialize(root)
      @root = root
      @reports = File.join(root, 'reports/defects')
    end

    def run
      FileUtils.mkdir_p(@reports)
      FileUtils.rm_f(File.join(@reports, 'summary.json'))
      results = catalog.map { |defect| DefectCheck.new(root: @root, defect: defect, reports: @reports).run }
      File.write(File.join(@reports, 'summary.json'), JSON.pretty_generate(results))
      results.each { |result| puts "#{result.fetch(:name)}: #{result.fetch(:outcome)}" }
      results.all? { |result| result.fetch(:outcome) == 'detected' }
    end

    private

    def catalog
      defects = JSON.parse(File.read(File.join(@root, 'maintainers/injected-defects.json')))
      raise 'Injected-defect catalog must contain each required defect exactly once' unless
        defects.map { |defect| defect.fetch('name') }.sort! == REQUIRED.sort

      defects.each { |defect| validate_paths(defect) }
    end

    def validate_paths(defect)
      %w[path spec].each do |key|
        value = defect.fetch(key)
        raise 'Defect paths must remain inside the checkout' unless
          File.expand_path(value, @root).start_with?("#{@root}/") && !File.symlink?(File.join(@root, value))
      end
    end
  end
end
