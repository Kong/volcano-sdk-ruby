# frozen_string_literal: true

bucket = Volcano::StorageBucket.new(
  Object.new, Object.new, 'assets', api_url: 'https://api.example.test', anon_key: 'anon'
)
bucket.upload('photo.png', 42)
bucket.update_visibility('photo.png', public: 'yes')
bucket.upload_part('video.mp4', session_id: 'upload', part_number: 'first', data: 'bytes')
