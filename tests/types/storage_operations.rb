# frozen_string_literal: true

bucket = Volcano::StorageBucket.new(
  Object.new, Object.new, 'assets', api_url: 'https://api.example.test', anon_key: 'anon'
)
bucket.list('photos/', limit: 10)

bucket.upload('photo.png', 'binary'.b, content_type: 'image/png')
bucket.download('photo.png', range: 'bytes=0-4')
bucket.move('photo.png', 'archive/photo.png')
bucket.update_visibility('photo.png', public: false)
bucket.create_upload_session('video.mp4', total_size: 10, part_size: 5)
bucket.upload_part('video.mp4', session_id: 'upload', part_number: 1, data: 'bytes')
bucket.get_upload_session('video.mp4', session_id: 'upload')
bucket.abort_upload_session('video.mp4', session_id: 'upload')
