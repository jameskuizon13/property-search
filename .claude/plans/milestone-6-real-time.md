# Milestone 6 — Real-time: implementation plan

Branch: `feature/milestone-6-real-time` (off `main` at 3baefaf, Milestone 5 merged).
Source of truth: PRD "Real-time design (ActionCable)", FR-6, Testing strategy, Delivery plan → Milestone 6.

## Goal

When a watched property's price or status changes (rake task now, admin screen in Milestone 8),
every open tab of every watcher updates the card in place within ~1 s and shows a toast. Updates
apply in order by `version` (`lock_version`), and each change is logged in `property_events` in
the same transaction.

## API (`api/`)

1. **`version` in the REST shape.** `PropertyResource` gets `attribute(:version) { |p| p.lock_version }`.
   Search (`properties.*`) and the watchlist query (`properties.*`) already select `lock_version`.
   The property request specs and the watchlist spec assert `version` is present.

2. **`Property` callbacks** (`app/models/property.rb`), exactly as the PRD sketches:
   - `after_update :record_change_events, if: :price_or_status_changed?` — inside the save's
     transaction. Writes one `price_changed` row (`from_value`/`to_value` = old/new cents as strings,
     `nil` for withheld) and/or one `status_changed` row, from `saved_change_to_price_cents` /
     `saved_change_to_status`. Both changed in one save → two rows. Uses `property_events.create!`
     so a failure rolls the whole save back.
   - `after_update_commit :notify_watchers, if: :price_or_status_changed?` → `PropertyChangeNotifier.call(self)`.
   - `price_or_status_changed? = saved_change_to_price_cents? || saved_change_to_status?`.
   - `Property#change_price!(cents)` helper? **No** — keep the model small. The rake tasks set
     `price_cents` and `price_display` together (see 5), and Milestone 8's form sends both.

3. **`PropertyChangeNotifier`** (`app/services/property_change_notifier.rb`), plain class with `self.call(property)`:
   - Payload: `{ type: "property.updated", property: PropertyResource.new(property, params: { watched: true }).to_h, changes: { priceCents: [old, new], status: [old, new] } }`
     (only the keys that changed; camelCase like every JSON key). `changes` is read from
     `property.saved_changes` while still in the commit callback.
   - Watchers: `User.where(id: WatchlistItem.where(property_id: property.id).select(:user_id)).find_each`
     — one query per 1,000 watchers, served by the `watchlist_items(property_id)` index — then
     `WatchlistChannel.broadcast_to(user, payload)` inline (no job; PRD Stack decisions).
   - Wrapped in `Rails.error.handle(context: { property_id: })` so a Redis outage after commit is
     reported but never turns a saved change into a 500 (same pattern as logout). The change and its
     event row are already committed; watchers pick it up on their next refetch.

4. **`WatchlistChannel`** (`app/channels/watchlist_channel.rb`): `subscribed { stream_for current_user }`.
   The connection already rejects anonymous users; the channel also calls `reject` if
   `current_user` is nil (defence in depth). No params accepted. Clients never send anything.

5. **Rake tasks** (`lib/tasks/demo.rake`), all using `update!` so callbacks fire:
   - `demo:change_property[id,change]` where `change` is `price=820000` (whole dollars, sets
     `price_cents` and `price_display` via `Property.format_price`), `price=withheld` (nil +
     "Contact agent"), or `status=sold|under_offer|for_sale|withdrawn`. Bad id / bad input →
     `abort` with a one-line usage message (non-zero exit), no stack trace. Prints the change and
     how many watchers were notified.
   - `demo:simulate_changes` — picks `COUNT` (default 3) random **watched** properties
     (distinct `property_id` from `watchlist_items`) and gives each a random price move (±2–10%,
     rounded to $5,000; never below $50,000) or, 1 in 4, a status step (for_sale → under_offer → sold).
     Prints each change. "No watched properties yet" message if none.
   - `demo:watched[email]` (new, small) — lists the property ids + addresses a user watches
     (default `demo@example.com`), so the README can say how to find an id instead of the current
     "TODO: fill in a known id". Documented in the PRD's FR-6 bullet too.

## Web (`web/`)

6. **Types:** `Property.version: number`; `PropertyUpdatedMessage` type
   (`{ type: 'property.updated'; property: Property; changes: { priceCents?: [n|null, n|null]; status?: [s, s] } }`).
   MSW fixtures in `src/test/propertyHandlers.ts` gain `version`.

7. **Cable status atom** (`src/lib/cableStatus.ts` or in the hook file): Jotai
   `cableStatusAtom: 'disconnected' | 'connecting' | 'connected'`. A small header indicator in
   `RootLayout` when signed in: a dot + visually-hidden text ("Live updates on" / "Reconnecting…"),
   with `title` for sighted hover. No toast for connection changes (would be noisy).

8. **`useWatchlistChannel`** (`src/features/watchlist/useWatchlistChannel.ts`), mounted once in
   `RootLayout`:
   - Subscribes only when `useMe()` has a user; effect deps `[user?.id]`, cleanup unsubscribes.
     Signing out already calls `disconnectConsumer()`; signing in again creates a fresh consumer.
   - `received(message)`: ignore anything whose `type` isn't `property.updated` or that fails a
     light shape check. Version gate: apply only if `message.property.version` is greater than
     both the cached card's `version` (`findCachedProperty`) and the last version this client
     applied for that id (a per-QueryClient `Map<id, version>`, so a duplicate still drops when the
     card isn't cached anywhere). Applied → `patchCachedProperty(queryClient, id, patch)` with the
     **payload minus `watched`** (an in-flight unwatch click must not be undone by a broadcast that
     says `watched: true`), then a toast.
   - Toast text: `"12 Smith St: $850k → $820k"`, `"12 Smith St: For sale → Sold"`, both joined with
     `", "`. Compact price formatter (`$850k`, `$1.25m`, withheld → "Contact agent") added to
     `features/properties/format.ts` with unit tests. Tone `info`.
   - `connected()`: set status `connected`; on a **re**connect (not the first connect), invalidate
     `watchlistKeys.all` (refetch) and mark `propertyKeys.lists()` stale with `refetchType: 'none'`,
     so changes missed while offline are picked up (PRD step 7) without refetching every loaded
     search batch at once. `disconnected()` → `connecting` (ActionCable retries itself).
     `rejected()` → `disconnected`.
   - Cards whose new status no longer matches the filters stay in place with their new badge
     (falls out of patching in place; README already says so).

## Tests

- **Model** (`spec/models/property_spec.rb`): price change → one `price_changed` row with right
  from/to; status change → one `status_changed`; both → two; other column → none; failed save
  (invalid value) → no change and no event; withheld → `nil` value; `PropertyChangeNotifier`
  called only after commit and only for price/status changes (`expect(...).to receive(:call)`;
  plus not called when the transaction rolls back); `lock_version` bumps.
- **Notifier** (`spec/services/property_change_notifier_spec.rb`): `have_broadcasted_to(watcher)`
  for each watcher, not for a non-watcher; payload `type`, `property.version == lock_version`,
  `property.watched == true`, `changes` keys camelCase; Redis error is swallowed and reported.
- **Channel** (`spec/channels/watchlist_channel_spec.rb`): subscribes and `have_stream_for(user)`;
  rejects without a user.
- **Rake** (`spec/tasks/demo_spec.rb`): `change_property` price, withheld, status, bad id, bad
  status (abort / SystemExit); `simulate_changes` changes only watched properties; `watched`
  lists them.
- **Requests:** `version` present in search, watchlist and PUT responses.
- **Web** (`src/features/watchlist/watchlistChannel.test.tsx`): `vi.mock('@/lib/cable')` with a fake
  consumer capturing the subscription callbacks. A message patches the cached card's price and
  badge and shows the toast; an older or equal `version` is ignored with no toast; `watched` isn't
  overwritten; no subscription when signed out; unsubscribes on sign-out; reconnect invalidates
  the watchlist. Format tests for the compact price.

## Docs

- README: "Trying the live updates" — drop "(available from Milestone 6)", replace the id TODO with
  `bin/rails demo:watched`, add the Docker variant (`docker compose exec api bin/rails …`).
  Real-time design-decisions section: version gate, payload minus `watched`, error handling,
  reconnect behaviour, status indicator; State-management table: cable status atom now built.
  Build progress: tick Milestone 6. Known gaps: an open socket outlives its token (already listed);
  missed updates while offline only refresh the watchlist, search batches refresh on next view.
- PRD: FR-6 mentions `demo:watched`; anything else that changed during the build.

## Edge cases handled

Duplicate/late messages (version gate + seen-version map), both price and status in one save,
rollback → no broadcast and no event, Redis down after commit, withheld price, broadcast during an
in-flight watch toggle, sign-out while subscribed, reconnect, a sold card under active filters.

## Out of scope

Background job for the notifier (documented as "at scale"), re-checking token `exp` on an open
socket (Milestone 9 list), property detail page.

## Changes after plan review (APPROVE WITH CHANGES)

1. Version gate per cached card: a version-aware `patchCachedProperty` replaces only cards with
   `version < incoming`, returns whether anything changed; toast only when it did. The seen-version
   map is dropped (a message for an uncached card applies nothing and shows no toast, per PRD).
2. `await cancelQueries` on property lists + watchlist before patching (as `useToggleWatch` does),
   so an in-flight batch can't write the old price back over the patch.
3. Use ActionCable's own args: `connected({ reconnected })`, `disconnected({ willAttemptReconnect })`
   (false → `disconnected`); reset the status atom in the effect cleanup.
4. Shared fake consumer `web/src/test/cable.ts`, used by auth/search/watchlist tests and the new test.
5. Notifier spec uses `have_broadcasted_to(user).from_channel(WatchlistChannel)`.
6. Explicit after-commit spec (not called inside the transaction, called after; not on rollback).
7. Rake: withheld price takes the status step; minimum $5,000 move; strict `Integer()` parsing;
   load tasks once, `reenable` before invoke, assert `SystemExit` + stderr usage.
8. PRD edits named: payload `changes` keys camelCase with `status`; callback name; `demo:watched`.
