# Milestone 7 — Performance & bonus: implementation plan

Branch: `feature/milestone-7-performance`, stacked on `feature/milestone-6-real-time` (its PR is
not merged yet; the PR says so). Source: PRD Stack decisions (rate limit / cache), Non-functional
requirements (Rate limiting, HTTP caching, App caching), FR-3 (optional virtualisation), Delivery
plan → Milestone 7.

## What already exists (checked in the code)

- rack-attack with `api/ip` (300 / 5 min) and `auth/ip` (10 / min), its own store (Redis; MemoryStore
  in test), keyed by `ClientIp` (ignores spoofed X-Forwarded-For). Shared 429 JSON + `Retry-After`.
- `Rack::ETag` and `Rack::ConditionalGet` are already in the API middleware stack, so search already
  gets a body-hash weak ETag and 304s. That saves bandwidth but still runs every query.
- `Rails.cache` is Redis in dev/prod, `:null_store` in test.
- `totalCount` runs a `COUNT` on the first batch of every search, uncached.

## API

1. **Per-route throttles** (`config/initializers/rack_attack.rb`):
   - `search/ip`: `GET /api/v1/properties`, 120 / min per `client_ip`. (Burst limit; `api/ip`
     still caps the sustained rate at 60/min on average.)
   - `watchlist/user`: `PUT`/`DELETE /api/v1/watchlist/*`, 60 / min per **user**, keyed
     `"user:#{AuthToken.decode(cookie)}"` (signature + expiry check only, no DB query in the
     middleware). No valid token → no key (the request 401s anyway; `api/ip` still counts it).
   - Throttle names follow the existing `scope/discriminator` style. Same responder.
2. **Search cache version** (`app/models/search_cache.rb`, plain module): `SearchCache.version`
   reads `search_cache_version` from `Rails.cache` (generating a random token when missing);
   `SearchCache.bump!` writes a fresh token. `Property` gets
   `after_commit :bump_search_cache, on: %i[create update destroy]` (every change may move counts
   or results). The seed calls `SearchCache.bump!` after its `insert_all` (which skips callbacks).
3. **Cached `COUNT`** (`Properties::SearchQuery#total_count`): `Rails.cache.fetch(["search-count",
   SearchCache.version, count_key], expires_in: 60.seconds) { filtered.count }`, where `count_key`
   is a digest of the *parsed* filters that affect the count (`q` downcased, prices, beds, sorted
   types, the two toggles, and whether the sort is a price sort since price sorts drop withheld
   prices). Not keyed by cursor, limit or user. Short-circuit stays: a first batch that holds every
   row uses its size.
4. **ETag that skips the query** (`PropertiesController#index`): before running the search,
   `return unless stale?(etag: [ETAG_SCHEMA, SearchCache.version, watchlist_fingerprint, normalised
   search params], weak_etag: true, public: false)`. `watchlist_fingerprint` is
   `current_user.watchlist_items.pick(Arel.sql("COUNT(*), MAX(created_at)"))` (one indexed query;
   any watch/unwatch changes it; `nil` when signed out). Params are validated first (invalid → 422
   as now). `ETAG_SCHEMA` is a constant to bump if the response shape changes. Cache-Control stays
   `max-age=0, private, must-revalidate` (Rails default for `stale?` with `public: false`).
   A 304 runs only the user lookup and the fingerprint query.
5. **Property types**: `expires_in 1.hour, public: true` on `GET /property_types` (a constant list;
   HTTP caching beats a Redis copy of a Ruby constant). **Deviation from PRD** "Redis cache for the
   property-type list", documented.

## Web

6. **429 wording**: `ErrorState`'s hint for a 429 ("Too many searches. Wait a moment, then
   retry."); the watch toggle's rollback toast for a 429 ("You're changing your watchlist too
   quickly. Try again in a moment."). No automatic retry (4xx already isn't retried).
7. **Rendering cost of long lists — not TanStack Virtual.** FR-3 makes virtualisation optional.
   Proposal: `content-visibility: auto` + `contain-intrinsic-size: auto 420px` on each result `<li>`,
   so the browser skips layout and paint for off-screen cards, while every card stays in the DOM
   and the accessibility tree. Why not TanStack Virtual: a responsive 1/2/3-column grid needs
   row chunking and measurement, it fights router scroll restoration on Back, removes off-screen
   cards from find-in-page and screen-reader list counts, and every existing list test would need
   a layout mock. Remove the unused `@tanstack/react-virtual` dependency; README and PRD explain
   the choice and say when real virtualisation would be worth it (thousands of cards).

## Tests

- `rate_limit_spec.rb`: 121st search in a minute → 429 + `Retry-After` + shared shape; another IP
  unaffected; 61st watchlist write by one user → 429 while another user (same IP) still passes;
  GETs on the watchlist and the 60 writes' different properties all count; an invalid cookie isn't
  keyed by user.
- `properties_spec.rb` (with `Rails.cache` stubbed to a `MemoryStore`): second identical request
  with `If-None-Match` → 304 and no `properties` query (count SQL with
  `ActiveSupport::Notifications`); ETag changes after a property update, after watch/unwatch, after
  sign-in, and between different filters; invalid params still 422 (not 304). Count cached: second
  first-batch request runs no `COUNT`; a property update makes the next one recount; different
  filters don't share a count; `q` differing only in case shares it.
- `property_types_spec.rb`: `Cache-Control` public with max-age.
- `SearchCache` spec: version stable until bumped; create/update/destroy bump it; a rolled-back
  change doesn't.
- Web: `ErrorState` 429 wording on search; watch toggle 429 toast; the `<li>` has the
  `content-visibility` class (light check).

## Docs

README: N+1/rate limiting/caching section rewritten (throttles table, cache keys, ETag flow and
what a 304 costs, why not virtualisation), Stack row (drop TanStack Virtual), Build progress tick.
PRD: NFR Rate limiting/HTTP caching/App caching rows, FR-3 optional bullet and Frontend architecture
virtualisation bullet updated to the decision, Stack decisions row.

## Edge cases

Spoofed `X-Forwarded-For` (reuses `ClientIp`); expired/tampered cookie on writes; ETag must vary by
user and by watchlist state; 304 must never hide a validation error; cached count after reseed
(bumped in seeds); `Rails.cache` down (fetch raises → let it be a 500? No: `RedisCacheStore`
swallows connection errors by default and returns nil/misses, so search still works uncached).

## Changes after plan review (APPROVE WITH CHANGES)

1. `stale?(etag: [...])` only — `weak_etag: true` makes Rails digest `true` (verified in
   actionpack 8.1 `fresh_when`: `weak_etag ||= etag || object`), so every search would share one ETag.
2. ETag includes `current_user&.id`; watchlist fingerprint is `COUNT(*), MAX(id)` (sequence ids,
   not app-clock `created_at`). Same-user concurrent commits colliding → known gap.
3. `SearchCache` version key gets a TTL (15 min) to cap staleness after a Redis outage; a failed
   `bump!` write is reported with `Rails.error.report`. Seeds bump unconditionally at the end.
4. rack-attack reads `req.cookies["auth"]` (string key); check method + path before decoding.
5. `ErrorState` is shared with the watchlist: generic 429 wording ("Too many requests…").
6. `SearchQuery` exposes one normalised key (`cache_key_parts`) from parsed values: defaulted limit,
   cursor, sort, sorted/deduped types, dropped short `q`; `q` not downcased.
7. `contain-intrinsic-size` tuned to the measured card height; check Back to search by hand; docs
   say "not virtualised; content-visibility instead".
8. Specs: watchlist GETs don't count toward `watchlist/user`; writes via `DELETE`; search throttle
   with a cheap 422; two users with empty watchlists get different ETags; cursor/limit change the ETag.
Optional taken: note that `update_all`/`insert_all`/`delete` skip the bump (+ a spec documenting it);
README Docker shared-bucket note includes search; 429 toast uses `Retry-After` if cheap.
