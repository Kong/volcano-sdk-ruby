# frozen_string_literal: true

require_relative '../../maintainers/quality/defect_process'
require 'json'
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

  it 'passes shell metacharacters to the child as literal arguments' do
    marker = File.join(directory, 'injected')
    payloads = ["; touch #{marker}", "$(touch #{marker})", "`touch #{marker}`", "| touch #{marker} && echo",
                'two words', %q('single' "double" \\ $HOME *), "line\nbreak"]
    output = File.join(directory, 'argv.json')
    command = [Gem.ruby, '-rjson', '-e', 'File.write(ARGV.shift, JSON.generate(ARGV))', output, *payloads]
    expect(described_class.new.run(command, directory: directory, log: log)).to eq(0)
    expect(JSON.parse(File.read(output))).to eq(payloads)
    expect(File).not_to exist(marker)
  end

  it 'runs a lone command string as a program name instead of a shell script' do
    marker = File.join(directory, 'injected')
    command = ["true; touch #{marker}"]
    expect { described_class.new.run(command, directory: directory, log: log) }.to raise_error(Errno::ENOENT)
    expect(File).not_to exist(marker)
  end

  it 'applies a leading environment hash without shell expansion' do
    probe = 'exit(ENV.fetch("DEFECT_PROCESS_PROBE") == "$(id); `id`" ? 0 : 3)'
    command = [{ 'DEFECT_PROCESS_PROBE' => '$(id); `id`' }, Gem.ruby, '-e', probe]
    expect(described_class.new.run(command, directory: directory, log: log)).to eq(0)
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
