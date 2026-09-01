# frozen_string_literal: true

module Volcano
  # Entry point for Volcano API, storage, lock, and realtime operations.
  class Client
    attr_reader :auth, :storage, :locks, :realtime

    def initialize(
      anon_key:,
      api_url: 'https://api.volcano.dev',
      service_key: nil,
      timeout: 60,
      **adapters
    )
      transport, socket_factory = extract_adapters(adapters)
      @api_url = api_url.delete_suffix('/')
      @anon_key = anon_key
      @service_key = service_key
      @auth_state = AuthState.new
      @transport = transport || GeneratedTransport.new(api_url: @api_url, timeout: timeout)
      initialize_facades(socket_factory)
    end

    def database(name)
      Database.new(self, @transport, name)
    end

    def anon_token
      @anon_key
    end

    def current_session
      @auth_state.current
    end

    def session_token
      session = current_session
      raise Error::AuthenticationError, 'No active session' unless session

      session.access_token
    end

    def service_token
      raise Error::AuthenticationError, 'No service key configured' unless @service_key

      @service_key
    end

    def store_session(session, event: :signed_in)
      @auth_state.store(session, event: event)
    end

    def capture_session
      @auth_state.capture
    end

    def store_session_if_current?(session, generation, event: :signed_in)
      @auth_state.store_if_current?(session, generation, event: event)
    end

    def clear_session_if_current?(generation, event: :signed_out)
      @auth_state.clear_if_current?(generation, event: event)
    end

    def subscribe_auth_state_change(...)
      @auth_state.subscribe(...)
    end

    private

    def extract_adapters(adapters)
      transport = adapters.delete(:_transport)
      socket_factory = adapters.delete(:_realtime_socket_factory)
      raise ArgumentError, "unknown keyword: #{adapters.keys.first}" unless adapters.empty?

      [transport, socket_factory]
    end

    def initialize_facades(socket_factory)
      @auth = Auth.new(self, @transport, api_url: @api_url)
      @storage = Storage.new(self, @transport)
      @locks = Locks.new(self, @transport)
      @realtime = Realtime.new(
        self,
        api_url: @api_url,
        socket_factory: socket_factory
      )
    end
  end
end
