---
title: Storage
description: Upload, download, list, move, and resume files using the Ruby SDK.
order: 4
---

Upload and read bytes from an existing `assets` bucket whose policies permit the signed-in user to access the object.
Set the [quickstart credentials](./README.md).

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
bucket = client.storage.from("assets")
bucket.upload("examples/hello.txt", "hello".b, content_type: "text/plain")
raise "Unexpected bytes" unless bucket.download("examples/hello.txt") == "hello".b
puts bucket.download("examples/hello.txt", range: "bytes=1-3")
```

Uploads accept a binary `String` or an `IO`; downloads return binary strings.
An omitted `content_type:` uses filename-based MIME detection with an `application/octet-stream` fallback.
Explicit content types must be non-blank printable ASCII and may include MIME parameters.
The following examples reuse an authenticated `client` and `bucket`.

## List and manage objects

```ruby
page = bucket.list("examples", limit: 100)
page.objects.each { |object| puts object.name }
next_page = bucket.list("examples", limit: 100, cursor: page.next_cursor) if page.next_cursor

copied = bucket.copy("examples/hello.txt", "examples/hello-copy.txt")
moved = bucket.move("examples/hello-copy.txt", "examples/hello-moved.txt")
removed = bucket.remove(["examples/hello-moved.txt"])
```

Copy preserves its source; move removes its source after creating the destination.
Object metadata and listing responses are immutable.
`remove` accepts one path or an array and returns removed paths.
It processes paths in order; a failure raises after earlier successful deletions.

## Control public visibility

```ruby
object = bucket.update_visibility("examples/hello.txt", public: true)
puts object.public_url
url = bucket.get_public_url("examples/hello.txt")
```

`update_visibility` returns server-confirmed metadata; its `public_url` is populated only for a public object.
`get_public_url` constructs a URL locally and does not check whether the object exists or is public.
Pass `public: false` to make an object private again.

## Upload a file in parts

```ruby
File.open("video.mp4", "rb") do |source|
  uploaded = bucket.upload_resumable(
    "videos/demo.mp4",
    source,
    content_type: "video/mp4",
    on_progress: ->(sent, total) { puts "#{sent}/#{total}" }
  )
  puts uploaded.name
end
```

The helper creates an upload session, uses the server-selected part size, and completes the object.
It streams seekable IO and spools non-seekable inputs to a temporary file with bounded reads.
Progress runs after each successful part with cumulative uploaded bytes and total size.
If a part or progress callback fails, the helper attempts to abort and raises the original error.

## Resume or cancel an upload session

For application-managed recovery, retain the session ID and upload progress yourself:

```ruby
payload = "example file".b
session = bucket.create_upload_session(
  "examples/resumable.txt",
  total_size: payload.bytesize,
  content_type: "text/plain"
)
offset = 0
while offset < payload.bytesize
  bucket.upload_part(
    "examples/resumable.txt",
    session_id: session.session_id,
    part_number: offset / session.part_size + 1,
    data: payload.byteslice(offset, session.part_size)
  )
  offset += session.part_size
end
status = bucket.get_upload_session("examples/resumable.txt", session_id: session.session_id)
puts [status.parts_uploaded, status.bytes_uploaded]
completed = bucket.complete_upload_session("examples/resumable.txt", session_id: session.session_id)
```

The server returns the part size, total part count, and session expiration.
`get_upload_session` exposes uploaded-part metadata to help an application resume.
Uploading the same part number again replaces that part.
To abandon an unfinished session, call `bucket.abort_upload_session(path, session_id: session_id)`; this discards its uploaded parts without publishing an object. Further session-status requests report not found.

Authenticated storage requests refresh and retry once after an explicit HTTP 401 when a refresh token is available.
They preserve the original request and session ownership, and do not retry ambiguous network failures or HTTP 403 responses.
