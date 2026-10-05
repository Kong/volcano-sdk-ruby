# frozen_string_literal: true

Volcano::LogSearchResponse.new(data: [], limit: 10, has_more: true, extra: 1)
Volcano::LogSearchResponse.new(data: [], limit: '10', has_more: true)
Volcano::LogSearchResponse[[], 10, 'yes']
Volcano::LogSearchResponse.new(data: [], limit: 10, has_more: true).with(next_cursor: 1)
Volcano::LogSearchResponse.new(data: [], limit: 10, has_more: true).deconstruct_keys

Volcano::LogActivityResponse.new(data: [], total: '1')
Volcano::LogActivityResponse[[], 1].with(total: '2')
Volcano::LogActivityResponse.new(data: [])
