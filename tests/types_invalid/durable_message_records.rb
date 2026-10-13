# frozen_string_literal: true

Volcano::DurableMessageSender.new(type: :user)
Volcano::DurableMessage.new(
  id: 'message', execution_id: 'execution', direction: 'out', seq: '3', name: 'progress',
  sender: Volcano::DurableMessageSender.new(type: 'execution'), status: 'published', sent_at: 'today'
)
Volcano::DurableMessagePage.new(messages: ['message'], has_more: false)
