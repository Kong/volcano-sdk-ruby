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
  region: 'us-east-1', preset: 'python3.12', request_id: request_id
)
puts result.stdout
```

Keep the same `request_id` when retrying an uncertain create or execution. A new
ID represents a new operation. The SDK does not replay commands after transport failures. A rejected user token
is refreshed once; the retry preserves the request ID.
Nonzero exits and session command timeouts are result fields. A one-shot execution
timeout raises an API error (HTTP 504); retrying the same request ID returns an
unknown-outcome conflict (HTTP 409), without running the command again. API failures
raise typed `Volcano::Error` exceptions with `status`, `code`, and `retry_after`
when supplied by the server.

## Keep a session

```ruby
client.sandboxes.create(
  project_id, region: 'us-east-1', preset: 'python3.12', max_duration_seconds: 300
).use do |session|
  60.times do
    break if session.refresh.state == 'running'
    sleep 1
  end
  raise 'Sandbox did not become ready' unless session.state == 'running'

  bytes = (0..255).to_a.pack('C*')
  session.files.write('/workspace/input.bin', bytes)
  raise 'File changed' unless session.files.read('/workspace/input.bin') == bytes
  puts session.exec('wc -c /workspace/input.bin').stdout
end
```

Creation, suspension, resumption, and termination are asynchronous. Use `refresh`
to observe state; `state` is an immutable snapshot. `use` requests termination
when its block exits, including on exceptions. If cleanup also fails, the original
block exception is preserved.
Cleanup treats an already terminating, terminated, or missing session as complete.
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
`client.sandboxes.revoke(session_id, auth_user_id)`. Supply a `Time` or ISO8601
string for `expiry`; returned session and access expiries are `Time` values. Project users can access only
sessions explicitly granted to them; they cannot create or manage sessions.
Service keys stay on the backend. The preset catalog is public; anonymous keys cannot create or manage sessions.

When both credentials are configured, management operations use the service key.
Handles returned by `create` keep using service credentials for subsequent operations.
Handles returned by `get` use the signed-in user for granted reads, commands, files,
and HTTP access.

Creation and execution use explicit keyword arguments. Unknown keywords raise
`ArgumentError`; pass a keyword options hash with `**options`.

## Deploy a custom image from source

Package the Dockerfile fragment and its files as a `tar.gz` archive, up to 32 MiB.
The platform supplies the Amazon Linux base; fragments cannot use `FROM`, `USER`,
or `ENTRYPOINT`. Use `RUN`, `COPY`, and `CMD` to install and launch your service.
Keep the template ID, request ID, archive, and options unchanged when retrying an
uncertain upload. A new request ID creates another version of the same template.

```ruby
template_id = SecureRandom.uuid
request_id = SecureRandom.uuid
archive = File.binread('sandbox-source.tar.gz')
deployment = client.sandboxes.deploy(
  project_id, template_id, archive,
  name: 'my-custom-sandbox', memory_mb: 1024, ports: [8080], request_id: request_id
)
status = client.sandboxes.deployment(project_id, template_id, deployment.id)
history = client.sandboxes.deployments(project_id, template_id, limit: 10)
logs = client.sandboxes.logs(project_id, template_id, deployment.id, region: 'aws-us-east-1')
File.binwrite('exported-source.tar.gz', client.sandboxes.source(project_id, template_id, deployment.id))
```

Poll `deployment` until `status` is `active`; stop on `failed` or `deleted`.
Only active versions can create sessions. `history.next_cursor` and
`logs.next_cursor` can be passed as `cursor:` to retrieve the next page.
`delete_template(project_id, template_id)` removes the custom template and its
sessions and requires the `sandboxes.terminate` permission. History page limits
range from 1 to 100. All template management uses backend service credentials.

Custom deployments accept at most 16 unique ports, from 1 through 65532.
