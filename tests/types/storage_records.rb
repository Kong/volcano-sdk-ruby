# frozen_string_literal: true

require 'volcano'

object = Volcano::StorageObject.new(
  id: 'object', bucket_id: 'bucket', name: 'photo.png', size: 5,
  mime_type: 'image/png', is_public: false
)
positional_object = Volcano::StorageObject.new('object', 'bucket', 'photo.png', 5, 'image/png', false)
raise 'Wrong object size' unless object.size == 5 && object.owner_id.nil?
raise 'Wrong positional object' unless positional_object == object
raise 'Wrong object members' unless Volcano::StorageObject.members == %i[
  id bucket_id name size mime_type is_public owner_id etag metadata created_at updated_at public_url
]

now = Time.utc(2026, 9, 22)
full_object = Volcano::StorageObject[
  'object', 'bucket', 'photo.png', 5, 'image/png', false, 'owner', 'etag',
  { 'labels' => ['profile'] }, now, now, nil
].with(public_url: 'https://example.com/photo.png')
raise 'Wrong object URL' unless full_object.public_url == 'https://example.com/photo.png'
raise 'Wrong object snapshot' unless full_object.to_h[:metadata] == { 'labels' => ['profile'] }
raise 'Wrong object tuple' unless full_object.deconstruct[0] == 'object'
raise 'Wrong object keys' unless full_object.deconstruct_keys([:size])[:size] == 5

mapped_object = full_object.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped object' unless mapped_object['size'] == '5'

page = Volcano::StoragePage.new(objects: [object])
raise 'Wrong page' unless page.objects == [object] && page.next_cursor.nil?
raise 'Wrong positional page' unless Volcano::StoragePage.new([object]) == page
raise 'Wrong page members' unless Volcano::StoragePage.members == %i[objects next_cursor]

updated_page = Volcano::StoragePage[[object], 'cursor'].with(next_cursor: 'next')
raise 'Wrong page cursor' unless updated_page.next_cursor == 'next'
raise 'Wrong page snapshot' unless updated_page.to_h[:objects] == [object]
raise 'Wrong page tuple' unless updated_page.deconstruct == [[object], 'next']
raise 'Wrong page keys' unless updated_page.deconstruct_keys([:next_cursor])[:next_cursor] == 'next'

mapped_page = updated_page.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped page' unless mapped_page['next_cursor'] == 'next'
