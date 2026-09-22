# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

# Checks a consumer against the signatures shipped in the gem.
module SteepConsumer
  STEEPFILE = <<~RUBY
    target :consumer do
      signature 'sig'
      check 'consumer.rb'
      configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
    end
  RUBY

  def self.check(source)
    Dir.mktmpdir('volcano-type-consumer-') do |directory|
      FileUtils.cp_r(File.expand_path('../../sig', __dir__), File.join(directory, 'sig'))
      File.write(File.join(directory, 'consumer.rb'), source)
      File.write(File.join(directory, 'Steepfile'), STEEPFILE)
      Open3.capture3(
        Gem.ruby, Gem.bin_path('steep', 'steep'), 'check', '--jobs', '1', chdir: directory
      )
    end
  end
end
