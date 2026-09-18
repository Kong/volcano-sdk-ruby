# frozen_string_literal: true

require_relative 'function_auth'

module Volcano
  # Invokes deployed Volcano functions by name.
  class Functions
    FUNCTION_NAME = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
    private_constant :FUNCTION_NAME

    # Present only once the platform has dispatched to the function.
    FUNCTION_INVOKED_HEADER = 'X-Volcano-Function-Invoked'
    private_constant :FUNCTION_INVOKED_HEADER

    def initialize(client, transport, api_url:)
      @client = client
      @transport = transport
      @api_url = api_url
    end

    def invoke(name, payload = {})
      auth = FunctionAuth.new(@client)
      validate_invocation(name, payload)
      invoke_owned(auth, name.dup.freeze, ImmutableQueryValue.capture(payload))
    end

    private

    def invoke_owned(auth, name, payload)
      authorization, resolution = auth.run { |token| [token, resolve(token, name)] }
      response = authenticated_invoke(auth, resolution, payload)
      if stale_mapping?(response)
        FunctionResolution.forget(@api_url, authorization, name)
        resolution = auth.run { |token| resolve(token, name) }
        response = authenticated_invoke(auth, resolution, payload)
      end
      function_response(response)
    end

    def authenticated_invoke(auth, resolution, payload)
      auth.run do |token|
        response = Transport.invoke { invoke_resolved(token, resolution, payload) }
        if response.status == 401 && header(response.headers, FUNCTION_INVOKED_HEADER).nil?
          Transport.body(response, 200)
        end
        response
      end
    end

    # A platform 404 means the cached function identity is gone. A function that
    # answers 404 itself must be returned rather than retried: invoking twice
    # would run the caller's side effects twice. The platform sets
    # X-Volcano-Function-Invoked only after dispatch, so its absence is what
    # separates the two. X-Volcano-Version cannot: the server stamps it on every
    # response, including errors raised before the function is reached.
    def stale_mapping?(response)
      response.status == 404 && header(response.headers, FUNCTION_INVOKED_HEADER).nil?
    end

    def invoke_resolved(authorization, resolution, payload)
      if resolution.invoke_url.nil?
        @transport.invoke_function(
          authorization: authorization, function_id: resolution.function_id, payload: payload
        )
      else
        @transport.invoke_function_url(
          authorization: authorization, invoke_url: resolution.invoke_url, payload: payload
        )
      end
    end

    # Returns the function's identity, reusing a live cached resolution.
    def resolve(authorization, name)
      cached = FunctionResolution.lookup(@api_url, authorization, name)
      return cached_resolution(cached) if cached

      # Hold the name's lock across the round trip so concurrent callers wait
      # for one resolve instead of each opening their own.
      FunctionResolution.resolve_lock(@api_url, authorization, name).synchronize do
        cached = FunctionResolution.lookup(@api_url, authorization, name)
        next cached_resolution(cached) if cached

        resolve_uncached(authorization, name)
      end
    end

    def resolve_uncached(authorization, name)
      resolved = Transport.invoke do
        @transport.resolve_function_for_invocation(authorization: authorization, name: name)
      end
      payload = Transport.body(resolved, 200)
      resolution = resolved_resolution(payload)
      FunctionResolution.store(@api_url, authorization, name, resolution, cache_ttl(payload))
      resolution
    rescue Error::NotFoundError => e
      FunctionResolution.store_missing(@api_url, authorization, name, e)
      raise
    end

    def cached_resolution(cached)
      cached.resolution || raise(cached.failure.exception)
    end

    def validate_invocation(name, payload)
      unless name.is_a?(String) && FUNCTION_NAME.match?(name)
        raise ArgumentError,
              'Function name must be DNS-safe: lowercase letters, numbers, and hyphens; 1-63 characters'
      end
      raise TypeError, 'Function payload must be a Hash' unless payload.is_a?(Hash)
    end

    def resolved_resolution(payload)
      function_id = payload['function_id'] if payload.is_a?(Hash)
      raise TypeError, 'Expected a complete function response' unless function_id.is_a?(String) && !function_id.empty?

      # Absent when the deployment serves no public invocation domain, as in
      # local development; the function is reached through the API instead.
      invoke_url = FunctionResolution.valid_invoke_url(payload['invoke_url'], @api_url)
      FunctionResolution::Resolution.new(function_id: function_id, invoke_url: invoke_url)
    end

    def cache_ttl(payload)
      ttl = payload['cache_ttl_seconds'] if payload.is_a?(Hash)
      raise TypeError, 'Expected a complete function response' unless ttl.is_a?(Integer) && ttl.positive?

      ttl
    end

    # A non-2xx the platform produced never reached the function, so it raises
    # rather than being returned as the function's answer. That turns on the
    # dispatch marker, not on the version stamp, which every response carries —
    # keying on the stamp would hand back every platform failure as a reply.
    def function_response(response)
      version = header(response.headers, 'X-Volcano-Version')
      dispatched = !header(response.headers, FUNCTION_INVOKED_HEADER).nil?
      Transport.body(response, 200) unless response.status.between?(200, 299) || dispatched

      FunctionResponse.new(
        data: response.body, status: response.status,
        headers: response.headers || {}, version: version
      )
    end

    def header(headers, name) = headers&.find { |key, _| key.casecmp?(name) }&.last
  end
end
