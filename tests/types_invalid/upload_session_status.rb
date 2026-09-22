# frozen_string_literal: true

Volcano::UploadSessionStatus.new(
  session_id: 'session', status: 'uploading', path: 'photo.png', content_type: 'image/png',
  total_size: '12', part_size: 6, total_parts: 2, parts_uploaded: 1, bytes_uploaded: 6,
  parts: [], expires_at: Time.now, created_at: Time.now
)

Volcano::UploadSessionStatus.new(session_id: 'session')
Volcano::UploadSessionStatus['session', 'uploading', 'photo.png', 'image/png', 12, 6, 2, 1, 6, [], Time.now, Time.now]
  .with(parts: ['not a part'])
