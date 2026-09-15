# frozen_string_literal: true

module VolcanoContract
  class DurableExecutions
    # A durable execution is started asynchronously and observed through a
    # status read, so it settles in seconds. Bounded, so a scenario reports a
    # timeout instead of hanging the lane.
    POLL_INTERVAL_SECONDS = 5
    POLL_TIMEOUT_SECONDS = 300

    # The platform token is not an auth session: it cannot be refreshed and
    # belongs to no auth user. The SDK carries a credential as a session and
    # requires a complete one, so the rest of the owner's session is filler.
    OWNER_SESSION_PLACEHOLDER = 'sdk-contract-platform-token-has-no-auth-session'

    attr_reader :execution_name, :payload, :started

    def initialize(world)
      @world = world
      @fixture = world.fixture
      @function_name = @fixture.fetch('durable_function_name')
      @execution_name = "#{@function_name}-#{world.suffix}"
      @payload = { 'value' => "volcano-sdk-contract-#{world.suffix}" }.freeze
      @started = nil
    end

    def start
      @started = @world.service_client.durable.start(
        @function_name, payload, execution_name: execution_name
      )
    end

    # Polls an execution to a terminal status. That read is also what reconciles
    # the stored status against the platform's, so it is the path a client
    # waiting for a result takes.
    def follow(execution_id)
      deadline = monotonic_now + POLL_TIMEOUT_SECONDS
      loop do
        execution = owner_client.durable.get(project_id, @function_name, execution_id)
        return execution if execution.terminal?

        if monotonic_now >= deadline
          raise "durable execution #{execution_id} was still #{execution.status} " \
                "after #{POLL_TIMEOUT_SECONDS}s"
        end

        sleep POLL_INTERVAL_SECONDS
      end
    end

    def list
      owner_client.durable.list(project_id, @function_name)
    end

    private

    def project_id = @fixture.fetch('project_id')

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Reading and listing are owner-scoped, so they need a client whose session
    # carries the project's own token; neither application key reaches them.
    def owner_client
      @owner_client ||= Volcano::Client.new(
        api_url: @fixture.fetch('api_url'), anon_key: @fixture.fetch('anon_key')
      ).tap do |client|
        client.auth.current_session = Volcano::Session.new(
          access_token: @fixture.fetch('platform_token'),
          refresh_token: OWNER_SESSION_PLACEHOLDER,
          user_id: OWNER_SESSION_PLACEHOLDER
        )
      end
    end
  end
end
