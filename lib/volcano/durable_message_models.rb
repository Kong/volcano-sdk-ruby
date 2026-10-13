# frozen_string_literal: true

module Volcano
  DURABLE_MESSAGE_ATTRIBUTES = %i[
    id execution_id direction seq name data sender status sent_at delivered_at
  ].freeze
  private_constant :DURABLE_MESSAGE_ATTRIBUTES

  # Who sent a durable message. `type` is the credential it was sent with:
  # `service_key`, `user`, `anon`, `project` for the owner or a project access
  # token, or `execution` for a message the execution published. `user_id` is
  # nil unless `type` is `user`.
  DurableMessageSender = Data.define(:type, :user_id)

  # Reopens the generated record for checked initialization.
  class DurableMessageSender
    # @dynamic type, user_id, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(type:, user_id: nil)
      type = type.dup.freeze
      user_id = user_id&.dup&.freeze
      super
    end
  end

  # A message sent to a durable execution (`direction` `in`), or one it
  # published (`out`).
  #
  # `seq` orders an execution's messages in both directions. It increases with
  # every message but can skip numbers; list the ones after it with `after:`.
  # `delivered_at` is nil until the execution receives the message, and for
  # `out` messages. `data` is frozen all the way down.
  DurableMessage = Data.define(*DURABLE_MESSAGE_ATTRIBUTES)

  # Reopens the generated record for checked initialization.
  class DurableMessage
    # @dynamic id, execution_id, direction, seq, name, data, sender, status, sent_at
    # @dynamic delivered_at, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(**attributes)
      values = DurableApprovalAttributes.capture(
        attributes, DURABLE_MESSAGE_ATTRIBUTES, optional: %i[data delivered_at]
      )
      attributes = values
      super
    end
  end

  # Messages after a `seq`, oldest first. `has_more` says whether more follow;
  # read them with `after:` set to the last message's `seq`.
  DurableMessagePage = Data.define(:messages, :has_more)

  # Reopens the generated record for checked initialization.
  class DurableMessagePage
    # @dynamic messages, has_more, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(messages:, has_more:)
      messages = messages.to_a.dup.freeze
      super
    end
  end
end
