# Live updates

## What it does

When a watched property's price or status changes, every open tab of each user watching it
updates the card in place within about a second and shows a toast such as
"12 Smith St: $850k → $820k". Each change is also logged in `property_events`. A dot by the user's
name shows the socket state ("Live", "Connecting…", "Offline"). Rake tasks change properties on
demand so the feature can be seen without an admin screen (steps in the README, "Trying the live
updates").

## Where the code is

| File | Role |
| ---- | ---- |
| `api/app/models/property.rb` | `after_update` writes the event rows; `after_update_commit` calls the notifier |
| `api/app/services/property_change_notifier.rb` | Finds the watchers, builds the message, broadcasts inline |
| `api/app/channels/watchlist_channel.rb` | One stream per user; no actions |
| `api/app/channels/application_cable/connection.rb` | Socket auth (see [auth.md](auth.md)) |
| `api/app/resources/property_resource.rb` | The property shape, including `version` (`lock_version`) |
| `api/lib/tasks/demo.rake` | `demo:watched`, `demo:change_property[id,price=…\|status=…]`, `demo:simulate_changes` |
| `web/src/features/watchlist/useWatchlistChannel.ts` | Subscribes while signed in (mounted once in `RootLayout`); applies updates, toasts, handles reconnects |
| `web/src/features/properties/cache.ts` | `applyPropertyUpdate`, `cancelListsHolding`, `findCachedProperty`; each covers the open property page too |
| `web/src/features/properties/format.ts` | `describeChanges`, `formatCompactPrice` for the toast |
| `web/src/lib/cable.ts`, `cableStatus.ts` | The consumer; the status atom for the header dot |
| `web/src/test/cable.ts` | The fake consumer used by the web tests |

Message: `{ type: "property.updated", property: <REST shape, watched: true>, changes: { priceCents?: [old, new], status?: [old, new] } }`.
A save that changes both price and status writes two event rows and sends one message.

## Rules that must stay true

- **The event row is written inside the save's transaction** (`after_update`); **watchers are told
  only after commit** (`after_update_commit`). A rolled-back change is neither logged nor broadcast.
- **Both callbacks are guarded by `saved_change_to_price_cents? || saved_change_to_status?`.** In
  after-callbacks `*_changed?` is already false.
- **Every write that should notify goes through `update!`** (rake tasks now, admin later). One save
  per transaction (see [property-data.md](property-data.md)).
- **The client applies an update only to cached cards with an older `version`,** checked per cached
  copy. A late or repeated message must never put an older price back.
- **The property page updates too:** the same version check, then a refetch for its history (see
  [property-detail.md](property-detail.md)). A reconnect refetches an open property page.
- **The patch keeps the card's own `watched` flag.** A watch click still in flight decides that,
  not the broadcast.
- **A broadcast failure never fails the save.** The change is committed; the error is reported and
  watchers see it on their next refetch.
- **The message reuses the REST shape,** so the client drops it straight into its cache. A change to
  `PropertyResource` changes both.

## Decision log

- **2026-11-22: One stream per user, not one per property.** One subscription however many
  properties are watched, and a user can only ever receive their own stream.
- **2026-11-22: Broadcast inline, no background job.** Each broadcast is a ~1 ms Redis publish, and
  inline sends also work from rake tasks and the console, which exit right after.
  _Rejected for now:_ a Solid Queue job with retries; worth it once fan-out grows.
- **2026-11-25: `version` = `lock_version`, in REST and in the message.** Rails bumps it on every
  save, so it orders updates with no extra column.
- **2026-11-25: The version gate is per cached card,** not one "last seen version" per property, so
  search and the watchlist can hold different versions and each still updates correctly. A small
  per-tab record of announced versions stops a repeated message toasting twice when no list holds
  the card.
- **2026-11-25: Toast every new version once per tab, even when no list on that tab holds the
  card;** never for a message older than what the tab already shows.
- **2026-11-25: Cancel list fetches already loading before patching,** as the watch toggle does, so
  an older response can't land on top. A list still on its *first* load is left alone: cancelling it
  left the page stuck on skeletons (found in QA).
- **2026-11-25: After a *re*connect, refetch the watchlist and mark search batches stale** (refreshed
  on their next view, not all at once), since messages sent while offline are gone. A live update
  arriving mid-refetch restarts that refetch rather than cancelling it.
- **2026-11-25: The status dot reads "Offline" when the server refuses the socket** (for example,
  an expired cookie), and "Connecting…" while ActionCable retries by itself. No toast for
  connection changes; they would be noise.
- **2026-11-25: Close prices are written in full** ("$2,005,000 → $2,000,000") when the short forms
  would read the same.
- **2026-11-25: `subscribed` is private.** Every public channel method is an action a client can
  `perform`; a public `subscribed` would let it stream the same updates twice.
- **2026-11-25: A card that no longer matches the filters stays** (with its new badge) until the
  next refetch, rather than vanishing under the cursor.
- **2026-11-25: `demo:watched` added** so the README can point at a real id instead of a
  placeholder (seed ids change on every reseed).

## Known gaps

- A sign-out anywhere disconnects the user's sockets everywhere; other devices reconnect and
  refetch, which is harmless.
- An open socket outlives its token (see [auth.md](auth.md)).
- Writes that skip callbacks (`update_all`, `update_columns`) don't notify anyone.

## How to check it

- API: `spec/models/property_spec.rb` (event rows, after-commit, rollback),
  `spec/services/property_change_notifier_spec.rb`, `spec/channels/watchlist_channel_spec.rb`,
  `spec/tasks/demo_spec.rb`.
- Web: `web/src/features/watchlist/watchlistChannel.test.tsx`.
- By hand: README, "Trying the live updates".
