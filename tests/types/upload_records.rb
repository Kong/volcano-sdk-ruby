# frozen_string_literal: true

require 'volcano'

expires_at = Time.utc(2026, 9, 30)
session = Volcano::UploadSession.new(session_id: 'session', part_size: 6, total_parts: 2, expires_at: expires_at)
raise 'Wrong session ID' unless session.session_id == 'session'
raise 'Wrong session members' unless Volcano::UploadSession.members == %i[session_id part_size total_parts expires_at]

updated_session = Volcano::UploadSession['session', 6, 2, expires_at].with(part_size: 12)
raise 'Wrong session part size' unless updated_session.part_size == 12
raise 'Wrong session snapshot' unless updated_session.to_h[:total_parts] == 2
raise 'Wrong session tuple' unless updated_session.deconstruct == ['session', 12, 2, expires_at]
raise 'Wrong session keys' unless updated_session.deconstruct_keys([:session_id])[:session_id] == 'session'

mapped_session = updated_session.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped session' unless mapped_session['part_size'] == '12'

part = Volcano::UploadPart.new(part_number: 1, etag: 'etag', size: 6)
raise 'Wrong part size' unless part.size == 6
raise 'Wrong part members' unless Volcano::UploadPart.members == %i[part_number etag size]

updated_part = Volcano::UploadPart[1, 'etag', 6].with(etag: 'other')
raise 'Wrong part etag' unless updated_part.etag == 'other'
raise 'Wrong part snapshot' unless updated_part.to_h[:part_number] == 1
raise 'Wrong part tuple' unless updated_part.deconstruct == [1, 'other', 6]
raise 'Wrong part keys' unless updated_part.deconstruct_keys([:etag])[:etag] == 'other'

mapped_part = updated_part.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped part' unless mapped_part['etag'] == 'other'
