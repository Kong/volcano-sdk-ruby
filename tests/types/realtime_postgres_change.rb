# frozen_string_literal: true

require 'volcano'

change = Volcano::Realtime::PostgresChange.new(
  type: 'UPDATE', schema: 'public', table: 'messages', timestamp: '2026-09-22T00:00:00Z',
  record: { 'id' => 7, 'body' => 'new' }, old_record: { 'id' => 7, 'body' => 'old' },
  columns: ['body']
)
raise 'Wrong change type' unless change.type == 'UPDATE' && change.schema == 'public'
raise 'Wrong row' unless change.record == { 'id' => 7, 'body' => 'new' }
raise 'Wrong old row' unless change.old_record == { 'id' => 7, 'body' => 'old' }
raise 'Wrong column' unless change.columns == ['body']
raise 'Wrong timestamp' unless change.timestamp == '2026-09-22T00:00:00Z'
raise 'Wrong members' unless Volcano::Realtime::PostgresChange.members == %i[
  type schema table record old_record columns timestamp id mode
]

updated = change.with(id: 7, mode: 'lightweight')
raise 'Wrong update' unless updated.id == 7 && updated.mode == 'lightweight'
raise 'Wrong snapshot' unless updated.to_h[:record] == { 'id' => 7, 'body' => 'new' }
raise 'Wrong tuple' unless updated.deconstruct[7] == 7
raise 'Wrong keys' unless updated.deconstruct_keys([:id])[:id] == 7

positional = Volcano::Realtime::PostgresChange.new(
  'UPDATE', 'public', 'messages', { 'id' => 7, 'body' => 'new' },
  { 'id' => 7, 'body' => 'old' }, ['body'], '2026-09-22T00:00:00Z', nil, nil
)
raise 'Wrong positional change' unless positional == change
raise 'Wrong bracket change' unless Volcano::Realtime::PostgresChange[
  type: 'UPDATE', schema: 'public', table: 'messages', timestamp: '2026-09-22T00:00:00Z',
  record: { 'id' => 7, 'body' => 'new' }, old_record: { 'id' => 7, 'body' => 'old' },
  columns: ['body']
] == change

mapped = change.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped change' unless mapped['type'] == 'UPDATE'
