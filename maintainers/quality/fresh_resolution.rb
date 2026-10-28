# frozen_string_literal: true

require 'bundler'
require 'json'
require 'open3'

# Relocks the bundle to the runtime gems a fresh `gem install volcano-sdk`
# resolves, so the specs test what customers install instead of Gemfile.lock.
module FreshResolution
  # Lists the gems RubyGems activates for the SDK as name => [version, default gem?].
  CLOSURE = <<~RUBY
    gem 'volcano-sdk'
    pending = ['volcano-sdk']
    closure = {}
    until pending.empty?
      spec = Gem.loaded_specs.fetch(pending.shift)
      next if closure.key?(spec.name)

      closure[spec.name] = [spec.version.to_s, spec.default_gem?]
      pending.concat(spec.runtime_dependencies.map(&:name))
    end
    closure.delete('volcano-sdk')
    puts JSON.generate(closure)
  RUBY

  def self.installed(artifact, directory)
    home = File.join(directory, 'gems')
    environment = { 'GEM_HOME' => home, 'GEM_PATH' => home, 'GEM_SPEC_CACHE' => File.join(directory, 'spec-cache'),
                    'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLE_GEMFILE' => nil }
    run!(environment, Gem.ruby, '-S', 'gem', 'install', artifact, '--no-document', '--clear-sources',
         '--source', 'https://rubygems.org', chdir: directory)
    JSON.parse(run!(environment, Gem.ruby, '-rjson', '-e', CLOSURE, chdir: directory))
  end

  def self.locked(root)
    specs = lock_specs(root)
    closure(specs, 'volcano-sdk', Set.new).to_h { |name| [name, specs.fetch(name).version.to_s] }
  end

  def self.relock!(root, installed)
    run!({}, 'bundle', 'lock', '--update', *(installed.keys & lock_specs(root).keys), chdir: root)
    run!({}, 'bundle', 'install', chdir: root)
    resolved = locked(root)
    held = installed.reject { |name, (version, default)| default || resolved[name] == version }
    return if held.empty?

    raise "Development dependencies hold runtime gems below a fresh install: #{held.keys.join(', ')}"
  end

  def self.report(locked, installed, summary = ENV.fetch('GITHUB_STEP_SUMMARY', nil))
    rows = installed.sort
    rows.map! { |name, (version, default)| [name, locked.fetch(name, 'none'), label(version, default)] }
    rows.each do |name, before, after|
      puts "::warning::#{name}: Gemfile.lock #{before}, fresh install #{after}" unless before == after
    end
    table = markdown(rows)
    puts table
    File.write(summary, table, mode: 'a') if summary
  end

  def self.label(version, default) = default ? "#{version} (Ruby default gem)" : version

  def self.markdown(rows)
    lines = ['| Gem | Gemfile.lock | Fresh install |', '| --- | --- | --- |']
    lines.concat(rows.map { |row| "| #{row.join(' | ')} |" })
    "#{lines.join("\n")}\n"
  end

  def self.lock_specs(root)
    Bundler::LockfileParser.new(File.read(File.join(root, 'Gemfile.lock'))).specs.to_h { |spec| [spec.name, spec] }
  end

  def self.closure(specs, name, seen)
    specs.fetch(name).dependencies.each do |dependency|
      closure(specs, dependency.name, seen) if seen.add?(dependency.name)
    end
    seen
  end

  def self.run!(environment, *command, chdir:)
    output, error, status = Open3.capture3(environment, *command, chdir: chdir)
    raise "#{command.join(' ')} failed:\n#{output}#{error}" unless status.success?

    output
  end
  private_class_method :label, :markdown, :lock_specs, :closure, :run!
end
