# frozen_string_literal: true

module Volcano
  # Starts and follows executions of deployed durable functions.
  class Durable
    # What the platform accepts as an execution name, and the page size it
    # serves at most. Mirrored from the wire contract so a refusal is the
    # facade's rather than the generated client's.
    EXECUTION_NAME = /\A[A-Za-z0-9._-]{1,255}\z/
    MAX_PAGE_SIZE = 100
    include DurableResponses

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    # Starts an execution and returns its handle. A durable function is never
    # invoked synchronously: it can outlive any request a caller could hold
    # open, so its result is read back with #get.
    #
    # Starting is the only durable operation an application credential may
    # perform, and it takes the token an invoke takes. Passing an
    # +execution_name+ makes the start idempotent: starting again under the
    # same name returns the execution that already exists rather than
    # beginning a second one.
    def start(function_name, payload = {}, execution_name: nil)
      # A durable function's id is accepted here as well as its name, so the
      # DNS-safe name pattern an invoke checks would reject half the input.
      function_id = identifier(function_name, 'function_name')
      name = execution_name.nil? ? nil : execution_name_argument(execution_name)
      response = Transport.invoke do
        @transport.start_durable_execution_from_application(
          authorization: @client.function_token,
          function_id: function_id, payload: payload.dup, execution_name: name
        )
      end
      durable_execution(Transport.body(response, 202))
    end

    # Reads an execution, including its result once it has succeeded.
    #
    # Owner-scoped: an execution is addressed by its id alone, so this takes
    # the project id and the project owner's platform user token. Auth-user
    # sessions, anon keys, service keys, and project access tokens are not
    # accepted. Poll it from a backend, not a browser.
    def get(project_id, function_name, execution_id)
      project, function_id, execution = execution_path(project_id, function_name, execution_id)
      response = Transport.invoke do
        @transport.get_durable_execution(
          authorization: @client.session_token,
          project_id: project, function_id: function_id, execution_id: execution
        )
      end
      durable_execution(Transport.body(response, 200))
    end

    # Lists a durable function's executions, most recent first. Each entry
    # carries the status the platform last observed rather than a live one;
    # read a single execution for that. Owner-scoped, like #get.
    def list(project_id, function_name, status: nil, page: nil, limit: nil)
      project = identifier(project_id, 'project_id')
      function_id = identifier(function_name, 'function_name')
      validate_paging(page, limit)
      response = Transport.invoke do
        @transport.list_durable_executions(
          authorization: @client.session_token, project_id: project, function_id: function_id,
          options: { status: status, page: page, limit: limit }.compact
        )
      end
      durable_execution_page(Transport.body(response, 200))
    end

    # Asks a running execution to stop. Accepted rather than awaited: what
    # comes back is the execution read after asking, and it often still says
    # +running+, so poll #get to see it reach +stopped+. Completed steps are
    # not undone, and repeating a stop is safe — an execution that has already
    # finished reports the state it settled in. Owner-scoped, like #get.
    def stop(project_id, function_name, execution_id)
      project, function_id, execution = execution_path(project_id, function_name, execution_id)
      response = Transport.invoke do
        @transport.stop_durable_execution(
          authorization: @client.session_token,
          project_id: project, function_id: function_id, execution_id: execution
        )
      end
      durable_execution(Transport.body(response, 200))
    end

    private

    def execution_path(project_id, function_name, execution_id)
      [
        identifier(project_id, 'project_id'),
        identifier(function_name, 'function_name'),
        identifier(execution_id, 'execution_id')
      ]
    end

    # An empty path segment would address the collection instead of the
    # execution, which is a different request rather than a failed one.
    def identifier(value, field)
      raise ArgumentError, "#{field} must be a non-empty String" unless value.is_a?(String) && present_string?(value)

      value.strip.freeze
    end

    # The generated client validates this header against the same pattern and
    # raises its own message, naming the operation and the option key it knows
    # the header by. Checked here first so the caller reads a message about the
    # argument they passed, the way Functions#invoke does for a function name.
    def execution_name_argument(value)
      name = identifier(value, 'execution_name')
      unless EXECUTION_NAME.match?(name)
        raise ArgumentError,
              'execution_name must be 1-255 characters of letters, numbers, dots, dashes or underscores'
      end

      name
    end

    # Same reason: the generated client enforces the page and limit bounds and
    # answers with its own vocabulary.
    def validate_paging(page, limit)
      raise ArgumentError, 'page must be a positive Integer' unless page.nil? || positive_integer?(page)

      validate_page_limit(limit)
    end

    def validate_page_limit(limit)
      return if limit.nil? || (limit.is_a?(Integer) && positive_integer?(limit) && limit <= MAX_PAGE_SIZE)

      raise ArgumentError, "limit must be an Integer between 1 and #{MAX_PAGE_SIZE}"
    end

    def positive_integer?(value)
      value.is_a?(Integer) && value.positive?
    end
  end
end
