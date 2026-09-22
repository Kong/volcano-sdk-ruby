# frozen_string_literal: true

Volcano::UploadSession.new(session_id: 'session', part_size: '6', total_parts: 2, expires_at: Time.now)
Volcano::UploadSession.new(session_id: 'session', part_size: 6, total_parts: 2, expires_at: 'later')
Volcano::UploadSession.new(session_id: 'session', part_size: 6, total_parts: 2)
Volcano::UploadSession['session', 6, 2, Time.now].with(total_parts: '2')

Volcano::UploadPart.new(part_number: 1, etag: 'etag', size: '6')
Volcano::UploadPart.new(part_number: 1, etag: 'etag')
Volcano::UploadPart[1, 'etag', 6].with(part_number: '1')
