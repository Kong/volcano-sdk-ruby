# frozen_string_literal: true

require 'volcano'

bucket = Volcano::StorageBucket.new(
  Object.new, Object.new, 'assets',
  api_url: 'https://api.example.test',
  anon_key: 'header.eyJwcm9qZWN0X2lkIjoicHJvamVjdCJ9.signature'
)
url = bucket.get_public_url('avatars/Ada photo.png')
raise 'Wrong public URL' unless url == 'https://api.example.test/public/project/assets/avatars/Ada%20photo.png'
raise 'Mutable public URL' unless url.frozen?
