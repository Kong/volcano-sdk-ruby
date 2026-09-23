# frozen_string_literal: true

Volcano::Realtime::PostgresChange.new(
  type: 123, schema: 'public', table: 'messages', timestamp: '2026-09-22T00:00:00Z'
)
Volcano::Realtime::PostgresChange.new(
  type: 'INSERT', schema: 'public', table: 'messages', timestamp: '2026-09-22T00:00:00Z',
  columns: 'not an array'
)
Volcano::Realtime::PostgresChange.new(
  type: 'INSERT', schema: 'public', table: 'messages', timestamp: '2026-09-22T00:00:00Z'
).with(mode: 123)
