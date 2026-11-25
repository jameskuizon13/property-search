# Watchlist

## What it does

A signed-in user can watch or unwatch any property from its card, and see their watched
properties on `/watchlist`, newest added first. The button changes at once; a failed request puts
it back with a toast. Signed-out users who click Watch go to log in and come back to the same page.
Live price and status updates for watched properties are in [live-updates.md](live-updates.md).

| Endpoint | Result |
| -------- | ------ |
| `GET /api/v1/watchlist` (`cursor`, `limit`) | Watched properties, newest added first; same shape and envelope as search, every row `watched: true` |
| `PUT /api/v1/watchlist/:propertyId` | 201 when added, 200 when already watched; both return the property. Unknown property → 404 |
| `DELETE /api/v1/watchlist/:propertyId` | 204, whether or not it was watched |

All three need sign-in (401); the writes also need the `Origin` check (403).

## Where the code is

| File | Role |
| ---- | ---- |
| `api/app/controllers/api/v1/watchlist_controller.rb` | The three actions, the id format check, the PUT retry |
| `api/app/queries/watchlist/list_query.rb`, `cursor.rb` | The user's list in one query; its own signed cursor `[created_at µs, item id]` |
| `api/app/models/watchlist_item.rb` | Append-or-delete rows; both FKs cascade |
| `api/db/migrate/*_create_watchlist_items.rb`, `*_add_watchlist_items_user_created_at_index.rb` | Unique `(user_id, property_id)`, `(property_id)`, `(user_id, created_at DESC, id DESC)` |
| `web/src/features/watchlist/WatchButton.tsx`, `useToggleWatch.ts` | The toggle: optimistic, queued per property, rollback |
| `web/src/features/watchlist/WatchlistPage.tsx`, `useWatchlist.ts`, `api.ts` | The page, on the shared `InfiniteResults` |
| `web/src/features/properties/cache.ts` | `patchCachedProperty`: one property updated in every cached list |

## Rules that must stay true

- **Every lookup goes through `current_user`** (`current_user.watchlist_items` or `ListQuery`
  scoped the same way). That is what makes IDOR impossible; a `user_id` param is ignored.
- **Endpoints are keyed on the property, never a watchlist-item id,** so the toggle is idempotent
  and the client never needs an item id.
- **Property ids must be plain positive integers** (up to 19 digits), and the routes have
  `format: false`. Otherwise `12abc` or `12.0` would act on property 12.
- **The list is not limited to active listings:** a watched property that sells stays, with its
  new badge.
- **Each click sends the state it wants, not "toggle",** and clicks for one property share a
  mutation `scope`, so they run in click order and the last click wins.
- **Cancel in-flight list fetches before patching the cache.** A fetch that started before the
  click copied the old pages and would write them back over it.

## Decision log

- **2026-11-22: `PUT`/`DELETE` keyed on the property.** Idempotent, and the client needs no item id.
  _Rejected:_ `POST /watchlist` + `DELETE /watchlist/:itemId` (not idempotent; needs the item id).
- **2026-11-25: `PUT` uses `create_or_find_by!`.** Insert first; on the unique index, return the
  existing row. Two racing PUTs both succeed instead of one getting a 500. Cost: each repeat PUT
  uses up a sequence value and logs a `duplicate key` line in Postgres.
- **2026-11-25: Retry a PUT once** when a DELETE removes the row between `create_or_find_by!`'s
  failed insert and its lookup (a fast unwatch/watch), instead of answering 404.
- **2026-11-25: The watchlist cursor has its own signing key,** so a search cursor is a 422 here.
  Another user's cursor only marks a position in your own list, so it leaks nothing.
- **2026-11-25: `(user_id, created_at DESC, id DESC)` index** serves the list order and the cursor
  condition with no sort. Checked by hand with 20k rows; the seed makes no watchlist rows, so there
  is no committed plan.
- **2026-11-25: Optimistic toggle across every cached list,** rolled back to the last state the
  server *confirmed*, and only when no later click is queued.
- **2026-11-25: Unwatching on `/watchlist` keeps the card in place** (now showing "Watch", so one
  click undoes it) and marks the list stale; it refreshes on the next visit.
  _Rejected:_ removing the card at once (it vanishes under the cursor, and undo is lost).
- **2026-11-25: No toast for a successful watch;** the button changing is the feedback. Failures
  toast, including a rate-limited click (429).
- **2026-11-25: The button is a toggle (`aria-pressed`)** whose accessible name starts with its
  visible text ("Watch"/"Watching") and then the address.

## Known gaps

- Repeat PUTs burn sequence values and log a `duplicate key` line (see above).
- Writes are limited to 60 per minute per user ([performance.md](performance.md)).

## How to check it

- API: `spec/requests/api/v1/watchlist_spec.rb` (401, 403, IDOR, idempotency, the simulated race,
  cursor walks, query count), `spec/queries/watchlist/list_query_spec.rb`, `cursor_spec.rb`,
  `spec/models/watchlist_item_spec.rb`.
- Web: `web/src/features/watchlist/watchlist.test.tsx` (optimistic update, rollback, three fast
  clicks ending in the third click's state).
