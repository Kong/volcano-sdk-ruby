# frozen_string_literal: true

# Access-token fixtures carry a stable session ID across token rotations.
module SessionFixtures
  def access_token(version = 'original')
    payload = [{ session_id: '00000000-0000-4000-8000-000000000010', version: version }.to_json].pack('m0')
    "header.#{payload.tr('+/', '-_').delete('=')}.signature"
  end
end
