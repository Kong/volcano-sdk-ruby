# frozen_string_literal: true

require 'tempfile'

# @type method storage_object_operations: (Volcano::StorageBucket) -> void
def storage_object_operations(bucket)
  bucket.list('photos/', limit: 10)

  uploaded = bucket.upload('photo.png', 'binary'.b, content_type: 'image/png')
  uploaded.fetch('name')
  temporary = Tempfile.new('storage-upload')
  bucket.upload('photo.png', temporary)
  bucket.upload_resumable('photo.png', temporary)
  temporary.close!
  bucket.download('photo.png', range: 'bytes=0-4')
  bucket.move('photo.png', 'archive/photo.png')
  bucket.update_visibility('photo.png', public: false)
end

# @type method storage_session_operations: (Volcano::StorageBucket) -> void
def storage_session_operations(bucket)
  bucket.create_upload_session('video.mp4', total_size: 10, part_size: 5)
  bucket.upload_part('video.mp4', session_id: 'upload', part_number: 1, data: 'bytes')
  bucket.get_upload_session('video.mp4', session_id: 'upload')
  bucket.abort_upload_session('video.mp4', session_id: 'upload')
end
