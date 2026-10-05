# frozen_string_literal: true

require 'spec_helper'
require 'support/session_fixtures'

RSpec.describe Volcano::Sandboxes do
  include SessionFixtures

  def project = '00000000-0000-4000-8000-000000000001'
  def session_id = '00000000-0000-4000-8000-000000000002'
  def subject_id = '00000000-0000-4000-8000-000000000003'
  def request_id = '00000000-0000-4000-8000-000000000004'
  let(:client) { Volcano::Client.new(anon_key: 'anon', service_key: 'service', api_url: 'https://sandbox.test', timeout: 5) }
  let(:facade) { client.sandboxes }
  let(:requests) { [] }
  let(:command) do
    { stdout: 'hello', stderr: 'err', exit_code: 7,
      timed_out: false, stdout_truncated: false, stderr_truncated: true }
  end

  def state(value = 'running')
    { id: session_id, project_id: project, region: 'aws-us-east-1', state: value, expires_at: '2026-10-06T10:00:00Z' }
  end

  def reply(payload = nil, status: 200)
    response = Typhoeus::Response.new(code: status, body: JSON.generate(payload),
                                      headers: { 'Content-Type' => 'application/json' })
    Typhoeus.stub(%r{\Ahttps://sandbox.test}).and_return do |request|
      requests << request
      response
    end
  end

  def mutated_command_response(request, input, environment, responses)
    requests << request
    input.replace('changed')
    environment['KEY'].replace('changed')
    responses.shift
  end

  after { Typhoeus::Expectation.clear }

  it 'creates a named session without overriding its configured memory' do
    reply(state, status: 201)
    handle = facade.create(project, region: 'aws-us-east-1', sandbox_id: subject_id, request_id: request_id)
    expect(handle.id).to eq(session_id)
    expect(handle.project_id).to eq(project)
    expect(handle.region).to eq('aws-us-east-1')
    expect(handle.expires_at).to eq(Time.utc(2026, 10, 6, 10))
  end

  it 'returns nonzero command exits as one-shot data' do
    reply(command.merge(session_id: session_id, region: 'aws-us-east-1', duration_ms: 42))
    result = facade.exec(project, 'exit 7', region: 'aws-us-east-1', preset: 'python3.12')
    expect(result.exit_code).to eq(7)
    expect(result.duration_ms).to eq(42)
    expect(result.stderr_truncated).to be(true)
  end

  it 'executes in a session with a caller retry identity' do
    reply(state)
    handle = facade.get(session_id)
    reply(command)
    expect(handle.exec('exit 7', timeout_seconds: 3600, request_id: request_id).stdout).to eq('hello')
  end

  { refresh: ['running', 200], suspend: ['suspending', 202], resume: ['resuming', 202],
    terminate: ['terminating', 202] }.each do |operation, (value, status)|
    it "updates observed state after #{operation}" do
      reply(state)
      handle = facade.get(session_id)
      reply(state(value), status: status)
      expect(handle.public_send(operation)).to be(handle)
      expect(handle.state).to eq(value)
    end
  end

  it 'preserves arbitrary bytes through guest files' do
    reply(state)
    handle = facade.get(session_id)
    bytes = (0..255).to_a.pack('C*')
    reply(nil, status: 204)
    expect(handle.files.write('/workspace/data', bytes)).to be_nil
    reply({ data: Base64.strict_encode64(bytes) })
    expect(handle.files.read('/workspace/data')).to eq(bytes)
  end

  it 'refuses oversized files before dispatch' do
    reply(state)
    handle = facade.get(session_id)
    expect { handle.files.write('/workspace/data', 'x' * ((8 * 1024 * 1024) + 1)) }
      .to raise_error(Volcano::Error::ValidationError)
  end

  it 'redacts expiring access credentials from inspection' do
    reply(state)
    handle = facade.get(session_id)
    reply({ url: 'https://access.test', token: 'secret', expires_at: '2026-10-06T10:00:00Z' })
    access = handle.access(8080)
    expect(access.token).to eq('secret')
    expect(access.url).to eq('https://access.test')
    expect(access.expires_at).to eq(Time.utc(2026, 10, 6, 10))
    expect(access.inspect).not_to include('secret')
  end

  it 'grants and revokes session access for a backend-selected user' do
    reply(nil, status: 204)
    expect(facade.grant(session_id, subject_id, expires_at: '2026-10-06T10:00:00Z')).to be_nil
    expect(facade.revoke(session_id, subject_id)).to be_nil
  end

  it 'lists typed presets' do
    reply({ data: [{ id: 'python3.12', memory_mb: 2048, regions: ['aws-us-east-1'] }] })
    expect(facade.presets.first).to eq(Volcano::SandboxPreset.new(id: 'python3.12', memory_mb: 2048,
                                                                  regions: ['aws-us-east-1']))
  end

  it 'lists public presets without service or user credentials' do
    anonymous = Volcano::Client.new(anon_key: 'anon', api_url: 'https://sandbox.test')
    reply({ data: [] })
    expect(anonymous.sandboxes.presets).to eq([])
    expect(requests.last.options[:headers]).not_to have_key('Authorization')
  end

  [{}, { preset: 'python3.12', sandbox_id: 'invalid' }, { sandbox_id: 'invalid' }].each do |options|
    it "refuses an invalid selector #{options}" do
      expect { facade.create(project, region: 'aws-us-east-1', **options) }.to raise_error(Volcano::Error::ValidationError)
    end
  end

  it 'does not use anonymous credentials' do
    anonymous = Volcano::Client.new(anon_key: 'anon')
    expect { anonymous.sandboxes.get(session_id) }.to raise_error(Volcano::Error::AuthenticationError)
  end

  it 'preserves structured conflict errors' do
    reply({ error: 'denied', code: 'sandbox_denied' }, status: 409)
    expect { facade.get(session_id) }.to raise_error(Volcano::Error::ConflictError) { |error| expect(error.code).to eq('sandbox_denied') }
  end

  it 'requests termination when a block raises' do
    reply(state)
    handle = facade.get(session_id)
    reply(state('terminating'), status: 202)
    expect { handle.use { raise ArgumentError, 'body failed' } }.to raise_error(ArgumentError, 'body failed')
    expect(handle.state).to eq('terminating')
  end

  it 'does not terminate an already terminated session' do
    reply(state('terminated'))
    handle = facade.get(session_id)
    expect(handle.use(&:id)).to eq(session_id)
  end

  it 'refuses mismatched identity without mutating the handle' do
    reply(state)
    handle = facade.get(session_id)
    reply(state('terminated').merge(id: subject_id))
    expect { handle.refresh }.to raise_error(TypeError, 'Sandbox session identity changed')
    expect(handle.state).to eq('running')
  end

  [{ stdout: 1 }, { exit_code: true }, { timed_out: 'false' }].each do |invalid|
    it "refuses invalid command output #{invalid}" do
      reply(command.merge(session_id: session_id, region: 'aws-us-east-1', duration_ms: 42).merge(invalid))
      expect { facade.exec(project, 'run', region: 'aws-us-east-1', preset: 'python3.12') }.to raise_error(TypeError)
    end
  end

  it 'refuses an unknown session state' do
    reply(state('invalid'))
    expect { facade.get(session_id) }.to raise_error(TypeError)
  end

  it 'refuses a malformed catalog' do
    reply({ data: {} })
    expect { facade.presets }.to raise_error(TypeError)
  end

  it 'uses the active session credential instead of the service key' do
    session = Volcano::Session.new(access_token: 'user-access', refresh_token: 'refresh', user_id: subject_id)
    client.auth.current_session = session
    reply(state)
    facade.get(session_id)
    expect(requests.last.options[:headers]['Authorization']).to eq('Bearer user-access')
  end

  it 'preserves caller request identities and omits named memory overrides on the wire' do
    reply(state, status: 201)
    2.times { facade.create(project, region: 'aws-us-east-1', sandbox_id: subject_id, request_id: request_id) }
    expect(requests.map { |request| request.options[:headers][:'Idempotency-Key'] }).to eq([request_id, request_id])
    expect(JSON.parse(requests.last.options[:body])).to eq('region' => 'aws-us-east-1', 'sandbox_id' => subject_id)
    expect(requests.last.options[:headers]['Authorization']).to eq('Bearer service')
  end

  it 'extends the HTTP timeout to include command completion' do
    reply(state)
    handle = facade.get(session_id)
    reply(command)
    handle.exec('run', timeout_seconds: 3600)
    expect(requests.last.options[:timeout]).to eq(3_720_000)
  end

  [nil, 3600].each do |timeout|
    it "extends the one-shot HTTP timeout for #{timeout || 'default'} command completion" do
      reply(command.merge(session_id: session_id, region: 'aws-us-east-1', duration_ms: 42))
      options = { region: 'aws-us-east-1', preset: 'python3.12' }
      options[:timeout_seconds] = timeout if timeout
      facade.exec(project, 'run', **options)
      expect(requests.last.options[:timeout]).to eq(((timeout || 60) + 120) * 1000)
    end
  end

  it 'preserves the configured timeout for short requests' do
    reply({ data: [] })
    facade.presets
    reply(state)
    handle = facade.get(session_id)
    reply(state('suspending'), status: 202)
    handle.suspend
    reply({ url: 'https://access.test', token: 'secret', expires_at: '2026-10-06T10:00:00Z' })
    handle.access(8080)
    reply({ data: 'aGVsbG8=' })
    handle.files.read('/workspace/file')
    expect(requests.map { |request| request.options[:timeout] }).to all(eq(5000))
  end

  it 'owns frozen session and project identifiers' do
    reply(state)
    handle = facade.get(session_id)
    expect { handle.id.replace(subject_id) }.to raise_error(FrozenError)
    expect { handle.project_id.replace(subject_id) }.to raise_error(FrozenError)
    reply(command)
    handle.exec('run')
    expect(requests.last.url).to end_with("/sandbox-sessions/#{session_id}/exec")
  end

  it 'does not replay a command after a lost transport response' do
    failure = Typhoeus::Response.new(code: 0, return_code: :operation_timedout)
    Typhoeus.stub(%r{\Ahttps://sandbox.test}).and_return(failure)
    expect { facade.exec(project, 'run', region: 'aws-us-east-1', preset: 'python3.12') }
      .to raise_error(Volcano::Error::TransportError)
  end

  it 'keeps service credentials for management after signing in' do
    client.auth.current_session = Volcano::Session.new(access_token: 'user', refresh_token: 'refresh',
                                                       user_id: subject_id)
    reply(state, status: 201)
    handle = facade.create(project, region: 'aws-us-east-1', preset: 'python3.12')
    %i[suspend resume terminate].each do |operation|
      reply(state, status: 202)
      handle.public_send(operation)
    end
    reply(nil, status: 204)
    facade.grant(session_id, subject_id, expires_at: '2026-10-06T10:00:00Z')
    facade.revoke(session_id, subject_id)
    reply(command.merge(session_id: session_id, region: 'aws-us-east-1', duration_ms: 1))
    facade.exec(project, 'run', region: 'aws-us-east-1', preset: 'python3.12')
    expect(requests.map { |request| request.options[:headers]['Authorization'] }).to all(eq('Bearer service'))
  end

  it 'refreshes a rejected user credential once while preserving the command identity' do
    client.auth.current_session = Volcano::Session.new(access_token: access_token, refresh_token: 'refresh',
                                                       user_id: subject_id)
    reply(state)
    handle = facade.get(session_id)
    input = +'run'
    environment = { 'KEY' => +'original' }
    responses = [
      Typhoeus::Response.new(code: 401, body: '{}', headers: {}),
      Typhoeus::Response.new(code: 200, headers: {},
                             body: JSON.generate(access_token: access_token('new'),
                                                 refresh_token: 'new-refresh', token_type: 'bearer', expires_in: 3600,
                                                 user: { id: subject_id, email: 'u@example.com', status: 'active' })),
      Typhoeus::Response.new(code: 200, headers: {}, body: JSON.generate(command))
    ]
    Typhoeus.stub(%r{\Ahttps://sandbox.test}).and_return do |request|
      mutated_command_response(request, input, environment, responses)
    end
    expect(handle.exec(input, request_id: request_id, environment: environment).stdout).to eq('hello')
    expect(responses).to be_empty
    expect([requests[-3], requests.last].map { |request| request.options[:headers][:'Idempotency-Key'] })
      .to eq([request_id, request_id])
    expect(requests.last.options[:headers]['Authorization']).to eq("Bearer #{access_token('new')}")
    expect([requests[-3], requests.last].map { |request| JSON.parse(request.options[:body]) })
      .to all(eq('command' => 'run', 'environment' => { 'KEY' => 'original' }, 'timeout_seconds' => 60))
  end

  it 'preserves a block error when termination also fails' do
    reply(state)
    handle = facade.get(session_id)
    reply({ error: 'cleanup failed' }, status: 500)
    expect { handle.use { raise ArgumentError, 'body failed' } }.to raise_error(ArgumentError, 'body failed')
    expect(requests.last.url).to end_with("/sandbox-sessions/#{session_id}")
    expect(requests.last.options[:method]).to eq(:delete)
  end

  it 'reports termination errors when the block succeeds' do
    reply(state)
    handle = facade.get(session_id)
    reply({ error: 'cleanup failed' }, status: 500)
    expect { handle.use(&:id) }.to raise_error(Volcano::Error::VolcanoError)
  end

  it 'keeps user credentials for all granted session operations' do
    client.auth.current_session = Volcano::Session.new(access_token: 'user', refresh_token: 'refresh',
                                                       user_id: subject_id)
    reply(state)
    handle = facade.get(session_id)
    reply(command)
    handle.exec('run')
    reply(nil, status: 204)
    handle.files.write('/workspace/file', 'hello')
    reply({ data: 'aGVsbG8=' })
    expect(handle.files.read('/workspace/file')).to eq('hello')
    reply({ url: 'https://access.test', token: 'secret', expires_at: '2026-10-06T10:00:00Z' })
    handle.access(8080)
    expect(requests.map { |request| request.options[:headers]['Authorization'] }).to all(eq('Bearer user'))
  end

  it 'rejects misspelled creation and execution keywords' do
    expect { facade.create(project, region: 'us-east-1', preset: 'python3.12', max_duration: 60) }
      .to raise_error(ArgumentError, /unknown keyword/)
    expect { facade.exec(project, 'run', region: 'us-east-1', preset: 'python3.12', timeout: 5) }
      .to raise_error(ArgumentError, /unknown keyword/)
    reply(state)
    handle = facade.get(session_id)
    expect { handle.exec('run', timeout: 5) }.to raise_error(ArgumentError, /unknown keyword/)
  end

  it 'reports cleanup failure even inside an outer rescue' do
    reply(state)
    handle = facade.get(session_id)
    reply({ error: 'cleanup failed' }, status: 500)
    begin
      raise ArgumentError, 'outer error'
    rescue ArgumentError
      expect { handle.use(&:id) }.to raise_error(Volcano::Error::ServerError)
    end
  end

  it 'does not terminate an already terminating session' do
    reply(state('terminating'))
    handle = facade.get(session_id)
    expect(handle.use(&:id)).to eq(session_id)
    expect(requests.length).to eq(1)
  end

  it 'treats cleanup of an expired session as success' do
    reply(state)
    handle = facade.get(session_id)
    reply({ error: 'gone' }, status: 404)
    expect(handle.use(&:id)).to eq(session_id)
  end

  it 'formats Time grants as UTC ISO8601 without mutating the argument' do
    expiry = Time.new(2026, 10, 6, 12, 0, 0, '+02:00')
    reply(nil, status: 204)
    facade.grant(session_id, subject_id, expires_at: expiry)
    expect(JSON.parse(requests.last.options[:body])).to eq('expires_at' => '2026-10-06T10:00:00Z')
    expect(expiry.utc_offset).to eq(7200)
  end

  it 'rejects invalid grant timestamps before sending a request' do
    expect { facade.grant(session_id, subject_id, expires_at: 'tomorrow') }
      .to raise_error(Volcano::Error::ValidationError)
    expect(requests).to be_empty
  end

  it 'redacts all Sandbox facade and handle inspection' do
    client.auth.current_session = Volcano::Session.new(access_token: 'user-secret', refresh_token: 'refresh-secret',
                                                       user_id: subject_id)
    reply(state)
    handle = facade.get(session_id)
    [facade, handle, handle.files].each do |value|
      expect(value.inspect).not_to match(/service|user-secret|refresh-secret|@requests|@client/)
    end
  end

  it 'keeps service credentials on handles returned by create' do
    reply(state, status: 201)
    handle = facade.create(project, region: 'us-east-1', preset: 'python3.12')
    client.auth.current_session = Volcano::Session.new(access_token: 'user-secret', refresh_token: 'refresh-secret',
                                                       user_id: subject_id)
    reply(state)
    handle.refresh
    reply(command)
    handle.exec('run')
    reply({ data: 'aGVsbG8=' })
    handle.files.read('/workspace/file')
    reply({ url: 'https://access.test', token: 'secret', expires_at: '2026-10-06T10:00:00Z' })
    handle.access(8080)
    expect(requests.map { |request| request.options[:headers]['Authorization'] }).to all(eq('Bearer service'))
  end

  it 'does not refresh a valid user denied by a missing grant' do
    client.auth.current_session = Volcano::Session.new(access_token: access_token, refresh_token: 'refresh',
                                                       user_id: subject_id)
    reply({ error: 'denied' }, status: 403)
    expect { facade.get(session_id) }.to raise_error(Volcano::Error::AuthenticationError)
    expect(requests.length).to eq(1)
  end

  it 'refuses malformed response timestamps without changing the observed state' do
    reply(state)
    handle = facade.get(session_id)
    reply(state('terminated').merge(expires_at: 'tomorrow'))
    expect { handle.refresh }.to raise_error(TypeError, 'Invalid Sandbox timestamp')
    expect(handle.state).to eq('running')
  end

  it 'preserves non-StandardError block failures during cleanup' do
    reply(state)
    handle = facade.get(session_id)
    reply({ error: 'cleanup failed' }, status: 500)
    expect { handle.use { raise Interrupt, 'cancelled' } }.to raise_error(Interrupt, 'cancelled')
  end
end
