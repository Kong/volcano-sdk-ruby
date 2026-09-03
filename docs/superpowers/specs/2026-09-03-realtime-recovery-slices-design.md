# Ruby Realtime Recovery Slices Design

## Context

Ruby realtime subscriptions reconnect after an unexpected transport loss, but
they do not ask Centrifugo to replay publications sent during the outage. Draft
PR #81 attempted recovery for broadcast, presence, and Postgres channels in one
change. Its review exposed coupling between protocol offsets, callback
lifecycles, and asynchronous Postgres row expansion. The draft grew to 15 files
and 1,339 added lines before it was closed.

The discarded draft remains a test and implementation reference. New changes
must be implemented from `main` with test-first development; they must not be
copied wholesale from the draft.

## Goals

- Recover missed broadcast and Postgres publications after an unexpected
  reconnect using Centrifugo epoch and offset state.
- Deliver recovered publications before later live publications.
- Advance a recovery cursor only when its publication is admitted for delivery
  to the current subscription generation.
- Preserve the existing public Ruby facade and callback payloads.
- Keep every pull request independently correct, reviewable, and safe for the
  Hosting SDK contract workflow.

## Non-goals

- Persistent recovery state across processes or `Volcano::Client` instances.
- A public history, replay, cursor, or recovery API.
- Changes to `api/openapi.yaml` or generated REST code.
- A second OpenAPI or payload validator.
- Replaying presence join and leave events. Presence reconnects rebuild the
  authoritative snapshot instead.
- Changing live callback queue capacity or promising unbounded recovery.
- Publishing the gem or changing repository visibility.

## Contract impact

The existing shared requirement `SDK-REALTIME-001` remains unchanged. Recovery
is internal transport behavior and does not change the public facade or its
cross-language scenario. Each slice therefore uses native Ruby tests and runs
the existing Hosting SDK contract guards without editing their fixtures or
canonical Gherkin.

## Slice 1: Broadcast recovery foundation

Only broadcast channels request replay in this slice. Presence and Postgres
channels retain their behavior from `main`.

The protocol subscribe command accepts an internal recovery position. When a
broadcast channel has no position, it asks for a recoverable subscription. Once
the server supplies an epoch and offset, the channel retains that immutable
position for the lifetime of the client and authenticated user lineage.
Unexpected reconnect and explicit unsubscribe/resubscribe may reuse it. A new
authenticated user lineage clears it.

Subscription replies may contain recovered publications. The protocol queues
those publications before completing the subscription reply so the existing
frame reader cannot deliver later live pushes first. Initial recovery uses the
first recovered offset minus one as its starting cursor; this prevents the
first retained batch from replaying repeatedly.

Protocol publication callbacks carry an internal context containing the
publication metadata and subscription generation. Immediately before invoking
the user's callback, the channel acquires its existing callback and lifecycle
serialization boundaries, confirms that the generation is still current, and
then advances the protocol position. If unsubscribe invalidates the generation
first, neither the cursor nor the stale callback advances.

If the bounded protocol callback queue rejects a live publication, the protocol
records a gap for that channel. Later offsets cannot move the cursor past that
gap. Recovered publications apply backpressure rather than being rejected by
the live queue limit, because discarding a recovery batch would leave the
connection healthy while silently losing its missed events.

The slice documents lifetime-only broadcast recovery and explicitly excludes
persistence and Postgres recovery.

## Slice 2: Postgres worker-generation isolation

This is an internal prerequisite and does not enable Postgres recovery.

Every Postgres subscription generation owns a distinct bounded delivery queue
and worker. Teardown detaches that queue and worker atomically, drains pending
work, and sends the stop marker only to the detached queue. A replacement
subscription cannot consume an older generation's stop marker, and an older
worker cannot consume a replacement generation's request.

Unsubscribe and channel removal mutate subscription state while holding the
lifecycle lock, then wait for the detached worker only after releasing that
lock. Workers may therefore finish their generation checks without a lock
cycle. Callback-triggered unsubscribe remains safe because a worker never waits
for itself.

Tests cover unsubscribe versus a completing fetch, removal versus a completing
fetch, and immediate resubscription with an old worker still exiting. Existing
ordered batching, queue limits, session isolation, and callback behavior must
remain unchanged.

## Slice 3: Postgres recovery

Postgres channels opt into the recovery foundation only after slice 2 has
merged. Recovered publications use the existing Postgres delivery queue so
lightweight row expansion and callbacks remain ordered.

A valid publication with no matching listener, or an invalid publication that
requires no user callback, enters the same queue as a checkpoint-only request.
That cursor update cannot overtake an earlier row fetch. Queue rejection marks
a recovery gap; recovered entries use backpressure so a retained batch is not
silently truncated.

The worker advances the cursor immediately before dispatching callbacks for the
current generation. Transport loss, unsubscribe, removal, or an authenticated
user change invalidates old work and prevents its cursor or callbacks from
crossing into the replacement generation.

The README then describes lifetime-only recovery for broadcast and Postgres
channels. Presence continues to rebuild its current snapshot on reconnect.

## Error and lifecycle behavior

- Server subscribe failures remain `Volcano::Realtime::ServerError` instances.
- A failed recovery attempt follows the existing bounded reconnect loop.
- An epoch mismatch is handled by the server's subscribe result; the SDK does
  not invent a second history protocol.
- Recovery state never survives a client process or authenticated-user lineage.
- Explicit channel removal clears the in-memory cursor with the channel.
- Existing callback exception isolation remains unchanged.

## Verification and review gates

Every slice follows red-green-refactor and must pass:

- `npm ci`
- `PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" bin/check-openapi`
- `/opt/homebrew/bin/bundle exec rubocop --parallel`
- `PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH" /opt/homebrew/bin/bundle exec rspec`
- Contract discovery against `tests/fixtures/sdk-contract-dry-run.json`
- `gem build volcano-sdk.gemspec`
- `npm test --prefix tests/sdk-contract` in `volcano-hosting`
- `bash scripts/ci/run-sdk-contract-tests_test.sh` in `volcano-hosting`

Each slice gets a separate draft pull request and a fresh Codex review cycle of
at most five rounds. Valid findings receive focused regression tests and
root-cause fixes. If round five still finds issues, work stops for another human
scope reassessment. A slice becomes ready and merges only after current-head CI
and Codex review are both clean.

After each merge, the next branch starts from the newly fetched Ruby `main`.
No Hosting source or SDK reference changes are required for these native
implementation slices.
