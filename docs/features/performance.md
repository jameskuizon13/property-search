# Performance: rate limits, caching and long lists

## What it does

Keeps the API cheap under load and the result list cheap to render: rate limits on every API
route, cached search counts, HTTP caching, automatic N+1 detection in the test suite, and result
cards that the browser skips laying out while they are off screen.

| Throttle | Limit | Keyed by |
| -------- | ----- | -------- |
| `api/ip` | 300 per 5 min, every `/api/*` request | client IP |
| `auth/ip` | 10 per min, `POST /api/v1/auth*` | client IP |
| `search/ip` | 120 per min, `GET`/`HEAD /api/v1/properties` (with or without `.json`) | client IP |
| `watchlist/user` | 60 per min, `PUT`/`DELETE /api/v1/watchlist/:id` | user id from the JWT |

Over a limit: 429, `{ "error": { "code": "rate_limited", … } }`, and `Retry-After`.

## Where the code is

| File | Role |
| ---- | ---- |
| `api/config/initializers/rack_attack.rb` | The four throttles, their store, the 429 responder |
| `api/lib/client_ip.rb` | The IP the throttles key on |
| `api/app/services/search_cache.rb` | The version token cached counts hang off |
| `api/app/queries/properties/search_query.rb` | `total_count`: the cached `COUNT` |
| `api/app/models/property.rb` | `after_commit :bump_search_cache` |
| `api/app/controllers/api/v1/property_types_controller.rb` | `expires_in 1.hour, public: true` |
| `api/config/environments/test.rb`, `Gemfile` | `bullet` with `Bullet.raise = true` |
| `web/src/index.css` (`offscreen-skip`), `web/src/components/ui/InfiniteResults.tsx` | `content-visibility` on result cards |
| `web/src/components/ui/states.tsx`, `web/src/features/watchlist/useToggleWatch.ts` | 429 wording on search and the watch toggle |

## Rules that must stay true

- **rack-attack has its own store** (Redis; `MemoryStore` in test). The test `Rails.cache` is a null
  store, so counters kept there would never count.
- **Throttles key on `ClientIp`, never `req.ip`,** which believes a client-supplied
  `X-Forwarded-For`.
- **Throttle rules match `req.path` as rack-attack hands it over,** already normalised by the
  router's own helper, so `/api/v1//properties/` shares a counter with `/api/v1/properties`. Don't
  normalise paths again by hand.
- **`watchlist/user` decodes the JWT without a DB query;** no valid token means no key (the request
  401s, and `api/ip` still counts it).
- **Cached counts are keyed by the parsed filters and `SearchCache.version`,** never by cursor,
  limit or user. Every property create, update or delete bumps the version after commit; the seed
  bumps it too.
- **A 304 must never serve a body from older code or data.** That is why search uses Rails' default
  body-hash ETag (see the decision log).
- **Card placeholder height must track the real card,** or Back lands on the wrong card. Only the
  height is set; a placeholder width widened the single phone column.

## Decision log

- **2026-11-22: rack-attack for every throttle.** Already scaffolded, already returns the shared
  JSON error. _Rejected:_ Rails 8 `rate_limit` (a second mechanism).
- **2026-11-25: `bullet` raises in the test suite,** so any request spec with an N+1 fails;
  `spec/config/bullet_spec.rb` proves it still raises.
  _Rejected:_ one hand-written query-count spec per endpoint (kept only where the count itself
  matters).
- **2026-11-25: `search/ip` counts `HEAD` and the `.json` suffix,** because both run the same query
  (found in QA).
- **2026-11-25: `watchlist/user` is per user, not per IP,** so one office or household doesn't share
  a bucket. Watchlist reads don't count.
- **2026-11-25: One cache version for all counts.** A single bump makes every cached count miss, with
  no need to know which searches a change affects. The key itself expires after 15 minutes, to cap
  staleness if Redis drops a bump; a failed bump is reported.
- **2026-11-25: Search ETag computed before the query, then dropped the same day.** It skipped the
  query on a 304, but only noticed code changes through a hand-bumped version or a deploy revision;
  forgetting either would answer 304 with a body cached under older code.
  _Chosen:_ Rails' default `Rack::ETag`, which hashes the rendered body. A 304 still saves the
  transfer, the query always runs, and an old body can never be reused.
  (`Cache-Control: private, max-age=0, must-revalidate`.)
- **2026-11-25: No list virtualisation; `content-visibility: auto` instead.** Off-screen cards skip
  layout and paint but stay in the DOM, in find-in-page and in the screen-reader list.
  _Rejected:_ TanStack Virtual. The responsive grid would need row chunking, it fights router scroll
  restoration, and it hides off-screen cards from find-in-page and assistive tech. Worth it at
  thousands of cards, not hundreds. The dependency was removed.
- **2026-11-25: The placeholder height is a formula** (a 3:2 photo as wide as the grid cell plus a
  190 px text block, from the list's width in container units), not a single measured value. A
  fixed value was off by most of a card on phones (found in QA).
- **2026-11-26: Removed the hand-written path normalising from the throttle rules.** rack-attack
  already does it; the specs now send raw requests through the whole app and fail if that
  normalisation is ever taken away.

## Known gaps

- If Redis loses a version bump, cached counts can be stale for up to 60 s.
- Writes that skip callbacks (`update_all`, `insert_all`, `delete`) don't bump the version; nothing
  outside the seed uses them on properties.
- In Docker Compose every browser shares one IP bucket (the Vite container is the peer); set
  `TRUSTED_PROXIES` in production.
- Fixed one-minute windows: up to twice a limit can land across a window boundary.
- Listing photos are WebP: cards load a 480×320 copy (~40 KB) through `srcset`, the property page
  the 960×640 one (~110 KB). The 31 files repeat across listings, so a long scroll loads each at
  most once (see [property-detail.md](property-detail.md)).

## How to check it

- API: `spec/requests/rate_limit_spec.rb`, `spec/requests/api/v1/search_caching_spec.rb`,
  `spec/services/search_cache_spec.rb`, `spec/requests/api/v1/property_types_spec.rb`,
  `spec/config/bullet_spec.rb`.
- Web: `web/src/features/properties/search.test.tsx` (429 wording, the `offscreen-skip` class),
  `web/src/features/watchlist/watchlist.test.tsx` (429 toast).
- By hand: scroll through several batches on search, open the watchlist, then press Back; the list
  comes back at the same card. Try it at phone width too.
