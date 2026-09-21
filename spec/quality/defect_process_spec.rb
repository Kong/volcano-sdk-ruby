# frozen_string_literal: true

require_relative '../../maintainers/quality/defect_process'
require 'tmpdir'
require 'fileutils'

RSpec.describe Quality::DefectProcess do
  let(:directory) { Dir.mktmpdir('defect-process-spec-') }
  let(:log) { File.join(directory, 'process.log') }

  after { FileUtils.remove_entry(directory) }

  it 'preserves the child exit status and log' do
    status = described_class.new.run([Gem.ruby, '-e', "warn 'failure'; exit 7"], directory: directory, log: log)
    expect(status).to eq(7)
    expect(File.read(log)).to include('failure')
  end

  it 'kills and reaps a process that exceeds its deadline' do
    command = [Gem.ruby, '-e', '$stdout.sync = true; puts Process.pid; sleep 30']
    status = described_class.new(timeout: 2).run(command, directory: directory, log: log)
    expect(status).to eq(:timeout)
    pid = Integer(File.read(log).lines.last)
    expect(pid).to be_positive
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  end
end
