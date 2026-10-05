---
title: Logs
description: Search retained project logs, paginate events, and read activity counts.
order: 6
---

Search logs and inspect activity for resources in your project.

Project logs require a platform user token or a [project access token](/platform/api-reference/using-the-api). For server-side log readers, create a `read_only` project token and set `VOLCANO_PROJECT_ACCESS_TOKEN`, `VOLCANO_PROJECT_ID`, and `VOLCANO_ANON_KEY`. Keep this credential on your server. The constructor requires an anon key, but the supplied project access token authorizes these requests. Project end-user sign-in, anon keys, and service keys do not grant project log access.

```ruby
require "volcano"

project_id = ENV.fetch("VOLCANO_PROJECT_ID")
client = Volcano::Client.new(
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  api_url: ENV.fetch("VOLCANO_API_URL", "https://api.volcano.dev"),
  access_token: ENV.fetch("VOLCANO_PROJECT_ACCESS_TOKEN")
)
request = { resource: { type: "function" }, q: "checkout_failed", limit: 100 }
page = client.logs.search(project_id, request)
page.data.each { |event| puts [event["timestamp"], event["body"]] }
```

`search` returns an immutable `Volcano::LogSearchResponse` with `data`, `limit`, `has_more`, and `next_cursor`.

## Continue a search

```ruby
if page.has_more && page.next_cursor
  next_page = client.logs.search(project_id, request.merge(cursor: page.next_cursor))
end
```

## Read activity buckets

```ruby
activity = client.logs.activity(
  project_id,
  { resource: request[:resource], q: request[:q], bucket_count: 24 }
)
puts activity.total
activity.data.each { |bucket| puts [bucket["start_time"], bucket["counts"], bucket["total"]] }
```

Keep the same resource selector, query, and time bounds on every pagination request. Results are newest first. `body` preserves JSON values, including objects and arrays; it is not always a string. Events include a stable `id`, `timestamp`, and owning `resource`.

Activity returns time buckets and a total count. Each bucket contains `start_time`, `end_time`, `total`, and `counts` grouped by `levels`, `regions`, and `resource_ids`.

Both methods accept `resource.ids` to restrict results to specific resources, `q` for text or field queries, and RFC3339 `start_time` and `end_time` bounds. Logs arrive asynchronously; use bounded polling when waiting for a new event. These methods read retained logs rather than open a live stream.

A project token has no refresh token. The SDK sends it as supplied and surfaces authentication failures; rotate or replace expired credentials through project token management. Do not use auth sign-out to revoke a project token.
