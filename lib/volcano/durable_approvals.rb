# frozen_string_literal: true

require 'time'

module Volcano
  # Lists, reads, and decides the approvals durable workflows request.
  #
  # Every operation takes the project id and the client's platform token.
  # Reads also accept a project access token, including a read-only one.
  # Deciding takes a person: a project access token is refused with
  # Error::PermissionDeniedError.
  class DurableApprovals
    include DurableArguments
    include DurableApprovalResponses
    include DurableApprovalStatsResponses

    # Bounds mirrored from the wire contract, for the reason DurableArguments gives.
    MAX_FUNCTION_LENGTH = 255
    MAX_COMMENT_LENGTH = 2000

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    LIST_FILTERS = %i[status function execution_id from to page limit].freeze
    private_constant :LIST_FILTERS

    # Lists approvals, newest first, filtered by any of +status+, +function+,
    # +execution_id+, +from+, +to+, +page+, and +limit+, given as keywords.
    # +function+ is a durable function's id or name; a name also matches
    # approvals from a deleted function of that name. +from+ is inclusive and
    # +to+ exclusive, each a Time or an ISO 8601 string with an offset.
    def list(project_id, filters = {})
      project = identifier(project_id, 'project_id')
      options = list_options(filters)
      response = Transport.invoke do
        @transport.list_durable_approvals(authorization: @client.session_token, project_id: project, options: options)
      end
      durable_approval_page(Transport.body(response, 200))
    end

    def get(project_id, approval_id)
      project = identifier(project_id, 'project_id')
      approval = identifier(approval_id, 'approval_id')
      response = Transport.invoke do
        @transport.get_durable_approval(
          authorization: @client.session_token, project_id: project, approval_id: approval
        )
      end
      durable_approval(Transport.body(response, 200))
    end

    # Counts approvals by outcome, overall, per workflow, and per UTC day of
    # request. The window defaults to the 30 days before +to+, which defaults
    # to now, and covers at most 366 days.
    def stats(project_id, function: nil, from: nil, to: nil)
      project = identifier(project_id, 'project_id')
      options = window(function, from, to).compact
      response = Transport.invoke do
        @transport.get_durable_approval_stats(
          authorization: @client.session_token, project_id: project, options: options
        )
      end
      durable_approval_stats(Transport.body(response, 200))
    end

    # Approves a pending approval; the workflow resumes with the decision.
    # Approving again returns the approval unchanged. Deciding one that was
    # denied, has expired, or was cancelled raises Error::ConflictError, whose
    # +code+ is +approval_decided+, +approval_expired+, or +approval_cancelled+.
    def approve(project_id, approval_id, comment: nil)
      decide(project_id, approval_id, comment) do |token, project, approval, note|
        @transport.approve_durable_approval(
          authorization: token, project_id: project, approval_id: approval, comment: note
        )
      end
    end

    # Denies a pending approval. A denial is a value the workflow branches on,
    # not an error in it. Repeats and conflicts behave as for #approve.
    def deny(project_id, approval_id, comment: nil)
      decide(project_id, approval_id, comment) do |token, project, approval, note|
        @transport.deny_durable_approval(
          authorization: token, project_id: project, approval_id: approval, comment: note
        )
      end
    end

    private

    def decide(project_id, approval_id, comment)
      project = identifier(project_id, 'project_id')
      approval = identifier(approval_id, 'approval_id')
      note = comment_argument(comment)
      response = Transport.invoke { yield(@client.session_token, project, approval, note) }
      durable_approval(Transport.body(response, 200))
    end

    def list_options(filters)
      status, function, execution_id, from, to, page, limit = list_filters(filters).values_at(*LIST_FILTERS)
      validate_paging(page, limit)
      window(function, from, to).merge(
        status: optional_identifier(status, 'status'),
        execution_id: optional_identifier(execution_id, 'execution_id'), page: page, limit: limit
      ).compact
    end

    # Refuses a misspelled filter, as an unknown keyword would be.
    def list_filters(filters)
      raise TypeError, 'filters must be a Hash' unless filters.is_a?(Hash)

      unknown = filters.keys - LIST_FILTERS
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      filters
    end

    def window(function, from, to)
      { function: function_filter(function), from: timestamp_argument(from, 'from'), to: timestamp_argument(to, 'to') }
    end

    def optional_identifier(value, field)
      value.nil? ? nil : identifier(value, field)
    end

    def function_filter(value)
      return if value.nil?

      name = value.is_a?(String) ? value.strip : ''
      return name.freeze if !name.empty? && name.length <= MAX_FUNCTION_LENGTH

      raise ArgumentError, "function must be a durable function id or name of 1 to #{MAX_FUNCTION_LENGTH} characters"
    end

    def comment_argument(value)
      return if value.nil?
      return value.dup.freeze if value.is_a?(String) && value.length <= MAX_COMMENT_LENGTH

      raise ArgumentError, "comment must be a String of at most #{MAX_COMMENT_LENGTH} characters"
    end
  end
end
