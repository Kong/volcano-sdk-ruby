# frozen_string_literal: true

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
      validate_invocation(name, payload)
      authorization = @client.function_token
      resolution = resolve(authorization, name)
      response = Transport.invoke { invoke_resolved(authorization, resolution, payload.dup) }
      if stale_mapping?(response)
        # The function was deleted and recreated, so the cached identity no
        # longer exists. Resolve again before giving up.
        FunctionResolution.forget(@api_url, authorization, name)
        resolution = resolve(authorization, name)
        response = Transport.invoke { invoke_resolved(authorization, resolution, payload.dup) }
      end
      function_response(response)
    end

    private

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
      FunctionResolution.store_missing(@api_url, authorization, name) if resolved.status == 404
      payload = Transport.body(resolved, 200)
      resolution = resolved_resolution(payload)
      FunctionResolution.store(@api_url, authorization, name, resolution, cache_ttl(payload))
      resolution
    end

    def cached_resolution(cached)
      return cached.resolution if cached.resolution

      raise Error::NotFoundError.new('Function was not found', status: 404)
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
      FunctionResolution::Resolution.new(
        function_id: function_id,
        invoke_url: FunctionResolution.valid_invoke_url(payload['invoke_url'], @api_url)
      )
    end

    def cache_ttl(payload)
      ttl = payload['cache_ttl_seconds'] if payload.is_a?(Hash)
      raise TypeError, 'Expected a complete function response' unless ttl.is_a?(Integer) && ttl.positive?

      ttl
    end

    def function_response(response)
      version = header(response.headers, 'X-Volcano-Version')
      Transport.body(response, 200) unless response.status.between?(200, 299) || version

      FunctionResponse.new(
        data: response.body, status: response.status,
        headers: response.headers || {}, version: version
      )
    end

    def header(headers, name)
      headers&.find { |key, _| key.casecmp?(name) }&.last
    end
  end
end
