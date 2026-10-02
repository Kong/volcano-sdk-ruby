---
title: Sandboxes
description: Run isolated commands and manage sessions, files, and HTTP services from Ruby.
---

Run a command from trusted backend code in an environment with Sandbox access enabled:

```ruby
require 'volcano'
require 'securerandom'

client = Volcano::Client.new(
  anon_key: ENV.fetch('VOLCANO_ANON_KEY'),
  service_key: ENV.fetch('VOLCANO_SERVICE_KEY'),
  api_url: ENV.fetch('VOLCANO_API_URL', 'https://api.volcano.dev')
)
project_id = ENV.fetch('VOLCANO_PROJECT_ID')
request_id = SecureRandom.uuid
result = client.sandboxes.exec(
  project_id, 'python -c "print(42)"',
  region: 'aws-us-east-1', preset: 'python3.12', request_id: request_id
)
puts result.stdout
```

Keep the same `request_id` when retrying an uncertain create or execution. A new
ID represents a new operation. The SDK does not replay commands after transport failures. A rejected user token
is refreshed once; the retry preserves the request ID.
Nonzero exits and timeouts are result fields, not API exceptions. API failures
raise typed `Volcano::Error` exceptions with `status`, `code`, and `retry_after`
when supplied by the server.

## Keep a session

```ruby
client.sandboxes.create(
  project_id, region: 'aws-us-east-1', preset: 'python3.12', max_duration_seconds: 300
).use do |session|
  60.times do
    break if session.refresh.state == 'running'
    sleep 1
  end
  raise 'Sandbox did not become ready' unless session.state == 'running'

  bytes = (0..255).to_a.pack('C*')
  session.files.write('/tmp/input.bin', bytes)
  raise 'File changed' unless session.files.read('/tmp/input.bin') == bytes
  puts session.exec('wc -c /tmp/input.bin').stdout
end
```

Creation, suspension, resumption, and termination are asynchronous. Use `refresh`
to observe state. `use` requests termination when its block exits, including on
exceptions. If cleanup also fails, the original block exception is preserved.
It does not wait for termination to complete. Use `get(session_id)`
to reconnect, then `suspend`, `resume`, or `terminate` as needed. Files preserve
binary `String` content. Writes accept at most 8 MiB.

## Access a background HTTP service

Inside a running session, detach the service and redirect its streams:

```ruby
session.exec('nohup python -m http.server 8080 --bind 0.0.0.0 >/tmp/http.log 2>&1 </dev/null &')
access = session.access(8080)
# Send access.token in X-Volcano-Sandbox-Token when requesting access.url.
```

The process lasts until it exits or its session ends. Credentials are scoped to
this session and port and expire at `access.expires_at`. Do not log the token or
put it in URLs. See [Sandbox HTTP access](/platform/guides/sandboxes).

## Select presets and authorize users

`client.sandboxes.presets` lists available presets and regions. Supply exactly one
of `preset` or a saved template's `sandbox_id`. Omit `memory_mb` to preserve that
template's configured memory.

Only trusted backend code should call
`client.sandboxes.grant(session_id, auth_user_id, expires_at: expiry)` or
`client.sandboxes.revoke(session_id, auth_user_id)`. Project users can access only
sessions explicitly granted to them; they cannot create or manage sessions.
Service keys stay on the backend. Anonymous keys alone cannot use this facade.

When both credentials are configured, management operations use the service key.
Granted session reads, commands, files, and HTTP access use the signed-in user.
