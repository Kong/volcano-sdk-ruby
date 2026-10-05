# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'steep'
require 'tmpdir'
require_relative 'dynamic_annotation_source'

module SpecSupport
  # Proves exact annotation scope and necessity using the pinned native tools.
  module DynamicAnnotations
    INVENTORY = 'maintainers/steep-dynamic-methods.json'
    STEEPFILES = %w[Steepfile Steepfile.transport].freeze
    COPY_PATHS = %w[sig sig_dev sig_client tests/types].freeze

    def self.records(root)
      JSON.parse(File.read(File.join(root, INVENTORY)))
    end

    def self.expected_entries(root)
      records(root).flat_map do |record|
        record.fetch('methods').map { |name| [record.fetch('path'), record.fetch('scope'), name] }
      end
    end

    def self.source_entries(root)
      lint_targets(root).flat_map do |path|
        DynamicAnnotationSource.new(File.read(File.join(root, path)), path).entries
      end
    end

    def self.missing_implementations(root)
      Dir.mktmpdir('volcano-dynamic-necessity-') do |directory|
        copy_project(root, directory)
        STEEPFILES.flat_map { |config| diagnostic_entries(directory, config) }
      end
    end

    def self.expected_diagnostics(root)
      expected_entries(root).map do |path, scope, name|
        method = name.start_with?('self.') ? ".#{name.delete_prefix('self.')}" : "##{name}"
        [path, 'Ruby::MethodDefinitionMissing', "Cannot find implementation of method `::#{scope}#{method}`", :error]
      end
    end

    def self.lint_targets(root)
      output, errors, status = Open3.capture3(
        Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--list-target-files', chdir: root
      )
      raise "RuboCop discovery failed: #{output}#{errors}" unless status.success?

      output.lines.map(&:strip)
    end

    def self.copy_project(root, directory)
      (COPY_PATHS + STEEPFILES).each do |path|
        destination = File.join(directory, path)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp_r(File.join(root, path), destination)
      end
      runtime_sources(root).each { |path| copy_without_annotations(root, directory, path) }
    end

    def self.runtime_sources(root)
      Dir.glob('lib/**/*.rb', base: root).reject { |path| path.start_with?('lib/volcano/generated/') }
    end

    def self.copy_without_annotations(root, directory, path)
      source = DynamicAnnotationSource.new(File.read(File.join(root, path)), path)
      destination = File.join(directory, path)
      FileUtils.mkdir_p(File.dirname(destination))
      File.write(destination, source.without_annotations)
    end

    def self.diagnostic_entries(directory, config)
      report = Pathname(File.join(directory, "#{config}.diagnostics.yml"))
      output, errors, status = Open3.capture3(
        Gem.ruby, Gem.bin_path('steep', 'steep'), 'check', "--steepfile=#{config}", '--jobs=1',
        "--save-expectations=#{report}", chdir: directory
      )
      raise "Steep diagnostic export failed: #{output}#{errors}" unless status.success?

      structured_diagnostics(report)
    end

    def self.structured_diagnostics(report)
      Steep::Expectations.load(path: report, content: report.read).diagnostics.flat_map do |path, diagnostics|
        diagnostics.map { |diagnostic| [path.to_s, diagnostic.code, diagnostic.message, diagnostic.severity] }
      end
    end
    private_class_method :lint_targets, :copy_project, :runtime_sources, :copy_without_annotations,
                         :diagnostic_entries, :structured_diagnostics
  end
end
