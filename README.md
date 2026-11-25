# Property Search

A small property search app, built for a fullstack coding challenge (3–4 h timebox).
Users search Australian listings, filter by price, bedrooms and property type, scroll through
results that keep loading, and save properties to a watchlist that updates live when a watched
property's price or status changes. The Docker Compose project is called `property-search`.

**Status: Milestones 1–4 are built** (auth and minimum security; property data and seeds; the search API; the watchlist API). The work is split into numbered **milestones**
(build steps that each end with something that runs, passing specs and an updated README; listed in [Build progress](#build-progress) and [PRD.md](PRD.md#delivery-plan-risks--open-questions)).
A label like _(Milestone 6)_ means that part is planned but not built yet. The full plan is in [PRD.md](PRD.md).

> The brief asked for Jest. Tests use **Vitest** (same API as Jest) with React Testing Library
> instead, because Vitest reuses the Vite config, so there is no separate Babel/SWC transform to maintain.

## Stack

| Part   | Stack |
| ------ | ----- |
| `api/` | Rails 8.1 (API mode), Ruby 3.4, Puma, PostgreSQL 17, Redis 7, ActionCable, `jwt`, Alba, rack-cors, rack-attack, bullet, RSpec + FactoryBot + shoulda-matchers |
| `web/` | Vite, React 19, TypeScript, TanStack Query, TanStack Router, zod, Jotai, `@rails/actioncable`, Tailwind 4, TanStack Virtual _(installed; used only if time allows, Milestone 7)_, Vitest + React Testing Library + MSW, oxlint |

Infra: Docker Compose (db, redis, api, web), a root `Makefile`, GitHub Actions CI (one job per app).

## Getting started

Both options run Postgres and Redis in Docker. Pick **Run it** (everything in Docker) to just
try the app. Pick **Develop** (Rails and Vite on your machine; recommended for coding) to work on it.
Either way, open **http://localhost:5173** (the web app). **http://localhost:3000/up** returning
200 means the API is healthy (port 3000 has no other routes yet).

| Port | Service | Open in a browser? |
| ---- | ------- | ------------------ |
| 5173 | Web (Vite) | **Yes, this is the app.** It proxies `/api` and `/cable` to Rails. |
| 3000 | API (Rails) | Only `/up` for a health check |
| 5432 | Postgres | No |
| 6379 | Redis | No |
| 5050 | pgAdmin (optional, `make pgadmin`) | Yes, to browse the database |

### Option A: Run it (everything in Docker)

**Who it's for:** reviewers who want to try the app without installing Ruby or Node.
You can still edit code (`./api` and `./web` are mounted into the containers), but file
reloads and tests are slower on macOS.

**Prerequisites:** Docker Desktop running, and ports 5432, 6379, 3000, 5173 free.

**Start / stop:**

```bash
make up                 # same as: docker compose up --build   (Ctrl-C to stop)
make down               # remove containers; keeps the database volume
```

The first start builds both images, installs gems and packages, and runs `bin/rails db:prepare`,
which creates the database and seeds it. Later starts reuse the existing database.

**How to know it worked:** `docker compose ps` shows all four services running (db and redis
`healthy`), http://localhost:3000/up returns 200, and http://localhost:5173 loads.

**Common commands** (in a second terminal, while `make up` is running):

```bash
docker compose exec api bin/rails console
docker compose exec api bin/rails db:seed:replant              # WIPES and reseeds
docker compose exec -e RAILS_ENV=test api bundle exec rspec    # RAILS_ENV=test is required, see below
docker compose exec api bin/rubocop
docker compose exec web pnpm test
docker compose exec web pnpm lint
docker compose exec web pnpm typecheck
docker compose logs -f api                                     # follow one service's logs
```

The api container sets `RAILS_ENV=development`, and `spec/rails_helper.rb` only defaults to
`test` when it is unset, so without `-e RAILS_ENV=test` rspec would run against the dev database.

**Troubleshooting:**

- **Added a gem or package and the container can't find it:** run `docker compose up --build`.
  Gems and `node_modules` live in named volumes (`bundle`, `web_node_modules`) that a rebuild
  doesn't refresh, so also run `docker compose exec api bundle install` or `docker compose exec web pnpm install`.
- **Dependencies still stale or broken:** remove just that volume: `docker compose down`, then
  `docker volume rm property-search_bundle` (or `property-search_web_node_modules`), then `make up`.
  `docker compose down -v` also works but deletes the database volume too.
- **Port already in use:** see the same item under Option B.
- **Reloads feel slow on macOS:** that's bind-mount file syncing. Use Option B for coding.

### Option B: Develop (hybrid, recommended)

**Who it's for:** anyone changing code. Rails and Vite run natively for fast reloads and tests,
your editor's Ruby/TS tooling works, and `debug`, `bin/rails console` and `pnpm` run directly,
with no `docker compose exec`.

**Prerequisites:**

1. **Docker Desktop**, running.
2. **Ruby 3.4.13** (pinned in `api/.ruby-version`). With [rbenv](https://github.com/rbenv/rbenv)
   (mise or asdf also work; they read the same file):

   ```bash
   rbenv install 3.4.13
   cd api && ruby -v        # should print 3.4.13
   gem install bundler      # only if `bundle` is missing
   ```

3. **Node 24 and pnpm.** Node ships with corepack, which installs the exact pnpm version pinned
   in `web/package.json` (`packageManager`). If you later see `pnpm: command not found`, this step
   was skipped, often after switching Node with nvm (corepack shims are per Node version).

   ```bash
   node -v                  # v24.x
   corepack enable pnpm
   ```

4. **Ports 5432, 6379, 3000 and 5173 free** (stop any local Postgres or Redis).

**One-time setup:**

```bash
make setup   # starts db + redis in Docker, bundle install, db:prepare + seed, pnpm install
```

**Start / stop:**

```bash
make dev        # starts db + redis if needed, then Rails on :3000 and Vite on :5173
                # Ctrl-C stops Rails and Vite; db + redis keep running
make down       # stop and remove the db + redis (and pgAdmin) containers (data is kept)
```

`make api` and `make web` run just one side, in separate terminals.

**How to know it worked:** both processes log that they are listening, http://localhost:3000/up
returns 200, and http://localhost:5173 loads. `docker compose ps` shows db and redis `healthy`.

**Common commands:**

```bash
make services                    # start only db + redis (needed by make test and rspec)
make test                        # rspec + vitest
make seed                        # db:seed:replant: WIPES all tables, then reseeds
cd api && bin/rails console
cd api && bin/rubocop            # same as CI
cd web && pnpm lint && pnpm typecheck   # same as CI
cd web && pnpm test:watch        # vitest in watch mode
```

`make test` and `bundle exec rspec` need Postgres running, so run `make services` first.

**Run a single test:**

```bash
cd api && bundle exec rspec spec/requests/health_spec.rb        # one file
cd api && bundle exec rspec spec/requests/health_spec.rb:4      # one example, by line
cd web && pnpm test src/lib/api.test.ts                         # one file
cd web && pnpm test -t "part of the test name"                  # by name
```

**Troubleshooting:**

- **`pnpm: command not found`:** run `corepack enable pnpm` (again after each new Node install via nvm).
- **`rbenv: version '3.4.13' is not installed`, or the wrong Ruby:** `rbenv install 3.4.13`; check
  `rbenv init` is in your shell profile and you're inside `api/`.
- **Port already in use (5432/6379):** a local Postgres or Redis is running. Stop it
  (e.g. `brew services stop postgresql`), or change the host side of `ports:` in `docker-compose.yml`
  (e.g. `"5433:5432"`) and set `DB_PORT=5433` in your shell.
- **API can't connect to the database** (`connection refused` on 5432): run `make services`, then
  check `docker compose ps` shows db `healthy`.
- **`A server is already running`:** a stale pid file from a crashed Rails (or from the Docker
  container, which shares `api/`). Delete `api/tmp/pids/server.pid`. The Docker setup does this on start.
- **Reset the database:** `make seed` wipes and reseeds the tables. `docker compose down -v`
  deletes the Postgres volume entirely; the next `make setup` recreates it.

### Browsing the database (pgAdmin, optional)

```bash
make pgadmin    # starts db if needed, then pgAdmin on http://localhost:5050
```

1. Open http://localhost:5050 and log in with **`dev@example.com` / `pgadmin`**.
2. In the left tree, open **Servers → property-search (Docker)**. It's pre-registered from
   `docker/pgadmin/servers.json`.
3. Enter the Postgres password **`postgres`** when asked. Tick "Save password" to skip it next time.
4. The app's tables are under **Databases → property_search_development → Schemas → public → Tables**
   (`property_search_test` is the RSpec database and is emptied by every test run).

Notes:

- pgAdmin is in the Compose `tools` profile, so `make up` and `make dev` never start it.
  `make down` stops it along with everything else.
- These are dev-only defaults. The port is published on `127.0.0.1` only, so nothing else on the
  network can reach it. Override the login with `PGADMIN_EMAIL` / `PGADMIN_PASSWORD` in your shell.
- Inside Docker the database host is `db`, not `localhost`. Use `db:5432` if you add a server by hand.
- `servers.json` is only imported the first time pgAdmin starts. If you change it, run
  `docker compose --profile tools down` and `docker volume rm property-search_pgadmin_data`, then
  `make pgadmin` again. That also forgets saved passwords and pgAdmin settings.

### Environment variables

Nothing needs copying: every value has a default in code that matches the Docker setup.

| File | Variables | Loaded? |
| ---- | --------- | ------- |
| `api/.env.example` | `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `REDIS_URL`, `FRONTEND_ORIGIN`, `JWT_SECRET` (commented out; at least 32 bytes or the app refuses to boot; falls back to a key derived from `secret_key_base`), `TRUSTED_PROXIES` (commented out; load balancers whose `X-Forwarded-For` is believed for rate limiting, empty = trust nobody) | **No.** There is no dotenv gem, so a copied `api/.env` is ignored. It documents the defaults in `config/database.yml`, `config/cable.yml` and `config/environments/development.rb`; to change one, export it in your shell. |
| `web/.env.example` | `API_PROXY_TARGET` (where Vite proxies `/api` and `/cable`; default `http://localhost:3000`) | **Yes**, if copied to `web/.env`: `vite.config.ts` uses `loadEnv`. Docker Compose sets it to `http://api:3000`. |

### Where things live

| Path | What |
| ---- | ---- |
| `api/app/models` | ActiveRecord models: `User`, `Property`, `PropertyEvent`, `WatchlistItem` |
| `api/app/controllers` | API controllers under `/api/v1` |
| `api/db/seeds.rb`, `api/db/seeds/` | Demo accounts, `PropertyGenerator`, `suburbs.csv` (real suburb/postcode pairs) |
| `api/app/channels` | ActionCable connection auth _(Milestone 1)_; `WatchlistChannel` _(Milestone 6)_ |
| `api/app/services` | `AuthToken` (JWT issue/verify, cookie options) |
| `api/app/queries` | `Properties::SearchQuery` (filters, sort, validation, keyset paging), `Properties::Cursor`; `Watchlist::ListQuery` and `Watchlist::Cursor` (the user's watchlist, newest added first) |
| `api/config/pagination.yml` | Default and maximum `limit` (`PAGINATION_DEFAULT_LIMIT`, `PAGINATION_MAX_LIMIT`) |
| `api/app/resources` | Alba serializers |
| `api/spec` | RSpec: `requests/`, `models/`, `services/`, `channels/`, `support/` |
| `web/src/features` | Feature code: `auth/`, `properties/`, `watchlist/` |
| `web/src/routes` | TanStack Router routes |
| `web/src/lib` | API client, cable consumer, Query client |
| `web/src/components` | Shared UI (`ui/`) |

### Demo logins

The seed creates two accounts, both with the password `property-demo-2026`:

| Email               | Role  |
| ------------------- | ----- |
| `demo@example.com`  | user  |
| `admin@example.com` | admin (admin screens are Milestone 8) |

`GET /api/v1/me` returns the `role`, so the UI can tell them apart. Sign-up ignores any `role`
param and always creates a normal user.

### Seed data

`make seed` (`db:seed:replant`) wipes every table and reseeds; plain `bin/rails db:seed` only adds
what is missing. Seeding is skipped in production unless `SEED_DEMO_DATA=1`, because the demo
accounts have a known password and `bin/docker-entrypoint` seeds a fresh database. Forcing it
there also requires `SEED_DEMO_PASSWORD`, so the published password is never used in production.

- **10,000 properties by default** (`SEED_COUNT=100000 make seed` for the `EXPLAIN` plans), written
  with `insert_all` in batches, about 2 s for 10k. `insert_all` skips callbacks on purpose, so
  seeding never writes `property_events` or broadcasts.
- **Real places:** 120 suburb/postcode pairs across all 8 states and territories in
  `api/db/seeds/suburbs.csv` (NT postcodes keep their leading zero, e.g. `0800`). Street names,
  prices and room counts are generated per property type (land has no bedrooms, apartments have
  no land size, acreage is 8,000 m² and up).
- **Something for every filter:** about 10% withheld prices ("Contact agent", "Auction"), 15%
  under offer, and some sold and withdrawn listings that search must never return.
- **Edge cases on purpose:** prices are rounded to $5,000 and some rows share a `listed_at`
  exactly, while others share its millisecond but not its microseconds (equal in JSON, different
  in Postgres), so the keyset cursor has ties to get right.
- **Deterministic:** a fixed random seed, so the same `SEED_COUNT` gives the same rows, with listing dates relative to when you seeded. Ids come from the table's sequence, so they change on each reseed.
- Built with Ruby's `Random` rather than Faker, since Faker is a development/test gem and street
  names from its default locale don't look Australian. `image_url` is left empty; the UI shows a
  placeholder.

## Trying the live updates _(available from Milestone 6)_

1. Open the app in two browser windows and sign in as `demo@example.com` in both.
2. Watch a property from the search page.
3. Change that property from a terminal in `api/` (`<id>` is a placeholder; TODO: fill in a known id once the seed exists):

```bash
bin/rails "demo:change_property[<id>,price=820000]"
bin/rails "demo:change_property[<id>,status=sold]"
```

Both windows should update the card in place and show a toast within about a second.
To change random watched properties instead:

```bash
bin/rails demo:simulate_changes
```

A card whose new status no longer matches the current filters (e.g. it just sold) stays in the
list with its new badge until the next refetch, rather than vanishing under the cursor.

## Design decisions

### Auth ([PRD](PRD.md#security-hardening))

- One HS256 JWT in an `HttpOnly; SameSite=Lax` cookie (`Secure` in production). Fixed 24 h `exp`: after that you sign in again. No renewal in Milestone 1; sliding renewal with a 14-day cap is [Milestone 9](PRD.md#milestone-9--nice-to-have-hardening).
- Signing secret: `JWT_SECRET` if set, otherwise a key derived from `secret_key_base` for this one purpose (`key_generator.generate_key("auth/jwt")`), so the JWT key is never the same as Rails' own secret. The app refuses to boot with a `JWT_SECRET` under 32 bytes: a short HS256 key could be brute-forced offline from any user's own cookie. `master.key` is gitignored, so a fresh clone works without it; production sets `JWT_SECRET` (or `SECRET_KEY_BASE`).
- Production refuses to boot without `FRONTEND_ORIGIN`, or with an entry that isn't a bare origin (e.g. a trailing slash), instead of answering every write with a silent 403.
- Why a JWT rather than Rails' encrypted session cookie: both are stateless; the JWT gives explicit `exp` and claims, verified by one code path for REST and ActionCable, and it is the option the brief names. `HttpOnly` keeps it away from JavaScript either way.
- Trade-off: nothing is stored server-side, so a token copied before logout stays valid for up to 24 h. Instant revocation (a `sessions` table) is in [Milestone 9](PRD.md#milestone-9--nice-to-have-hardening).
- Assumes web and API are on the same site (e.g. `app.` and `api.` subdomains); in dev the Vite proxy gives one origin.
- CSRF (another site making the browser send a request with your cookie): `SameSite=Lax` (the browser won't attach the cookie to cross-site `POST`s) plus an `Origin` check against `FRONTEND_ORIGIN` on every `POST`/`PUT`/`PATCH`/`DELETE`.
- Logout disconnects all of that user's live sockets on every device; other devices simply reconnect with their still-valid cookie.
- Where it lives: `AuthToken` (`api/app/services/auth_token.rb`) issues and verifies the token; `Api::V1::BaseController` reads the cookie (`authenticate!`) and runs the `Origin` check; `ApplicationCable::Connection` reuses `AuthToken`. On the web, `apiFetch` sends `credentials: 'include'` and never sees the token; `requireAuth` guards routes in `beforeLoad`; a 401 anywhere else clears cached data and goes to `/login?next=…` (only same-app paths are accepted as `next`).

**Threat model (Milestone 1)**

| Asset | Threat | Control | Spec |
| ----- | ------ | ------- | ---- |
| Auth token | Stolen by injected script (XSS) | `HttpOnly` cookie; nothing in `localStorage` or JS memory | `auth_spec.rb` (cookie flags) |
| Auth token | Forged, edited or downgraded | HS256 only, `alg: none` and other algorithms rejected, `sub`/`iat`/`exp` required | `auth_token_spec.rb`, `me_spec.rb` |
| Session | Used forever after theft | Fixed 24 h `exp`; logout clears the cookie | `auth_token_spec.rb`, `auth_spec.rb` |
| User actions | CSRF from another site | `SameSite=Lax` + `Origin` must equal `FRONTEND_ORIGIN` on writes (403) | `auth_spec.rb` (Origin check) |
| Live updates | Cross-site WebSocket hijacking | Cable `allowed_request_origins` from `FRONTEND_ORIGIN`; connection needs a valid cookie | `connection_spec.rb` |
| Accounts | Password guessing, user enumeration on login | rack-attack 10/min per IP on `/auth/*`, keyed on the real peer (a spoofed `X-Forwarded-For` is ignored unless it comes from `TRUSTED_PROXIES`; ports in forwarded entries are stripped so one client keeps one bucket); `authenticate_by` (constant time) and one generic error | `rate_limit_spec.rb`, `client_ip_spec.rb`, `auth_spec.rb` |
| Passwords | Leaked from the DB or logs | bcrypt; `password_digest` never serialised; `password`, `email`, `token`, `cursor` filtered from logs | `auth_spec.rb` (response keys), `filter_parameters_spec.rb` |
| Errors | Stack traces or SQL in responses | One JSON error envelope everywhere: `rescue_from` in controllers, `JsonExceptionsApp` for unknown routes and 500s; non-string params, NUL bytes and malformed JSON are 400s, not crashes; Rails' `ip_spoofing_check` is off because it raised an empty 500 above the error handler (rate limits don't use `remote_ip`) | `errors_spec.rb`, `auth_spec.rb` |
| Watchlists | Reading or changing another user's watchlist (IDOR) | Every query goes through `current_user.watchlist_items`; endpoints are keyed on the property, never a watchlist-item id; a `user_id` param is ignored; ids must be plain integers (`12abc` and `12.0` are 404s, not property 12) | `watchlist_spec.rb` |
| Redirects | Open redirect via `?next=` | Only same-origin paths accepted; control characters and backslashes rejected (URL parsers strip or rewrite them); the normalised result is checked again, since dot segments like `/.//evil.example` normalise to `//evil.example` | `safeNext.test.ts`, `auth.test.tsx` |

Known, accepted gaps (Milestone 1):

- **Signup reveals whether an email is registered** ("has already been taken"). Hiding it needs an email-verification flow, which this app doesn't have; the `auth/ip` throttle limits how fast anyone can probe.
- **Rate limits use fixed one-minute windows**, so up to ~20 attempts can land across a window boundary. `Retry-After` reports the time left in the current window.
- **Rate limiting in Docker Compose** sees the Vite container as the peer, so all browsers share one bucket there. In production, set `TRUSTED_PROXIES` to the load balancer's range.
- **Tokens have zero clock leeway** (`iat` in the future is rejected). Fine for one API instance; several instances need synced clocks (NTP).
- **Malformed JSON bodies are logged raw in development** (Rails' debug-level parse-error log, password included). Production logs at `info` and doesn't write them.
- **Logout is idempotent:** it always clears the cookie (even an expired or tampered one) and returns 204. Disconnecting sockets is best effort: if Redis is down, the error is reported and the cookie is still cleared.
- **An open WebSocket outlives its token.** The cookie is checked when the socket connects, so a socket opened just before `exp` keeps receiving that user's updates until it drops, the user logs out, or the server restarts. Re-checking `exp` on the connection is a Milestone 9 item.
- **Subdomain deployment needs a proxy or a base URL.** The web app calls same-origin `/api/v1` and `/cable` paths, so `app.` + `api.` subdomains need either a reverse proxy in front of `app.` or a configurable API base URL. CORS and cable origins are already driven by `FRONTEND_ORIGIN`.

### Real-time ([PRD](PRD.md#real-time-design-actioncable))

- Both callbacks are guarded by `saved_change_to_price_cents? || saved_change_to_status?` (in after-callbacks `*_changed?` is already false).
- `Property#after_update` (runs inside the save's transaction) writes a `property_events` row alongside the price/status change, so history can't miss a change.
- `after_update_commit` (runs only after the transaction commits) calls `PropertyChangeNotifier`, so watchers only hear about changes that were actually saved.
- Broadcasts run inline, with no job: each is a ~1 ms Redis publish, and inline delivery also works from rake tasks and the console. At scale it would move to a Solid Queue job with retries.
- One per-user `WatchlistChannel` stream instead of one per property: one subscription per user, and a user can only ever receive their own stream.

### Search & pagination ([PRD](PRD.md#api-design))

- Keyset pagination (each page starts after the last row seen, instead of `OFFSET`, so deep pages stay fast) with an opaque, signed cursor (`[sort value, id]`); fetches `limit + 1` to decide `hasMore`. The cursor stores `listed_at` as integer microseconds (Postgres precision), since JSON times only carry milliseconds.
- Search always returns active listings (`for_sale` + `under_offer`, via `Property.active`); there is no `status` param, and sold/withdrawn never appear. An "Exclude under offer" toggle narrows to `for_sale`. The watchlist is not limited to active, so a watched property that sells stays there with its new badge.
- `GET /api/v1/properties` params: `q`, `minPrice`, `maxPrice` (whole AUD, inclusive), `minBedrooms`, `propertyTypes[]` (or comma-separated), `excludeUnderOffer`, `excludePriceWithheld` (`true`/`false`/`1`/`0`), `sort` (`newest` | `price_asc` | `price_desc`), `cursor`, `limit` (default 20, max 50). Response: `{ data: [...], meta: { limit, hasMore, nextCursor?, totalCount? } }`; `totalCount` only on the first batch (and no `COUNT` query at all when that batch already holds every row).
- `q` is trimmed and ignored when shorter than 2 characters; `%` and `_` are matched literally. Every value is type-checked: a bad value (`minBedrooms=banana`, an array where one value is expected, an unknown type or sort, `limit` out of range, min > max, a forged cursor, or a cursor from another sort) returns 422 with every bad field listed at once, keyed by the same camelCase names the client sends (`details.maxPrice`), like every other JSON key. There are no required params, so search never returns 400. NUL bytes in any value are a 422, not a database error.
- The cursor is signed (HMAC-SHA256, JSON payload, URL-safe) and records the sort it was issued for. Its values are type-checked as integers before they reach SQL.
- `watched` comes from one `LEFT JOIN watchlist_items … AND user_id = ?`, selected as a boolean, so the page is one query; `totalCount` is a separate `COUNT` on the filtered scope, without the join. A spec checks the query count doesn't grow with the number of rows.
- `GET /api/v1/watchlist` (`cursor`, `limit`) returns the user's watched properties, most recently added first, in the same shape and envelope as search (every row `watched: true`). It isn't limited to active listings. Its cursor is `[watchlist_items.created_at, id]` in microseconds, signed with its own key, so a search cursor is a 422 there. Another user's cursor only marks a position in your own list, so it leaks nothing.
- `PUT /api/v1/watchlist/:propertyId` → 201 when added, 200 when already watched (both return the property). It uses `create_or_find_by!`: insert first, and on the unique index fall back to the existing row, so two racing PUTs both succeed instead of one getting a 500. Unknown property → 404. `DELETE /api/v1/watchlist/:propertyId` → 204 whether or not it was watched. All three need sign-in (401); the writes need the `Origin` check (403). If a DELETE lands between a PUT's failed insert and its lookup, the PUT retries once. Trade-off: each repeat PUT uses up a sequence value and logs a `duplicate key` line in Postgres.
- Price sorts leave out listings with a withheld price ("Contact agent"), and the UI says so.
- Honest limits: no jumping to page N, and in a price sort a listing whose price changes mid-scroll can appear twice (de-duplicated by `id` on the client) or be missed.

### Indexes ([PRD](PRD.md#data-model--indexing))

- Partial btree indexes (an index over only the rows matching a `WHERE`, so it stays small) `WHERE status IN ('for_sale', 'under_offer')`, matching the `Property.active` scope exactly: `(listed_at DESC, id DESC)` for newest, `(price_cents, id)` (also `price_cents IS NOT NULL`) for both price sorts, `(property_type, bedrooms)` for narrow filters.
- Free-text `q`: GIN `gin_trgm_ops` on `suburb` and `street_address` (`ILIKE '%q%'`), plus a `text_pattern_ops` btree on `postcode` for prefix matching (`LIKE 'q%'`, so `30` finds `3065`).
- **Extended statistics** on `(property_type, bedrooms)` (`CREATE STATISTICS … (mcv)`). See the villas case below for why. `schema.rb` can't record them, so the seed also creates them (`IF NOT EXISTS`) for databases loaded from `schema.rb`.
- Every `properties` index appears in at least one plan below, so none was dropped. (`watchlist_items(property_id)` and the `property_events` index serve Milestone 6.)
- `watchlist_items (user_id, created_at DESC, id DESC)` serves `GET /watchlist`: an index scan with `Index Cond: user_id = … AND ROW(created_at, id) < ROW(…)` and no sort, then a primary-key lookup per row on `properties`. Checked by hand with 20k watchlist rows across 50 users (in a rolled-back transaction; the seed creates no watchlist rows, so there's no committed plan to reproduce). With only a few hundred rows Postgres prefers a sequential scan, which is fine at that size. The unique `(user_id, property_id)` index enforces one row per property and serves the `watched` join.

#### EXPLAIN evidence

The plans below come from the exact SQL Rails sends (`Properties::SearchQuery.new(params).relation.to_sql`, run through `EXPLAIN (ANALYZE)`), not hand-written SQL. They were captured with `SEED_COUNT=100000`, because at 10k rows Postgres often prefers a sequential scan. To reproduce them:

```bash
cd api && SEED_COUNT=100000 bin/rails db:seed:replant && bin/rails search:explain
```

| Search | Plan | Time |
| ------ | ---- | ---- |
| Newest, signed in | Index Scan on `(listed_at, id)` partial, stops after 21 rows; `watched` is a Nested Loop Left Join probing the unique `(user_id, property_id)` index once per row | 0.05 ms |
| Newest, later batch | Same index, `Index Cond: ROW(listed_at, id) < ROW(…)`, so a deep page costs the same as the first | 0.04 ms |
| Price low→high | Index Scan on `(price_cents, id)` partial | 0.03 ms |
| Price high→low | Index Scan **Backward** on the same index | 0.03 ms |
| Villas, 4+ beds (no matches) | Bitmap Index Scan on `(property_type, bedrooms)`, then sort | 0.03 ms (was 33 ms, see below) |
| Acreage, 5+ beds | Feed index with a filter: matches are common enough that the first 21 come quickly | 0.7 ms |
| `q=jetty` (rare) | BitmapOr of the two trigram GIN indexes and the postcode `text_pattern_ops` index | 0.06 ms |
| `q=fitz` (common) | Feed index with a filter: matches are common, so it stops after 21 | 2.7 ms |
| `q=30` (postcode prefix) | Feed index with a filter | 0.2 ms |

**Why the extended statistics:** Postgres assumes columns are independent. For "villas, 4+ beds" it multiplied the two selectivities and expected about 1,200 matches, when the seed has none. So it walked the newest-first index hoping to fill a page early, and read every active row:

```
Index Scan using index_properties_active_on_listed_at_id on properties (actual time=34.074..34.074 rows=0)
  Filter: ((bedrooms >= 4) AND ((property_type)::text = 'villa'::text))
  Rows Removed by Filter: 91914
Execution Time: 34.098 ms
```

MCV statistics over the pair tell it the combination is rare, so it switches to the narrow index:

```
Limit (actual time=0.007..0.007 rows=0)
  ->  Sort  (Sort Key: listed_at DESC, id DESC)
        ->  Bitmap Heap Scan on properties (rows=1) (actual rows=0)
              ->  Bitmap Index Scan on index_properties_active_on_property_type_bedrooms (actual rows=0)
                    Index Cond: (((property_type)::text = 'villa'::text) AND (bedrooms >= 4))
Execution Time: 0.030 ms
```

The rare free-text plan, showing all three text indexes:

```
Bitmap Heap Scan on properties (actual time=0.015..0.015 rows=0)
  ->  BitmapOr
        ->  Bitmap Index Scan on index_properties_on_suburb_trgm          Index Cond: (suburb ~~* '%jetty%')
        ->  Bitmap Index Scan on index_properties_on_street_address_trgm  Index Cond: (street_address ~~* '%jetty%')
        ->  Bitmap Index Scan on index_properties_on_postcode_pattern     Index Cond: (postcode ~>=~ 'jetty' AND postcode ~<~ 'jettz')
Execution Time: 0.055 ms
```

Trade-off: a very common `q` that is also rare among the newest listings could still scan a lot of the feed index before it fills a page. At this size it never exceeded 3 ms.

### State management ([PRD](PRD.md#frontend-architecture))

- **Server state:** TanStack Query (search pages, watchlist, `/me`).
- **URL state:** TanStack Router search params, validated by a zod schema in `validateSearch` (`q`, price, beds, types, sort).
- **Client state:** Jotai (toasts, cable status, drawer open, auth-redirect target).
- Filters live only in the URL, never copied into Jotai, so back/forward, refresh and shared links work with no sync code.

### N+1, rate limiting & caching ([PRD](PRD.md#non-functional-requirements))

- `bullet` is in the development and test groups: it logs in development and raises in the test suite (`Bullet.raise = true`), so any request spec with an N+1 fails. `spec/config/bullet_spec.rb` proves it still raises.
- rack-attack is the only limiter (no Rails 8 `rate_limit`). Login and signup use the scaffold's `auth/ip` throttle (10/min per IP), returning 429 with the shared error shape and `Retry-After`. It gets its own `Rack::Attack.cache.store` (Redis in dev/prod, `MemoryStore` in test), since the test `Rails.cache` is a null store. _(Milestone 1)_
- Per-route rack-attack throttles for search and watchlist writes, and Redis-cached search counts, come in Milestone 7.

## Build progress

The core path (Milestones 1–6) is about 3 h 40 min, including the README update each milestone
ends with, leaving a **20-minute buffer** inside 4 hours. A short final README pass comes out of
that buffer. Milestone 7 only uses leftover buffer.
Milestones 8–9 are nice-to-haves.

| Milestone | Name | Estimate | Actual | Done |
| --------- | ---- | -------- | ------ | ---- |
| 1  | Auth & minimum security | ~50 min | | [x] |
| 2  | Property data & seeds | ~25 min | | [x] |
| 3  | Search API | ~40 min | | [x] |
| 4  | Watchlist API | ~15 min | | [x] |
| 5  | Search & watchlist UI | ~50 min | | [ ] |
| 6  | Real-time | ~25 min | | [ ] |
| 7  | Performance & bonus | leftover buffer | | [ ] |
| 8  | Admin UI for properties (nice to have) | ~55 min | | [ ] |
| 9  | Security hardening & extras (nice to have) | documented only | | [ ] |

## Notes from a JS/TS developer learning Rails

_To be written as I go._

- What surprised me: _TODO_
- What I hand-rolled and would now replace with a Rails built-in: _TODO_
- Time spent vs estimate: _TODO_

## What I'd do next

- Sliding token renewal (fresh 24 h `exp` once the token is over 1 h old) with a hard cap of 14 days from login.
- Server-side sessions for instant revocation, plus "log out everywhere" and a device list.
- Short-lived access token with a rotating refresh token and reuse detection.
- Stronger login protection: per-email throttling with lockout, a breached-password check, optional TOTP 2FA.
- Encrypted cursors bound to the query, so they can't be read or replayed against other filters.
- Production web image behind nginx with a strict CSP, HSTS and the usual security headers; `pnpm audit`, gitleaks and Dependabot in CI.
- Offset paging mode for API clients, saved searches with alerts, and PostGIS radius search.
- Admin extras: CSV import, image uploads, an audit log of admin changes.
- Move `PropertyChangeNotifier` into a Solid Queue job with retries once fan-out grows; lograge JSON logs.

---

Full plan, requirements and trade-offs: [PRD.md](PRD.md).
