---
title: Database queries
description: Read and change Postgres rows through the Ruby SDK with filters, ordering, and pagination.
order: 3
---

Query an existing database and table using the signed-in user's permissions.
This example expects a `main` database with an `items` table containing `id`, `name`, and `status` columns, plus Row-Level Security policies that permit the user to read those rows.
Set the credentials described in the [quickstart](./README.md).

```ruby
require "volcano"

client = Volcano::Client.new(
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  api_url: ENV.fetch("VOLCANO_API_URL", "https://api.volcano.dev")
)
client.auth.sign_in(
  email: ENV.fetch("VOLCANO_USER_EMAIL"),
  password: ENV.fetch("VOLCANO_USER_PASSWORD")
)
items = client.database("main").from("items")
rows = items.select("id", "name").eq("status", "published").execute
rows.each { |row| puts [row["id"], row["name"]] }
```

`execute` returns an array of row hashes, including an empty array when no rows match.
Builders are immutable; each chained operation returns a new builder, so a base query can be reused.
The following examples reuse an authenticated `client` and the same table.

## Filter, sort, and page through rows

```ruby
base = client.database("main").from("items").select("id", "name")
rows = base.ilike("name", "%volcano%")
           .in("status", %w[draft published])
           .order("name")
           .order("id")
           .limit(20)
           .offset(40)
           .execute
```

| Methods | Filter |
| --- | --- |
| `eq`, `neq` | Equal or not equal to a value |
| `gt`, `gte`, `lt`, `lte` | Compare values |
| `like`, `ilike` | Case-sensitive or case-insensitive SQL pattern; `%` matches any sequence |
| `is("deleted_at", nil)` | Match a SQL null |
| `is("enabled", true)` | Match a SQL boolean |
| `in("status", %w[draft published])` | Match a member of a list |

Use `select("*")` to return every column.
Pass `ascending: false` to `order` for descending order.
Include a unique final sort column such as `id` when paging with `limit` and `offset`.

## Insert, update, and delete

```ruby
items = client.database("main").from("items")
created = items.insert(name: "Volcano", status: "draft").execute
item_id = created.first.fetch("id")
updated = items.update(status: "published").eq("id", item_id).execute
deleted = items.delete.eq("id", item_id).execute
```

Mutations return an array of the affected rows.
Updates and deletes with no matches return an empty array.
They require at least one filter; Volcano rejects filterless updates and deletes.

## Handle authentication failures

Database reads and mutations refresh a rejected access token once when the captured session has a usable refresh token, then retry the same request.
HTTP 403 responses and network failures do not trigger this retry.
Mutations are never retried after an ambiguous transport failure.
Replacing or signing out the session during recovery raises `Volcano::Error::SessionChangedError` instead of replaying under another user.

For direct Postgres connections inside a Volcano function, `Volcano.database_connection_string` can derive a connection string from `DATABASE_URL` and a server-validated `user_id:` while preserving its database target.
Passing a user ID applies that user's Row-Level Security context; omitting it requests service access.
Keep the resulting connection string private.
