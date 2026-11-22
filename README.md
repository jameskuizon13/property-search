# Property Search

A small property search app, built for a fullstack coding challenge (3–4 h timebox).
Users search Australian listings, filter by price, bedrooms and property type, scroll through
results that keep loading, and save properties to a watchlist that updates live when a watched
property's price or status changes. The Docker Compose project is called `property-search`.

**Status: only the scaffold exists so far.** The work is split into numbered **batches** (build
steps, listed in [Build progress](#build-progress) and [PRD.md](PRD.md#delivery-plan-risks--open-questions)).
A label like _(Batch 6)_ means that part is planned but not built yet. The full plan is in [PRD.md](PRD.md).

> The brief asked for Jest. Tests use **Vitest** (same API as Jest) with React Testing Library
> instead, because Vitest reuses the Vite config, so there is no separate Babel/SWC transform to maintain.

## Stack

| Part   | Stack |
| ------ | ----- |
| `api/` | Rails 8.1 (API mode), Ruby 3.4, Puma, PostgreSQL 17, Redis 7, ActionCable, `jwt`, Alba, rack-cors, rack-attack, bullet, RSpec + FactoryBot + shoulda-matchers |
| `web/` | Vite, React 19, TypeScript, TanStack Query, TanStack Router, zod, Jotai, `@rails/actioncable`, Tailwind 4, TanStack Virtual _(installed; used only if time allows, Batch 7)_, Vitest + React Testing Library + MSW, oxlint |

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
make down       # stop and remove the db + redis containers (data is kept)
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

### Environment variables

Nothing needs copying: every value has a default in code that matches the Docker setup.

| File | Variables | Loaded? |
| ---- | --------- | ------- |
| `api/.env.example` | `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `REDIS_URL`, `FRONTEND_ORIGIN`, `JWT_SECRET` (commented out; falls back to `secret_key_base`) | **No.** There is no dotenv gem, so a copied `api/.env` is ignored. It documents the defaults in `config/database.yml`, `config/cable.yml` and `config/environments/development.rb`; to change one, export it in your shell. |
| `web/.env.example` | `API_PROXY_TARGET` (where Vite proxies `/api` and `/cable`; default `http://localhost:3000`) | **Yes**, if copied to `web/.env`: `vite.config.ts` uses `loadEnv`. Docker Compose sets it to `http://api:3000`. |

### Where things live

| Path | What |
| ---- | ---- |
| `api/app/models` | ActiveRecord models _(Batch 1–2)_ |
| `api/app/controllers` | API controllers under `/api/v1` _(Batch 1 onwards)_ |
| `api/app/channels` | ActionCable `WatchlistChannel` _(Batch 6; folder not created yet)_ |
| `api/spec` | RSpec: `requests/`, `support/` |
| `web/src/features` | Feature code: `auth/`, `properties/`, `watchlist/` |
| `web/src/routes` | TanStack Router routes |
| `web/src/lib` | API client, cable consumer, Query client |
| `web/src/components` | Shared UI (`ui/`) |

### Demo logins _(Batch 2)_

The seed will create two accounts:

| Email               | Role  |
| ------------------- | ----- |
| `demo@example.com`  | user  |
| `admin@example.com` | admin (admin screens are Batch 9) |

Password: see `api/db/seeds.rb`. `make seed` re-runs the seed from scratch.

## Trying the live updates _(available from Batch 6)_

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

- One HS256 JWT in an `HttpOnly; SameSite=Lax` cookie (`Secure` in production). Fixed 24 h `exp`: after that you sign in again. No renewal in Batch 1; sliding renewal with a 14-day cap is [Batch 10](PRD.md#batch-10--nice-to-have-hardening).
- Signing secret: `ENV.fetch("JWT_SECRET") { Rails.application.secret_key_base }`. `master.key` is gitignored, so a fresh clone works without it; production sets `JWT_SECRET` (or `SECRET_KEY_BASE`).
- Why a JWT rather than Rails' encrypted session cookie: both are stateless; the JWT gives explicit `exp` and claims, verified by one code path for REST and ActionCable, and it is the option the brief names. `HttpOnly` keeps it away from JavaScript either way.
- Trade-off: nothing is stored server-side, so a token copied before logout stays valid for up to 24 h. Instant revocation (a `sessions` table) is in [Batch 10](PRD.md#batch-10--nice-to-have-hardening).
- Assumes web and API are on the same site (e.g. `app.` and `api.` subdomains); in dev the Vite proxy gives one origin.
- CSRF (another site making the browser send a request with your cookie): `SameSite=Lax` (the browser won't attach the cookie to cross-site `POST`s) plus an `Origin` check against `FRONTEND_ORIGIN` on every `POST`/`PUT`/`PATCH`/`DELETE`.
- Logout disconnects all of that user's live sockets on every device; other devices simply reconnect with their still-valid cookie.

### Real-time ([PRD](PRD.md#real-time-design-actioncable))

- Both callbacks are guarded by `saved_change_to_price_cents? || saved_change_to_status?` (in after-callbacks `*_changed?` is already false).
- `Property#after_update` (runs inside the save's transaction) writes a `property_events` row alongside the price/status change, so history can't miss a change.
- `after_update_commit` (runs only after the transaction commits) calls `PropertyChangeNotifier`, so watchers only hear about changes that were actually saved.
- Broadcasts run inline, with no job: each is a ~1 ms Redis publish, and inline delivery also works from rake tasks and the console. At scale it would move to a Solid Queue job with retries.
- One per-user `WatchlistChannel` stream instead of one per property: one subscription per user, and a user can only ever receive their own stream.

### Search & pagination ([PRD](PRD.md#api-design))

- Keyset pagination (each page starts after the last row seen, instead of `OFFSET`, so deep pages stay fast) with an opaque, signed cursor (`[sort value, id]`); fetches `limit + 1` to decide `hasMore`. The cursor stores `listed_at` as integer microseconds (Postgres precision), since JSON times only carry milliseconds.
- Search always returns active listings (`for_sale` + `under_offer`, via `Property.active`); there is no `status` param, and sold/withdrawn never appear. An "Exclude under offer" toggle narrows to `for_sale`. The watchlist is not limited to active, so a watched property that sells stays there with its new badge.
- `q` is trimmed and ignored when shorter than 2 characters. A missing required param returns 400; invalid values (bad cursor, `limit` out of range, min > max) return 422.
- Price sorts leave out listings with a withheld price ("Contact agent"), and the UI says so.
- Honest limits: no jumping to page N, and in a price sort a listing whose price changes mid-scroll can appear twice (de-duplicated by `id` on the client) or be missed.

### Indexes ([PRD](PRD.md#data-model--indexing))

- Partial btree indexes (an index over only the rows matching a `WHERE`, so it stays small) `WHERE status IN ('for_sale', 'under_offer')`, matching the `Property.active` scope exactly: `(listed_at DESC, id DESC)` for newest, `(price_cents, id)` (also `price_cents IS NOT NULL`) for both price sorts, `(property_type, bedrooms)` for narrow filters.
- Free-text `q`: GIN `gin_trgm_ops` on `suburb` and `street_address` (`ILIKE '%q%'`), plus a `text_pattern_ops` btree on `postcode` for prefix matching (`LIKE 'q%'`, so `30` finds `3065`).
- Any index `EXPLAIN` shows is unused gets dropped.

#### EXPLAIN evidence _(Batch 3)_

Captured from `Properties::SearchQuery.new(params).relation.explain(:analyze)` (not hand-written SQL) with `SEED_COUNT=100000`, since at 10k rows Postgres often prefers a sequential scan.

- **Newest:** _TODO: paste plan_
- **Price low→high / high→low:** _TODO: paste plan_
- **Narrow filter (e.g. villas, 4+ beds):** _TODO: paste plan_
- **Free-text `q`:** _TODO: paste plan_

### State management ([PRD](PRD.md#frontend-architecture))

- **Server state:** TanStack Query (search pages, watchlist, `/me`).
- **URL state:** TanStack Router search params, validated by a zod schema in `validateSearch` (`q`, price, beds, types, sort).
- **Client state:** Jotai (toasts, cable status, drawer open, auth-redirect target).
- Filters live only in the URL, never copied into Jotai, so back/forward, refresh and shared links work with no sync code.

### N+1, rate limiting & caching ([PRD](PRD.md#non-functional-requirements))

- _(Batch 3)_ `bullet` will raise in the test suite (`Bullet.raise = true`), so any request spec with an N+1 fails. Today it is only in the development group and logs warnings.
- rack-attack is the only limiter (no Rails 8 `rate_limit`). Login and signup use the scaffold's `auth/ip` throttle (10/min per IP), returning 429 with the shared error shape and `Retry-After`. It gets its own `Rack::Attack.cache.store` (Redis in dev/prod, `MemoryStore` in test), since the test `Rails.cache` is a null store. _(Batch 1)_
- Per-route rack-attack throttles for search and watchlist writes, and Redis-cached search counts, are later batches (Batch 7).

## Build progress

The core path (Batches 1–6 plus the README) is about 3 h 40 min, leaving a **20-minute buffer**
inside 4 hours. Batch 7 only uses leftover buffer. Batches 9–10 are nice-to-haves.

| Batch | Name | Estimate | Actual | Done |
| ----- | ---- | -------- | ------ | ---- |
| 1  | Auth & minimum security | ~50 min | | [ ] |
| 2  | Property data & seeds | ~25 min | | [ ] |
| 3  | Search API | ~40 min | | [ ] |
| 4  | Watchlist API | ~15 min | | [ ] |
| 5  | Search & watchlist UI | ~50 min | | [ ] |
| 6  | Real-time | ~25 min | | [ ] |
| 7  | Performance & bonus | leftover buffer | | [ ] |
| 8  | README | ~15 min | | [ ] |
| 9  | Admin UI for properties (nice to have) | ~55 min | | [ ] |
| 10 | Security hardening & extras (nice to have) | documented only | | [ ] |

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
