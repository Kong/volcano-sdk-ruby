# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require_relative '../../features/support/contract_world'
require 'socket'
require 'tmpdir'

RSpec.describe VolcanoContract::World do
  def with_rate_limit_server(message, request_count: 1)
    server, server_thread = start_rate_limit_server(message, request_count)

    yield "http://127.0.0.1:#{server.local_address.ip_port}"
  ensure
    server&.close
    server_thread&.join(2)
  end

  def start_rate_limit_server(message, request_count)
    server = TCPServer.new('127.0.0.1', 0)
    response_body = JSON.generate(error: message, code: 'contract_rate_limit')
    server_thread = Thread.new do
      request_count.times { serve_rate_limit_response(server, response_body) }
    rescue IOError, SystemCallError
      nil
    end
    server_thread.report_on_exception = false
    [server, server_thread]
  end

  def serve_rate_limit_response(server, response_body)
    socket = server.accept
    content_length = 0
    while (line = socket.gets)
      break if line == "\r\n"

      content_length = line.split(':', 2).last.to_i if line.match?(/\Acontent-length:/i)
    end
    socket.read(content_length) if content_length.positive?
    socket.write(rate_limit_http_response(response_body))
  ensure
    socket&.close
  end

  def rate_limit_http_response(response_body)
    "HTTP/1.1 429 Too Many Requests\r\n" \
      "Connection: close\r\n" \
      "Content-Type: application/json\r\n" \
      "Retry-After: 17\r\n" \
      "Content-Length: #{response_body.bytesize}\r\n\r\n" \
      "#{response_body}"
  end

  def complete_fixture(api_url, credential_values)
    {
      'api_url' => api_url,
      'anon_key' => credential_values.fetch('anon_key'),
      'service_key' => credential_values.fetch('service_key'),
      'user_email' => 'user@example.com',
      'user_password' => credential_values.fetch('user_password'),
      'user_id' => 'user-id',
      'database_name' => 'main',
      'table_name' => 'items',
      'fixture_row' => { 'slug' => 'fixture' },
      'bucket_name' => 'assets',
      'storage_path' => 'contract.txt',
      'realtime_channel' => 'contract',
      'lock_key' => 'contract-lock'
    }
  end

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
  let(:binding_credentials) do
    {
      'anon_key' => 'anon fixture/secret',
      'service_key' => 'service fixture/secret',
      'user_password' => 'password fixture/secret'
    }
  end
  let(:binding_credential_leaks) do
    [
      *binding_credentials.values,
      'anon+fixture%2Fsecret',
      'service+fixture%2Fsecret',
      'password+fixture%2Fsecret',
      'anon%20fixture%2Fsecret',
      'service%20fixture%2Fsecret',
      'password%20fixture%2Fsecret'
    ]
  end

  def rate_limit_message
    "rate limit while signing in #{binding_credential_leaks.join(' ')}"
  end

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

  it 'redacts direct authentication failures without losing typed metadata', :aggregate_failures do
    with_rate_limit_server(rate_limit_message) do |api_url|
      contract_world = described_class.new(complete_fixture(api_url, binding_credentials))

      expect { contract_world.authenticate }.to raise_error(Volcano::Error::RateLimitedError) { |error|
        expect(VolcanoContract.classify_error(error)).to eq('rate limited')
        expect(error.status).to eq(429)
        expect(error.code).to eq('contract_rate_limit')
        expect(error.retry_after).to eq(17)
        expect(error.message).to include('rate limit while signing in')
        expect(binding_credential_leaks.count { |value| error.full_message.include?(value) }).to eq(0)
        expect(error.cause).to be_nil
      }
    end
  end

  it 'redacts credentials from the actual authenticated-client Cucumber binding' do
    Dir.mktmpdir('volcano-ruby-cucumber-binding') do |directory|
      fixture_path = File.join(directory, 'fixture.json')
      report_directory = File.join(directory, 'reports')
      with_rate_limit_server(rate_limit_message, request_count: 2) do |api_url|
        File.write(fixture_path, JSON.generate(complete_fixture(api_url, binding_credentials)))
        File.chmod(0o600, fixture_path)
        _stdout, _stderr, status = Open3.capture3(
          {
            'CUCUMBER_PUBLISH_QUIET' => 'true',
            'VOLCANO_SDK_CONTRACT_FIXTURE' => fixture_path
          },
          'bundle', 'exec', 'cucumber',
          'features/contract/database.feature', 'features/contract/realtime.feature',
          '--format', 'junit', '--out', report_directory,
          chdir: File.expand_path('../..', __dir__)
        )
        report = Dir.glob(File.join(report_directory, '**/*')).select { |path| File.file?(path) }
                    .map { |path| File.binread(path) }.join

        expect(status).not_to be_success
        expect(report).to include('rate limit while signing in', 'Volcano::Error::RateLimitedError')
        expect(report.scan('Volcano::Error::RateLimitedError').length).to eq(2)
        expect(report).not_to include('LocalJumpError')
        expect(binding_credential_leaks.count { |value| report.include?(value) }).to eq(0)
      end
    end
  end
end
