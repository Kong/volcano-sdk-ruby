# frozen_string_literal: true

require 'json'
require 'open3'

# Checks the native SimpleCov report after its RSpec process has exited.
class CoverageReport
  def initialize(root, run_id)
    @root = root
    @run_id = run_id
  end

  def verify!
    path = File.join(@root, 'reports', 'coverage', @run_id, 'coverage.json')
    raise "Missing SimpleCov report for this run: #{path}" unless File.file?(path)

    report = JSON.parse(File.read(path))
    %w[lines branches].each { |criterion| verify_total!(report.fetch('total').fetch(criterion), criterion) }
    missing = runtime_sources - report.fetch('coverage').keys
    raise "Runtime files absent from SimpleCov report: #{missing.join(', ')}" unless missing.empty?
  end

  private

  def verify_total!(total, criterion)
    return if total.fetch('total').positive? && total.fetch('missed').zero? &&
              total.fetch('covered') == total.fetch('total')

    raise "Incomplete #{criterion} coverage in SimpleCov report"
  end

  def runtime_sources
    output, error, status = Open3.capture3('git', 'ls-files', '--cached', '--others', '--exclude-standard',
                                           '-z', '--', 'lib', chdir: @root)
    raise error unless status.success?

    paths = output.split("\0")
    paths.select! { |path| path.end_with?('.rb') && path.start_with?('lib/') }
    paths.reject! { |path| path.start_with?('lib/volcano/generated/') }
    paths
  end
end
