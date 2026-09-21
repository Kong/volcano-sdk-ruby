# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

module Quality
  # Snapshot current maintained files, including uncommitted edits, without ignored dependencies.
  class DefectCheckout
    def initialize(root)
      @root = root
    end

    def open
      Dir.mktmpdir('volcano-sdk-defect-') do |directory|
        files.each { |path| copy(path, directory) }
        yield directory
      end
    end

    private

    def files
      output, error, status = Open3.capture3(
        'git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', chdir: @root
      )
      raise error unless status.success?

      output.split("\0").uniq
    end

    def copy(path, directory)
      source = File.join(@root, path)
      return unless File.file?(source)

      target = File.join(directory, path)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(source, target, preserve: true)
    end
  end
end
