# Broadcast Recovery Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover missed Ruby broadcast publications after reconnect without changing the public facade or enabling recovery for presence and Postgres channels.

**Architecture:** Extend the internal Centrifugo protocol adapter with immutable epoch/offset state, ordered subscription-reply publication dispatch, and per-channel gap tracking. A broadcast channel owns a user-lineage-scoped cursor and advances it only after the current callback generation crosses both callback and lifecycle serialization boundaries.

**Tech Stack:** Ruby 3.2/3.4, Async queues and semaphores, RSpec, RuboCop, Cucumber contract discovery, Centrifugo JSON protocol.

**Spec:** `docs/superpowers/specs/2026-09-03-realtime-recovery-slices-design.md`

## Global Constraints

- Slice 1 enables recovery only for `type: :broadcast` channels.
- Presence and Postgres subscribe, delivery, teardown, and reconnect behavior must remain unchanged.
- Keep `Volcano::Realtime::Channel` and callback payloads source-compatible.
- Store recovery state only in memory for one `Volcano::Client` and authenticated-user lineage.
- Do not change OpenAPI, generated REST code, shared Gherkin, Hosting source, package publication, or repository visibility.
- Recovered publications must precede live publications read after their subscribe reply.
- A rejected or stale publication must never move a recovery cursor past an undelivered offset.
- Run Ruby's strict native gates and the Hosting SDK contract guards before review.

---

### Task 1: Encode internal Centrifugo recovery subscriptions

**Files:**
- Modify: `lib/volcano/realtime/protocol.rb`
- Test: `spec/volcano/realtime/protocol_spec.rb`

**Interfaces:**
- Consumes: existing `Protocol.subscribe(channel:, recoverable: false, join_leave: false)`.
- Produces: `Protocol.subscribe(channel:, recovery: nil, recoverable: false, join_leave: false)` where `recovery` is either `nil` or an immutable `{epoch:, offset:}` hash.
- Produces: subscribe JSON with `recover: true`, `positioned: true`, and `recoverable: true` whenever `recovery` is non-`nil`; include `epoch` and `offset` only when present.

- [ ] **Step 1: Write the failing command tests**

Add two focused examples to `spec/volcano/realtime/protocol_spec.rb`:

```ruby
it 'builds an initial recovery subscription command' do
  command = described_class.subscribe(
    id: 7, channel: 'broadcast:contract', recovery: {}
  )

  expect(command).to eq(
    'id' => 7,
    'subscribe' => {
      'channel' => 'broadcast:contract',
      'recover' => true,
      'positioned' => true,
      'recoverable' => true
    }
  )
end

it 'builds a recovery subscription command from a stream position' do
  command = described_class.subscribe(
    id: 7,
    channel: 'broadcast:contract',
    recovery: { epoch: 'epoch-1', offset: 42 }
  )

  expect(command.fetch('subscribe')).to include(
    'recover' => true,
    'epoch' => 'epoch-1',
    'offset' => 42,
    'positioned' => true,
    'recoverable' => true
  )
end
```

- [ ] **Step 2: Run the command examples and verify RED**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec \
  spec/volcano/realtime/protocol_spec.rb \
  --example 'initial recovery subscription command' \
  --example 'stream position'
```

Expected: both examples fail because `recovery:` is unknown.

- [ ] **Step 3: Add the minimal recovery options to the existing command builder**

Keep command construction in `Protocol` for this slice; do not extract every
protocol command into a new module solely to accommodate recovery.

```ruby
def self.subscribe(id:, channel:, recovery: nil, recoverable: false, join_leave: false)
  options = { 'channel' => channel }
  if recovery
    options.merge!('recover' => true, 'positioned' => true, 'recoverable' => true)
    options['epoch'] = recovery.fetch(:epoch) if recovery.key?(:epoch)
    options['offset'] = recovery.fetch(:offset) if recovery.key?(:offset)
  end
  options['recoverable'] = true if recoverable
  options['join_leave'] = true if join_leave
  { 'id' => id, 'subscribe' => options }
end
```

Pass `recovery:` through the instance method when building the request. Do not
yet process publications or retain a position.

- [ ] **Step 4: Run the focused tests and RuboCop**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec spec/volcano/realtime/protocol_spec.rb
/opt/homebrew/bin/bundle exec rubocop \
  lib/volcano/realtime/protocol.rb spec/volcano/realtime/protocol_spec.rb
```

Expected: protocol examples pass and RuboCop reports no offenses. If the
command method violates strict complexity or length limits, extract only a
private `add_recovery_options(options, recovery)` method.

- [ ] **Step 5: Commit the command boundary**

```bash
git add lib/volcano/realtime/protocol.rb spec/volcano/realtime/protocol_spec.rb
git commit -m "feat(realtime): request broadcast recovery"
```

---

### Task 2: Process retained publications before later live pushes

**Files:**
- Create: `lib/volcano/realtime/protocol_recovery.rb`
- Modify: `lib/volcano/realtime/protocol.rb`
- Modify: `lib/volcano/realtime/protocol_dispatch.rb`
- Modify: `lib/volcano/realtime/protocol_io.rb`
- Modify: `lib/volcano/realtime/protocol_lifecycle.rb`
- Test: `spec/volcano/realtime/protocol_spec.rb`

**Interfaces:**
- Produces: private `Protocol::Pending = Data.define(:queue, :on_reply)`.
- Produces: private `request(on_reply: nil)`; the callback runs in frame order before its reply wakes the requester.
- Produces: `Protocol#position(channel)`, `#complete_publication(channel, publication)`, and `#drop_publication(channel, publication)` for channel coordination.
- Changes the internal publication handler invocation to `(event, data, publication, recovered:)`.

- [ ] **Step 1: Write a failing same-frame ordering test**

Create one protocol example whose fake socket returns a subscribe reply and a
live push in the same raw frame. The reply contains recovered offsets 2 and 3;
the live push has offset 4. Subscribe with `{epoch: 'epoch-1', offset: 1}` and
assert that the handler receives:

```ruby
expect(received).to eq(
  [
    ['recovered-2', 2, true],
    ['recovered-3', 3, true],
    ['live-4', 4, false]
  ]
)
```

The handler must record the publication's offset and the `recovered:` flag.

- [ ] **Step 2: Run the ordering example and verify RED**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec \
  spec/volcano/realtime/protocol_spec.rb \
  --example 'recovered publications before a same-frame live push'
```

Expected: the recovered publications are absent or appear after the live push.

- [ ] **Step 3: Add ordered reply processing and immutable positions**

Add `Protocol::Pending`, store it in `@pending`, and run `on_reply` inside
`dispatch_reply` before enqueuing the response value. Skip the hook for
`Protocol::Failure`.

Create `ProtocolRecovery` with these responsibilities:

```ruby
def process_subscription_result(channel, result)
  @position_gaps.delete(channel)
  publications = result.fetch('publications', [])
  remember_recovery_start(channel, result, publications)
  publications.each { |publication| dispatch_recovered_publication(channel, publication) }
  remember_subscription_position(channel, result) if publications.empty?
end
```

Initialize the first retained batch at `first_offset - 1`; initialize an empty
batch from the result's epoch and offset. Reject malformed epoch/offset pairs
instead of coercing them. Freeze the epoch string and position hash.

Dispatch recovered publications into the existing callback queue before the
subscribe reply wakes its caller. Pass the full publication and `recovered:`
flag to internal handlers. Preserve existing two-argument user callbacks by
keeping the extra values inside the protocol-to-channel adapter.

- [ ] **Step 4: Run the protocol suite and verify GREEN**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec spec/volcano/realtime/protocol_spec.rb
```

Expected: all protocol examples pass, including existing presence dispatch,
request limits, timeout, and callback-isolation examples.

- [ ] **Step 5: Commit ordered retained-publication processing**

```bash
git add \
  lib/volcano/realtime/protocol.rb \
  lib/volcano/realtime/protocol_dispatch.rb \
  lib/volcano/realtime/protocol_io.rb \
  lib/volcano/realtime/protocol_lifecycle.rb \
  lib/volcano/realtime/protocol_recovery.rb \
  spec/volcano/realtime/protocol_spec.rb
git commit -m "feat(realtime): order recovered broadcasts"
```

---

### Task 3: Preserve a contiguous cursor under callback pressure

**Files:**
- Modify: `lib/volcano/realtime/protocol_dispatch.rb`
- Modify: `lib/volcano/realtime/protocol_recovery.rb`
- Test: `spec/volcano/realtime/protocol_spec.rb`

**Interfaces:**
- Consumes: `Protocol#complete_publication` after successful channel admission.
- Consumes: `Protocol#drop_publication` when the bounded live callback queue rejects a publication.
- Produces: a per-channel earliest-gap barrier that prevents a later offset from advancing over an undelivered offset.

- [ ] **Step 1: Write a failing gap-barrier test**

Configure `max_callback_queue: 1`. Block delivery of offset 1, queue offset 2,
drop offset 3 because the queue is full, then deliver offset 4 after capacity
returns. Have the handler call `complete_publication` before recording each
value. Assert:

```ruby
expect(protocol.position('broadcast:contract')).to eq(
  epoch: 'epoch-1', offset: 2
)
```

This proves offset 4 cannot move the cursor beyond dropped offset 3.

- [ ] **Step 2: Run the gap test and verify RED**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec \
  spec/volcano/realtime/protocol_spec.rb \
  --example 'past a dropped live publication'
```

Expected: the position incorrectly reaches offset 4 or no gap API exists.

- [ ] **Step 3: Add the per-channel gap barrier**

When the live queue is full, call `mark_publication_gap` with the rejected
publication. Retain the earliest valid gap for the current epoch. If metadata
is malformed, use a boolean barrier that prevents all later advancement for
that subscription. Clear gaps only when processing a new successful subscribe
result. Recovered publications bypass the live queue limit and enqueue with
backpressure.

- [ ] **Step 4: Write and pass a recovered-backpressure test**

Add a second example with `max_callback_queue: 1` and two retained
publications. Block the first callback and assert both values eventually arrive
in order. Run the example before implementation to observe the second retained
publication being dropped, then implement `enforce_limit: false` only for
recovered dispatch and rerun it to pass.

- [ ] **Step 5: Run focused verification and commit**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec spec/volcano/realtime/protocol_spec.rb
/opt/homebrew/bin/bundle exec rubocop \
  lib/volcano/realtime/protocol_dispatch.rb \
  lib/volcano/realtime/protocol_recovery.rb \
  spec/volcano/realtime/protocol_spec.rb
```

Then commit:

```bash
git add \
  lib/volcano/realtime/protocol_dispatch.rb \
  lib/volcano/realtime/protocol_recovery.rb \
  spec/volcano/realtime/protocol_spec.rb
git commit -m "fix(realtime): preserve contiguous recovery cursors"
```

---

### Task 4: Restore broadcast channels from delivered positions

**Files:**
- Modify: `lib/volcano/realtime.rb`
- Modify: `lib/volcano/realtime/channel_callbacks.rb`
- Modify: `lib/volcano/realtime/channel_lifecycle.rb`
- Test: `spec/volcano/realtime_spec.rb`

**Interfaces:**
- Produces: private immutable `PublicationContext(protocol:, publication:, generation:, recovered:)`.
- Produces: channel-owned `@stream_position` and `@stream_lineage`.
- Consumes: `Realtime#capture_protocol_session` to scope the cursor to the authenticated-user lineage.
- Requests `recovery: recovery_position` only when `broadcast?`; presence and Postgres call `Protocol#subscribe` with `recovery: nil`.

- [ ] **Step 1: Write a failing reconnect test**

Using two `FacadeSocket` instances, subscribe a broadcast channel, deliver live
offset 2 from epoch `epoch-1`, fail the first socket, and wait for restoration
on the second. Assert that the replacement subscribe command includes:

```ruby
expect(subscribe.fetch('subscribe')).to include(
  'channel' => 'broadcast:contract',
  'recover' => true,
  'epoch' => 'epoch-1',
  'offset' => 2
)
```

- [ ] **Step 2: Run the reconnect test and verify RED**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec \
  spec/volcano/realtime_spec.rb \
  --example 'recovers a broadcast from its last delivered position'
```

Expected: the replacement subscribe omits recovery fields.

- [ ] **Step 3: Add channel cursor ownership and completion**

Initialize an empty frozen position and `nil` lineage. For broadcasts, pass the
current position into `Protocol#subscribe`. After subscribing and before
protocol teardown, snapshot `protocol.position(@name)` into the channel.

Wrap internal publications in a generation-bearing context. Add a
`before_delivery` operation to the existing callback delivery tuple. It must:

1. run while the callback semaphore is held;
2. acquire the lifecycle semaphore;
3. verify the publication generation is current;
4. call `protocol.complete_publication`;
5. update `@stream_position`; and
6. return `true` only when callback dispatch may continue.

If the operation returns `false`, suppress the user callback. Increment the
generation whenever the broadcast publication handler is detached. Select this
context-aware path only when `broadcast?`; presence and Postgres handlers must
continue calling their existing two-argument delivery path without cursor or
generation behavior. A suitable adapter shape is:

```ruby
@publication_handler = protocol.on_publication(@name) do |event, data, publication, recovered:|
  if broadcast?
    deliver_broadcast(event, data, publication, recovered, generation)
  else
    deliver_publication(event, data)
  end
end
```

- [ ] **Step 4: Add and pass initial-retention and same-frame facade tests**

Add separate examples proving:

- an initial `recovery: {}` response with retained offsets establishes a base
  cursor and the next reconnect starts after the delivered retained offset;
- recovered offsets 2 and 3 arrive before same-frame live offset 4 at the
  public `channel.on('message')` callback.

Run each test before its production change and confirm the expected failure.
Then rerun the focused facade examples until they pass.

- [ ] **Step 5: Prove non-broadcast channels are unchanged**

Add or extend one existing command assertion so presence retains
`recoverable: true` and `join_leave: true` without `recover`, while Postgres
subscribe commands omit all recovery fields. Assert the exact hashes; do not
rely on absence by visual inspection.

- [ ] **Step 6: Run the complete realtime suite and commit**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec \
  spec/volcano/realtime/protocol_spec.rb spec/volcano/realtime_spec.rb
/opt/homebrew/bin/bundle exec rubocop \
  lib/volcano/realtime.rb \
  lib/volcano/realtime/channel_callbacks.rb \
  lib/volcano/realtime/channel_lifecycle.rb \
  spec/volcano/realtime_spec.rb
```

Then commit:

```bash
git add \
  lib/volcano/realtime.rb \
  lib/volcano/realtime/channel_callbacks.rb \
  lib/volcano/realtime/channel_lifecycle.rb \
  spec/volcano/realtime_spec.rb
git commit -m "feat(realtime): resume broadcast subscriptions"
```

---

### Task 5: Close lifecycle races without expanding into Postgres

**Files:**
- Modify: `lib/volcano/realtime/channel_callbacks.rb`
- Modify: `lib/volcano/realtime/channel_lifecycle.rb`
- Test: `spec/volcano/realtime_spec.rb`

**Interfaces:**
- Consumes: the callback generation and `before_delivery` admission from Task 4.
- Produces: duplicate-free explicit unsubscribe/resubscribe and user-lineage isolation for broadcast positions.
- Does not modify `postgres_delivery.rb`, `postgres_batch.rb`, `postgres_changes.rb`, or `postgres_expansion.rb`.

- [ ] **Step 1: Write a failing stale-generation callback test**

Hold an unsubscribe request inside the lifecycle semaphore. Deliver broadcast
offset 2 so its callback waits for that semaphore. Complete unsubscribe, which
detaches the handler and increments its generation. Assert that the old callback
does not run after it resumes.

- [ ] **Step 2: Run the stale-generation test and verify RED**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec \
  spec/volcano/realtime_spec.rb \
  --example 'subscription expires before callback dispatch'
```

Expected: the stale callback receives offset 2.

- [ ] **Step 3: Write a failing explicit-resubscribe duplication test**

Block the offset-2 callback, queue offset 3, unsubscribe, then resubscribe with
offset 3 in the server's retained batch. Release the old callback and assert
that values are exactly `[2, 3]`, not `[2, 3, 3]`. The generation check must
suppress any old queued copy invalidated by unsubscribe.

- [ ] **Step 4: Write a failing authenticated-user lineage test**

Establish `epoch-1`/offset 2 as one user, lose the socket, sign in as a different
user before restoration, and assert that the replacement subscribe requests
initial recovery without the previous epoch or offset. A token refresh for the
same user lineage must retain the cursor.

- [ ] **Step 5: Implement the minimal lifecycle rules and verify GREEN**

Snapshot the protocol position before handler detachment on transport loss and
explicit unsubscribe. Detach the handler and increment the generation during a
successful explicit unsubscribe for broadcast channels only. In
`recovery_position`, compare the current protocol session lineage to
`@stream_lineage`; clear the position only when the lineage changes.

Do not change Postgres worker shutdown or queue ownership in this task. The
broadcast callback admission is a separate branch from the existing presence
and Postgres path. Those channel types must retain their current delivery and
handler-lifecycle behavior when `recovery` is `nil`.

- [ ] **Step 6: Run full realtime verification and commit**

Run:

```bash
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec \
  spec/volcano/realtime/protocol_spec.rb spec/volcano/realtime_spec.rb
/opt/homebrew/bin/bundle exec rubocop --parallel
```

Then commit:

```bash
git add \
  lib/volcano/realtime/channel_callbacks.rb \
  lib/volcano/realtime/channel_lifecycle.rb \
  spec/volcano/realtime_spec.rb
git commit -m "fix(realtime): scope broadcast recovery delivery"
```

---

### Task 6: Document, verify, and open the broadcast-only pull request

**Files:**
- Modify: `README.md`
- Verify only: `tests/fixtures/sdk-contract-dry-run.json`
- Verify only: `/Users/sean.keever/.codex/worktrees/093c/volcano-hosting/tests/sdk-contract`

**Interfaces:**
- Documents: lifetime-only automatic broadcast recovery after unexpected reconnect and explicit resubscribe.
- Explicitly documents: Postgres publications are not recovered until the later slice; presence rebuilds its current snapshot.

- [ ] **Step 1: Update the focused realtime documentation**

Replace the sentence saying outage publications are not recovered with compact
language equivalent to:

```markdown
Unexpected transport loss reconnects with bounded exponential backoff and
restores active subscriptions. Broadcast channels recover retained publications
for the lifetime of this client and authenticated user. Recovery state is not
persisted across processes. Postgres channels do not recover missed
publications yet; presence channels rebuild their current snapshot.
```

- [ ] **Step 2: Run every Ruby gate from a clean status snapshot**

Run:

```bash
npm ci
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" bin/check-openapi
/opt/homebrew/bin/bundle exec rubocop --parallel
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec rspec
chmod 600 tests/fixtures/sdk-contract-dry-run.json
VOLCANO_SDK_CONTRACT_FIXTURE="$PWD/tests/fixtures/sdk-contract-dry-run.json" \
  PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  /opt/homebrew/bin/bundle exec cucumber \
  features/contract --dry-run --strict --format progress
PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  gem build volcano-sdk.gemspec
git diff --check
git status --short
```

Expected: dependency audit has zero vulnerabilities; OpenAPI is current;
RuboCop has zero offenses; RSpec has zero failures; all 13 contract scenarios
and 66 steps are discovered; the gem builds; only intended source, test, docs,
spec, and plan changes appear in status.

- [ ] **Step 3: Run the Hosting contract guards**

From `/Users/sean.keever/.codex/worktrees/093c/volcano-hosting`, run:

```bash
npm test --prefix tests/sdk-contract
bash scripts/ci/run-sdk-contract-tests_test.sh
```

Expected: all contract unit tests and shell cases pass. Do not run the stateful
live contract runner against staging or production.

- [ ] **Step 4: Audit the scope against the base branch**

Run:

```bash
git diff --stat origin/main...HEAD
git diff --name-only origin/main...HEAD
git log --oneline origin/main..HEAD
```

Expected: no Postgres delivery implementation, OpenAPI, generated code, shared
Gherkin, or Hosting file is changed. If any appears, remove it before review.

- [ ] **Step 5: Commit documentation and push**

```bash
git add README.md
git commit -m "docs(realtime): describe broadcast recovery"
git push -u origin skeever/realtime-recovery-broadcast
```

- [ ] **Step 6: Open a draft pull request**

Use the title:

```text
feat(realtime): recover missed broadcasts
```

Use this scope anchor in the body:

```text
Recover retained broadcast publications across reconnects using internal
Centrifugo epoch/offset state while preserving existing public callbacks;
exclude Postgres recovery, presence replay, persistent cursors, OpenAPI, and
public API changes.
```

Include the native and Hosting verification results. Keep the pull request a
draft during automated review.

- [ ] **Step 7: Run the Codex review loop**

Select Codex only. On each current head, post exactly one top-level comment:

```text
@codex review
```

Validate every finding against the scope anchor. For each valid in-scope
finding, first add a focused failing regression test, then make the smallest
root-cause fix, rerun the full Ruby and Hosting gates, commit, push, and request
the next round. Stop after a fifth round containing findings and request human
reassessment; never silently begin a sixth round.

- [ ] **Step 8: Make ready, merge, and verify `main`**

Only after current-head CI passes, every review thread is resolved, and Codex
completes with no findings:

```bash
gh pr ready
gh pr merge --squash --delete-branch
git fetch origin main
```

Verify the pull request reports `MERGED` and its merge commit is an ancestor of
`origin/main`. Then begin Slice 2 from a new branch and worktree based on that
updated `origin/main`.
