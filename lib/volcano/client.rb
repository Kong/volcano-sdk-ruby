# frozen_string_literal: true

module Volcano
  # Entry point for Volcano API, storage, lock, and realtime operations.
  class Client
    SessionToken = Data.define(:value)

    # Restricts database queries to the captured access token.
    class SessionToken
      # @dynamic value
      def session_token = value

      def session_request
        yield(value)
      end
    end
    private_constant :SessionToken

    attr_reader :sandboxes, :auth, :functions, :durable, :logs, :storage, :locks, :realtime

    # @dynamic auth, functions, durable, logs, storage, locks, realtime

    def initialize( # rubocop:disable Metrics/ParameterLists -- Preserve typed constructor keywords.
      anon_key:,
      api_url: 'https://api.volcano.dev',
      service_key: nil,
      timeout: 60,
      _transport: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.
      _realtime_socket_factory: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.
      _realtime_reconnect_delay: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.
      **options
    )
      session = SessionCredentials.build(options.delete(:access_token), options.delete(:refresh_token))
      raise ArgumentError, "unknown keyword: #{options.keys.first}" unless options.empty?

      @api_url = api_url.delete_suffix('/')
      @anon_key = anon_key
      @service_key = service_key
      @auth_state = AuthState.new(session: session)
      @transport = _transport || GeneratedTransport.new(api_url: @api_url, timeout: timeout)
      initialize_facades(_realtime_socket_factory, _realtime_reconnect_delay)
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

    def session_request(...)
      @auth.session_request(...)
    end

    alias session_read session_request

    def service_token
      service_key = @service_key
      raise Error::AuthenticationError, 'No service key configured' unless service_key

      service_key
    end

    def function_token
      current_session&.access_token || @service_key || @anon_key
    end

    def store_session(session, event: :signed_in)
      @auth_state.store(session, event: event)
    end

    def capture_session
      @auth_state.capture
    end

    def capture_session_binding
      @auth_state.capture_binding
    end

    def store_session_if_current?(session, generation, event: :signed_in, notifications: nil)
      @auth_state.store_if_current?(session, generation, event: event, notifications: notifications)
    end

    def clear_session_if_current?(generation, event: :signed_out, notifications: nil, lineage: nil)
      @auth_state.store_if_current?(nil, generation, event: event, notifications: notifications, lineage: lineage)
    end

    def reject_refresh_if_current?(...) = @auth_state.reject_refresh_if_current?(...)

    def refresh_rejected?(...) = @auth_state.refresh_rejected?(...)

    def subscribe_auth_state_change(...)
      @auth_state.subscribe(...)
    end

    def update_session_user_if_current?(...)
      @auth_state.update_user_if_current?(...)
    end

    private

    def database_with_token(name, token) # rubocop:disable Lint/UnusedPrivateMethod -- Typed cross-file private dispatch.
      Database.new(SessionToken.new(value: token), @transport, name)
    end

    def initialize_facades(socket_factory, reconnect_delay)
      @auth = Auth.new(self, @transport, api_url: @api_url)
      @functions = Functions.new(self, @transport, api_url: @api_url)
      @durable = Durable.new(self, @transport)
      @logs = Logs.new(self, @transport)
      @storage = Storage.new(self, @transport, api_url: @api_url, anon_key: @anon_key)
      @locks = Locks.new(self, @transport)
      @sandboxes = Sandboxes.new(self, @transport)
      @realtime = Realtime.new(
        self,
        api_url: @api_url,
        socket_factory: socket_factory,
        reconnect_delay: reconnect_delay
      )
    end
  end
end
