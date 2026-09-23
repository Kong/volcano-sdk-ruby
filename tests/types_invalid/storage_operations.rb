# frozen_string_literal: true

# @type method invalid_storage_operations: (Volcano::StorageBucket) -> void
def invalid_storage_operations(bucket)
  bucket.upload('photo.png', 42)
  bucket.update_visibility('photo.png', public: 'yes')
  bucket.upload_part('video.mp4', session_id: 'upload', part_number: 'first', data: 'bytes')
end
