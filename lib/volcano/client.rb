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
      @session_mutex = Mutex.new
      @session_generation = 0
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

    def current_session
      capture_session.last
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

    def store_session(session)
      @session_mutex.synchronize do
        @current_session = session
        @session_generation += 1
      end
    end

    def capture_session
      @session_mutex.synchronize { [@session_generation, @current_session] }
    end

    def store_session_if_current(session, generation)
      @session_mutex.synchronize do
        next false unless generation == @session_generation

        @current_session = session
        @session_generation += 1
        true
      end
    end

    def clear_session_if_current(generation)
      @session_mutex.synchronize do
        next false unless generation == @session_generation

        @current_session = nil
        @session_generation += 1
        true
      end
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
