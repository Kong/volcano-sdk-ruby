# frozen_string_literal: true

require 'stringio'
require 'timeout'
require_relative '../../spec/support/recording_server'

# Executes the unchanged public example with the isolated gem selected by smoke-gem.sh.
class PackageQuickstart
  USER = {
    id: '22222222-2222-4222-8222-222222222222',
    project_id: '11111111-1111-4111-8111-111111111111',
    email: 'quickstart@example.test', email_confirmed: true, status: 'active'
  }.freeze
  SESSION = {
    access_token: 'synthetic-access', refresh_token: 'synthetic-refresh',
    token_type: 'bearer', expires_in: 3600, user: USER
  }.freeze

  def run
    server = RecordingServer.new { |path| response(path) }
    configure(server.url)
    execute
    verify_requests(server.requests)
  ensure
    server&.close
  end

  private

  def response(path)
    case path
    when '/auth/signin' then [200, SESSION]
    when '/auth/user' then [200, { user: USER }]
    when '/auth/logout' then [204, nil]
    else [404, { error: 'Unexpected quickstart request' }]
    end
  end

  def configure(url)
    ENV.update(
      'VOLCANO_API_URL' => url,
      'VOLCANO_ANON_KEY' => 'synthetic-anon',
      'VOLCANO_USER_EMAIL' => USER.fetch(:email),
      'VOLCANO_USER_PASSWORD' => 'synthetic-password'
    )
  end

  def example
    document = File.read(File.expand_path('../../docs/README.md', __dir__))
    section = document.split("## Sign in and read a profile\n").fetch(1).split("\n## ").first
    examples = section.scan(/```ruby\n(.*?)\n```/m).flatten
    raise 'Expected one complete documented quickstart' unless examples.length == 1

    examples.first
  end

  def execute
    previous_stdout = $stdout
    File.write('quickstart.rb', example)
    output = StringIO.new
    $stdout = output
    Timeout.timeout(30) { load File.expand_path('quickstart.rb') }
    raise 'Unexpected quickstart output' unless output.string.strip == "Signed in as #{USER.fetch(:email)}"
  ensure
    $stdout = previous_stdout
  end

  def verify_requests(requests)
    actual = requests.map do |request|
      body = JSON.parse(request.body) if request.body
      [request.http_method, request.target, request.authorization, body]
    end
    raise 'Unexpected quickstart requests' unless actual == expected_requests
  end

  def expected_requests
    [
      ['POST', '/auth/signin', 'Bearer synthetic-anon',
       { 'email' => USER.fetch(:email), 'password' => 'synthetic-password' }],
      ['GET', '/auth/user', 'Bearer synthetic-access', nil],
      ['POST', '/auth/logout', 'Bearer synthetic-anon', { 'refresh_token' => 'synthetic-refresh' }]
    ]
  end
end

PackageQuickstart.new.run
