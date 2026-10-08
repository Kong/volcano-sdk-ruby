# frozen_string_literal: true

require_relative 'immutable_request_value'

module Volcano
  DURABLE_APPROVAL_ATTRIBUTES = %i[
    id status name title description details function execution requested_at expires_at decision
  ].freeze
  DURABLE_APPROVAL_STATS_ATTRIBUTES = %i[
    from to counts approval_rate median_seconds_to_decision p90_seconds_to_decision
    functions other_functions daily
  ].freeze
  private_constant :DURABLE_APPROVAL_ATTRIBUTES, :DURABLE_APPROVAL_STATS_ATTRIBUTES

  # Checks keywords for the approval records with too many fields for an
  # explicit keyword list, and owns immutable copies of their values.
  module DurableApprovalAttributes
    def self.capture(attributes, names, optional:)
      unknown = attributes.keys - names
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      missing = names - optional - attributes.keys
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?

      names.to_h { |name| [name, immutable_value(attributes[name])] }
    end

    def self.immutable_value(value)
      case value
      when Hash, Array, Time, String then ImmutableRequestValue.capture(value)
      else value
      end
    end
  end
  private_constant :DurableApprovalAttributes

  # The durable function that requested an approval. `id` is nil once the
  # function has been deleted; `name` is kept.
  DurableApprovalFunction = Data.define(:id, :name)

  # Reopens the generated record for checked initialization.
  class DurableApprovalFunction
    # @dynamic id, name, members, with, to_h, deconstruct, deconstruct_keys, self.[]
    # @dynamic self.members
    def initialize(id:, name:)
      id = id&.dup&.freeze
      name = name.dup.freeze
      super
    end
  end

  # The durable execution that requested an approval. `id` and `status` are
  # nil once the execution is no longer retained; `name` is kept.
  DurableApprovalExecution = Data.define(:id, :name, :status)

  # Reopens the generated record for checked initialization.
  class DurableApprovalExecution
    # @dynamic id, name, status, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(id:, name:, status:)
      id = id&.dup&.freeze
      name = name.dup.freeze
      status = status&.dup&.freeze
      super
    end
  end

  # The person who decided an approval.
  DurableApprovalDecider = Data.define(:id, :email)

  # Reopens the generated record for checked initialization.
  class DurableApprovalDecider
    # @dynamic id, email, members, with, to_h, deconstruct, deconstruct_keys, self.[]
    # @dynamic self.members
    def initialize(id:, email:)
      id = id.dup.freeze
      email = email.dup.freeze
      super
    end
  end

  # Who decided an approval and when. `decided_by` is nil once that person's
  # account is deleted.
  DurableApprovalDecision = Data.define(:comment, :decided_by, :decided_at)

  # Reopens the generated record for checked initialization.
  class DurableApprovalDecision
    # @dynamic comment, decided_by, decided_at, members, with, to_h, deconstruct
    # @dynamic deconstruct_keys, self.[], self.members
    def initialize(comment:, decided_by:, decided_at:)
      comment = comment.dup.freeze
      decided_at = decided_at.dup.freeze
      super
    end
  end

  # An approval a durable workflow requested.
  #
  # `decision` is nil unless the approval was approved or denied, and
  # `expires_at` is nil when the workflow set no timeout. `details` is the
  # workflow's own JSON, frozen all the way down.
  DurableApproval = Data.define(*DURABLE_APPROVAL_ATTRIBUTES)

  # Reopens the generated record for checked initialization.
  class DurableApproval
    # @dynamic id, status, name, title, description, details, function, execution
    # @dynamic requested_at, expires_at, decision, members, with, to_h, deconstruct
    # @dynamic deconstruct_keys, self.[], self.members
    def initialize(**attributes)
      values = DurableApprovalAttributes.capture(
        attributes, DURABLE_APPROVAL_ATTRIBUTES, optional: %i[details expires_at decision]
      )
      attributes = values
      super
    end
  end

  # One page of a project's approvals, newest first.
  DurableApprovalPage = Data.define(:approvals, :page, :limit, :total, :has_more)

  # Reopens the generated record for checked initialization.
  class DurableApprovalPage
    # @dynamic approvals, page, limit, total, has_more, members, with, to_h, deconstruct
    # @dynamic deconstruct_keys, self.[], self.members
    def initialize(approvals:, page:, limit:, total:, has_more:)
      approvals = approvals.to_a.dup.freeze
      super
    end
  end

  # Approvals by status. `requested` counts every approval, whatever its status.
  DurableApprovalCounts = Data.define(:requested, :pending, :approved, :denied, :expired, :cancelled)

  # One workflow's approval counts.
  DurableApprovalFunctionCounts = Data.define(:function, :counts)

  # Approval counts for one UTC day, given as `YYYY-MM-DD`.
  DurableApprovalDailyCounts = Data.define(:date, :counts)

  # Reopens the generated record for checked initialization.
  class DurableApprovalDailyCounts
    # @dynamic date, counts, members, with, to_h, deconstruct, deconstruct_keys, self.[]
    # @dynamic self.members
    def initialize(date:, counts:)
      date = date.dup.freeze
      super
    end
  end

  # Approval outcomes over a time window.
  #
  # `functions` holds the ten workflows that requested the most approvals and
  # `other_functions` sums the rest. `daily` omits days without approvals.
  # The rate and decision times are nil when nothing in the window was decided.
  DurableApprovalStats = Data.define(*DURABLE_APPROVAL_STATS_ATTRIBUTES)

  # Reopens the generated record for checked initialization.
  class DurableApprovalStats
    # @dynamic from, to, counts, approval_rate, median_seconds_to_decision
    # @dynamic p90_seconds_to_decision, functions, other_functions, daily, members, with
    # @dynamic to_h, deconstruct, deconstruct_keys, self.[], self.members
    def initialize(**attributes)
      values = DurableApprovalAttributes.capture(
        attributes, DURABLE_APPROVAL_STATS_ATTRIBUTES,
        optional: %i[approval_rate median_seconds_to_decision p90_seconds_to_decision]
      )
      attributes = values
      super
    end
  end
end
