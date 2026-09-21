# frozen_string_literal: true

require 'open3'
require 'ripper'
require 'rubocop'
require 'yaml'

module Quality
  # Checks maintained sources against the linter's actual discovered targets.
  class SourcePolicy
    GENERATED = 'lib/volcano/generated/'
    RUBY_PATTERNS = RuboCop::ConfigLoader.default_configuration.for_all_cops.fetch('Include').freeze
    SUPPRESSION = /rubocop\s*:\s*(?:disable|todo)|:nocov:/i
    private_constant :GENERATED, :RUBY_PATTERNS, :SUPPRESSION

    def initialize(root)
      @root = File.expand_path(root)
      @errors = []
    end

    def check
      @errors.clear
      check_inheritance
      paths = repository_files.reject { |path| path.start_with?(GENERATED) }
      paths.each { |path| check_configuration(path) }
      sources = paths.select { |path| ruby_source?(path) }
      sources.each { |path| check_comments(path) }
      check_targets(sources)
      @errors
    end

    private

    def command(*)
      output, error, status = Open3.capture3(*, chdir: @root)
      raise "Policy discovery failed: #{error}" unless status.success?

      output
    end

    def repository_files
      command('git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split("\0").uniq.select do |path|
        File.exist?(File.join(@root, path)) || File.symlink?(File.join(@root, path))
      end
    end

    def check_inheritance
      configuration = YAML.safe_load_file(File.join(@root, '.rubocop.yml'), aliases: true)
      return unless configuration.key?('inherit_from') || configuration.key?('inherit_gem')

      @errors << '.rubocop.yml: inherited configurations are forbidden; keep policy in the root configuration'
    end

    def check_configuration(path)
      name = File.basename(path)
      return unless name.start_with?('.rubocop') || %w[.rspec .simplecov].include?(name)
      return if %w[.rubocop.yml .rspec].include?(path) && !File.symlink?(File.join(@root, path))

      @errors << "#{path}: nested overrides and debt-baseline configurations are forbidden"
    end

    def ruby_source?(path)
      if RUBY_PATTERNS.any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) }
        return true
      end
      return false if File.symlink?(File.join(@root, path))

      File.open(File.join(@root, path), 'rb') { |file| /\A#!.*\bruby\b/.match?(file.gets.to_s) }
    end

    def check_comments(path)
      full_path = File.join(@root, path)
      if File.symlink?(full_path)
        @errors << "#{path}: maintained Ruby sources must not be symlinks"
        return
      end
      Ripper.lex(File.read(full_path)).each do |position, event, content, _state|
        next unless event == :on_comment && SUPPRESSION.match?(content)

        @errors << "#{path}:#{position.first}: inline lint and coverage suppressions are forbidden"
      end
    end

    def check_targets(sources)
      targets = command(Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--list-target-files').lines.to_set do |line|
        File.expand_path(line.strip, @root)
      end
      sources.each do |path|
        next if targets.include?(File.join(@root, path))

        @errors << "#{path}: maintained Ruby source is excluded from RuboCop"
      end
      @errors << 'No maintained Ruby sources discovered' if sources.empty?
    end
  end
end
