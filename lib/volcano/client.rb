# frozen_string_literal: true

module Volcano
  # Entry point for Volcano API, storage, lock, and realtime operations.
  class Client
    attr_reader :auth, :storage, :locks, :realtime, :current_session

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
      @current_session = nil
      @transport = transport || GeneratedTransport.new(api_url: @api_url, timeout: timeout)
      initialize_facades(socket_factory)
    end

    def database(name)
      Database.new(self, @transport, name)
    end

    def anon_token
      @anon_key
    end

    def session_token
      raise Error::AuthenticationError, 'No active session' unless @current_session

      @current_session.access_token
    end

    def service_token
      raise Error::AuthenticationError, 'No service key configured' unless @service_key

      @service_key
    end

    def store_session(session)
      @current_session = session
    end

    private

    def extract_adapters(adapters)
      transport = adapters.delete(:_transport)
      socket_factory = adapters.delete(:_realtime_socket_factory)
      raise ArgumentError, "unknown keyword: #{adapters.keys.first}" unless adapters.empty?

      [transport, socket_factory]
    end

    def initialize_facades(socket_factory)
      @auth = Auth.new(self, @transport)
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
