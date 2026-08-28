# Volcano Ruby SDK

Official Ruby SDK for Volcano. This repository is a private proof of concept;
the gem is not published yet.

## Proof-of-concept API

Create a client with the project URL and anonymous key from Volcano:

```ruby
require "volcano"

client = Volcano::Client.new(
  api_url: "https://api.volcano.dev",
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  service_key: ENV["VOLCANO_SERVICE_KEY"]
)
```

The REST facade is synchronous. Successful calls return Volcano-owned values;
failures raise typed errors under `Volcano::Error`.

### Sign in

```ruby
session = client.auth.sign_in(email: "user@example.com", password: "secret")
```

### Query a database

```ruby
rows = client.database("main").from("items").select("*").eq("slug", "a").execute
```

### Upload and download an object

```ruby
client.storage.from("assets").upload("a.txt", "hello".b)
bytes = client.storage.from("assets").download("a.txt")
```

Uploads accept a binary `String` or an `IO`. Downloads return a binary
`String`.

### Acquire and release a lock

```ruby
lease = client.locks.acquire("build", ttl: 30)
client.locks.release("build", lease)
```

### Broadcast over realtime

Realtime calls are asynchronous and must run in an Async reactor:

```ruby
Async do
  channel = client.realtime.channel("deployments")
  channel.on("message") { |message| puts message.fetch("value") }
  channel.subscribe
  channel.send(event: "message", value: "contract")
  channel.unsubscribe
  client.realtime.disconnect
end.wait
```

This proof of concept implements connect, subscribe, publish, unsubscribe, and
clean shutdown. Reconnect, recovery, presence, and database-change
subscriptions are out of scope.

## Generated boundary

The internal REST transport is generated from the self-contained public
Volcano OpenAPI bundle at hosting commit
`a3f4a6e9d0fb48a16621383bd796d8b0d1378630`. Its SHA-256 is
`c26ab2f32961699b19f710c1174906b7baae077eefcec299a6c19a36d2f559f6`.
Generation uses `@openapitools/openapi-generator-cli` 2.41.0 with OpenAPI
Generator 7.17.0. Node is used only to regenerate the committed client and is
not a gem runtime dependency.

Run `npm ci && bin/check-openapi` to verify generated provenance. Use
`bundle exec rubocop -A` to apply safe formatting and lint fixes. Before
changing the facade, run `bundle exec rubocop --parallel`, `bundle exec rspec`,
and the shared Cucumber contract suite.

See [Authentication](docs/authentication.md) for account, session, hosted auth,
and OAuth examples.
