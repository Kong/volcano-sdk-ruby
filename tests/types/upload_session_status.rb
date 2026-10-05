# frozen_string_literal: true

require 'volcano'

expiry = Time.utc(2026, 9, 30)
created = Time.utc(2026, 9, 22)
part = Volcano::UploadPart.new(part_number: 1, etag: 'etag', size: 6)
status = Volcano::UploadSessionStatus.new(
  session_id: 'session', status: 'uploading', path: 'photo.png', content_type: 'image/png',
  total_size: 12, part_size: 6, total_parts: 2, parts_uploaded: 1, bytes_uploaded: 6,
  parts: [part], expires_at: expiry, created_at: created
)
positional = Volcano::UploadSessionStatus.new(
  'session', 'uploading', 'photo.png', 'image/png', 12, 6, 2, 1, 6, [part], expiry, created
)

raise 'Wrong status' unless status.status == 'uploading' && status.parts == [part]
raise 'Wrong positional constructor' unless positional == status
raise 'Wrong members' unless Volcano::UploadSessionStatus.members == %i[
  session_id status path content_type total_size part_size total_parts parts_uploaded
  bytes_uploaded parts expires_at created_at
]

updated = Volcano::UploadSessionStatus[
  'session', 'uploading', 'photo.png', 'image/png', 12, 6, 2, 1, 6, [part], expiry, created
].with(parts_uploaded: 2)
raise 'Wrong uploaded count' unless updated.parts_uploaded == 2
raise 'Wrong snapshot' unless updated.to_h[:expires_at] == expiry
raise 'Wrong tuple' unless updated.deconstruct[9] == [part]
raise 'Wrong keys' unless updated.deconstruct_keys([:parts_uploaded])[:parts_uploaded] == 2

mapped = updated.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped status' unless mapped['status'] == 'uploading'
