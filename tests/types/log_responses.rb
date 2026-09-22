# frozen_string_literal: true

require 'volcano'

event_time = Time.utc(2026, 9, 2, 12)
rows = [{
  'message' => 'started',
  'timestamp' => event_time,
  'metadata' => { 'attempt' => 1, 'updated_at' => event_time }
}]
search = Volcano::LogSearchResponse.new(data: rows, limit: 10, has_more: true, next_cursor: 'cursor')
raise 'Wrong members' unless Volcano::LogSearchResponse.members == %i[data limit has_more next_cursor]
raise 'Wrong search rows' unless search.data == rows && search.data.frozen?

bracket_search = Volcano::LogSearchResponse[rows, 10, false]
updated_search = bracket_search.with(next_cursor: 'later', has_more: true)
raise 'Wrong search update' unless updated_search.next_cursor == 'later'
raise 'Wrong search snapshot' unless updated_search.to_h[:has_more] == true
raise 'Wrong search tuple' unless updated_search.deconstruct == [rows, 10, true, 'later']
raise 'Wrong search keys' unless updated_search.deconstruct_keys([:limit])[:limit] == 10

mapped_search = updated_search.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped search' unless mapped_search['limit'] == '10'

activity = Volcano::LogActivityResponse.new(data: rows, total: 1)
raise 'Wrong activity members' unless Volcano::LogActivityResponse.members == %i[data total]
raise 'Wrong activity rows' unless activity.data == rows && activity.data.frozen?

bracket_activity = Volcano::LogActivityResponse[rows, 1]
updated_activity = bracket_activity.with(total: 2)
raise 'Wrong activity update' unless updated_activity.total == 2
raise 'Wrong activity snapshot' unless updated_activity.to_h[:total] == 2
raise 'Wrong activity tuple' unless updated_activity.deconstruct == [rows, 2]
raise 'Wrong activity keys' unless updated_activity.deconstruct_keys([:total])[:total] == 2

mapped_activity = updated_activity.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped activity' unless mapped_activity['total'] == '2'
