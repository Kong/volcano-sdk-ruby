# frozen_string_literal: true

require_relative 'defect_checkout'
require_relative 'defect_process'
require_relative 'defect_result'

module Quality
  # Check the original example, apply one exact defect, then require an assertion failure.
  class DefectCheck
    def initialize(root:, defect:, reports:, process: DefectProcess.new)
      @root = root
      @defect = defect
      @reports = reports
      @process = process
    end

    def run
      DefectCheckout.new(@root).open { |directory| check(directory) }
    rescue StandardError => e
      { name: @defect.fetch('name'), outcome: 'harness_error', detail: e.message }
    end

    private

    def check(directory)
      baseline = example(directory, 'baseline')
      return result('baseline_failed', baseline) unless baseline == 'passed'

      failure = mutation_failure(directory)
      return result(failure) if failure

      outcome = example(directory, 'mutant')
      result(outcome == 'passed' ? 'survived' : outcome)
    end

    def result(outcome, detail = nil)
      { name: @defect.fetch('name'), outcome: outcome, detail: detail }
    end

    def apply?(directory)
      path = File.join(directory, @defect.fetch('path'))
      source = File.read(path)
      before = @defect.fetch('before')
      offset = source.index(before)
      return false if before.empty? || offset.nil?
      return false unless offset == source.rindex(before)
      return false if before == @defect.fetch('after')

      File.write(path, source.sub(before) { @defect.fetch('after') })
      true
    end

    def mutation_failure(directory)
      return 'stale_patch' unless apply?(directory)

      case syntax_status(directory)
      when 0 then nil
      when :timeout then 'timeout'
      else 'invalid_mutation'
      end
    end

    def syntax_status(directory)
      @process.run([Gem.ruby, '-c', @defect.fetch('path')],
                   directory: directory, log: report_path('syntax', 'log'))
    end

    def example(directory, phase)
      report = report_path(phase, 'json')
      FileUtils.rm_f(report)
      status = @process.run(command(directory, report), directory: directory, log: report_path(phase, 'log'))
      DefectResult.new(report, status).outcome
    end

    def command(directory, report)
      [environment(directory), Gem.ruby, '-rbundler/setup', '-Ilib', Gem.bin_path('rspec-core', 'rspec'),
       @defect.fetch('spec'), '--example', @defect.fetch('example'),
       '--format', 'json', '--out', report]
    end

    def environment(directory)
      path = Bundler.settings[:path]
      { 'BUNDLE_GEMFILE' => File.join(directory, 'Gemfile'),
        'BUNDLE_PATH' => path && File.expand_path(path, @root), 'BUNDLE_PATH__SYSTEM' => path ? nil : 'true',
        'VOLCANO_PROPERTY_SEED' => '12345' }
    end

    def report_path(phase, extension)
      File.join(@reports, "#{@defect.fetch('name')}-#{phase}.#{extension}")
    end
  end
end
