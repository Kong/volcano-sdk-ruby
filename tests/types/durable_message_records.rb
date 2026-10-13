# frozen_string_literal: true

require 'volcano'

sent = Time.utc(2026, 10, 12)
sender = Volcano::DurableMessageSender.new(type: 'execution')
raise 'Wrong sender' unless sender.type == 'execution' && sender.user_id.nil?
raise 'Wrong positional sender' unless Volcano::DurableMessageSender['user', 'user-1'].user_id == 'user-1'
raise 'Wrong sender keys' unless sender.deconstruct_keys([:type])[:type] == 'execution'

message = Volcano::DurableMessage.new(
  id: 'message', execution_id: 'execution', direction: 'out', seq: 3, name: 'progress',
  data: { 'percent' => 40 }, sender: sender, status: 'published', sent_at: sent
)
raise 'Wrong message' unless message.seq == 3 && message.delivered_at.nil?
raise 'Wrong message members' unless Volcano::DurableMessage.members.first.equal?(:id)
raise 'Wrong message tuple' unless message.deconstruct[2] == 'out'
raise 'Wrong delivered message' unless message.with(direction: 'in', delivered_at: sent).delivered_at == sent

page = Volcano::DurableMessagePage.new(messages: [message], has_more: false)
raise 'Wrong page' unless page.messages == [message] && !page.has_more
raise 'Wrong positional page' unless Volcano::DurableMessagePage[[message], true].has_more
raise 'Wrong page snapshot' unless page.to_h[:messages] == [message]
