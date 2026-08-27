# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe Volcano do
  it 'exports the client' do
    expect(Volcano::Client.name).to eq('Volcano::Client')
  end

  it 'keeps the generated namespace outside the public constant boundary' do
    expect { Volcano::Generated }.to raise_error(NameError, /private constant/)
  end

  it 'does not load the Async runtime for a REST-only require' do
    root = File.expand_path('..', __dir__)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      '-I', File.join(root, 'lib'),
      '-e', 'require "volcano"; puts(defined?(Async) || "absent")',
      chdir: root
    )

    expect(status).to be_success
    expect(stdout).to eq("absent\n")
    expect(stderr).not_to include('IO::Buffer is experimental')
  end
end
