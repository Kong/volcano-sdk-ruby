# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require_relative '../../features/support/contract_world'
require 'tmpdir'

RSpec.describe VolcanoContract::World do
  let(:credentials) do
    {
      'anon_key' => 'anon-fixture-secret',
      'service_key' => 'service-fixture-secret',
      'user_password' => 'password-fixture-secret'
    }
  end
  let(:fixture) do
    {
      'api_url' => 'https://api.test.volcano.dev',
      'storage_path' => 'contract.txt',
      'realtime_channel' => 'contract',
      'lock_key' => 'contract-lock',
      **credentials
    }
  end
  let(:world) { described_class.new(fixture) }

  it 'redacts fixture credentials from recorded report failures' do
    world.record do
      raise "request failed: #{credentials.values.join(' ')}"
    end

    message = world.last_outcome.error.message
    expect(message).to include('request failed:')
    expect(message.scan('[REDACTED]').length).to eq(3)
    credentials.each_value { |secret| expect(message).not_to include(secret) }
  end

  it 'keeps fixture credentials out of a failing Cucumber JUnit report' do
    root = File.expand_path('../..', __dir__)
    Dir.mktmpdir('volcano-ruby-cucumber-redaction') do |directory|
      feature_path = File.join(directory, 'redaction.feature')
      steps_path = File.join(directory, 'redaction_steps.rb')
      report_directory = File.join(directory, 'reports')
      File.write(feature_path, <<~FEATURE)
        Feature: Report redaction
          Scenario: A fixture failure reaches the report
            When a fixture failure reaches the report
      FEATURE
      File.write(steps_path, <<~RUBY)
        require #{File.join(root, 'lib/volcano').inspect}
        require #{File.join(root, 'features/support/contract_world').inspect}

        When('a fixture failure reaches the report') do
          fixture = #{fixture.inspect}
          world = VolcanoContract::World.new(fixture)
          world.record { raise "request failed: \#{fixture.values_at(*VolcanoContract::CREDENTIAL_KEYS).join(' ')}" }
          raise world.last_outcome.error
        end
      RUBY

      _stdout, _stderr, status = Open3.capture3(
        { 'CUCUMBER_PUBLISH_QUIET' => 'true' },
        'bundle', 'exec', 'cucumber', feature_path,
        '--require', steps_path,
        '--format', 'junit', '--out', report_directory,
        chdir: root
      )
      report = Dir.glob(File.join(report_directory, '**/*')).select { |path| File.file?(path) }
                  .map { |path| File.binread(path) }.join
      matches = credentials.values.count { |secret| report.include?(secret) }

      expect(status).not_to be_success
      expect(matches).to eq(0)
      expect(report).to include('[REDACTED]')
    end
  end

  it 'preserves typed error category and metadata while redacting its message' do
    world.record do
      raise Volcano::Error::ValidationError.new(
        "invalid #{credentials.fetch('anon_key')}",
        status: 422,
        code: 'invalid_contract'
      )
    end

    outcome = world.last_outcome
    expect(outcome.category).to eq('validation error')
    expect(outcome.error).to be_a(Volcano::Error::ValidationError)
    expect(outcome.error.message).to eq('invalid [REDACTED]')
    expect(outcome.error.status).to eq(422)
    expect(outcome.error.code).to eq('invalid_contract')
  end

  it 'redacts fixture credentials from cleanup exceptions and their failures' do
    realtime = Object.new
    secret_values = credentials.values
    realtime.define_singleton_method(:disconnect) do
      raise "cleanup failed: #{secret_values.join(' ')}"
    end
    world.realtime_clients << Struct.new(:realtime).new(realtime)

    expect { world.cleanup }.to raise_error(VolcanoContract::CleanupError) { |error|
      messages = [error.message, *error.failures.map(&:message)]
      expect(error.cause).to be_nil
      expect(messages.join(' ')).to include('cleanup failed:')
      credentials.each_value do |secret|
        messages.each { |message| expect(message).not_to include(secret) }
      end
    }
  end
end
