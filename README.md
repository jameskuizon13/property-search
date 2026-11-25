# Property Search

A small property search app, built for a fullstack coding challenge (3–4 h timebox).
Users search Australian listings, filter by price, bedrooms and property type, scroll through
results that keep loading, and save properties to a watchlist that updates live when a watched
property's price or status changes. The Docker Compose project is called `property-search`.

**Status:** built: auth and minimum security, property data and seeds, the search and watchlist
APIs, the search and watchlist UI, live watchlist updates, and rate limits and caching. Admin screens
for properties and further security hardening are planned but not built (see
[What I'd do next](#what-id-do-next)). The full plan, including the build order and estimates, is
in [PRD.md](PRD.md#delivery-plan-risks--open-questions).

> The brief asked for Jest. Tests use **Vitest** (same API as Jest) with React Testing Library
> instead, because Vitest reuses the Vite config, so there is no separate Babel/SWC transform to maintain.

## Stack

| Part   | Stack |
| ------ | ----- |
| `api/` | Rails 8.1 (API mode), Ruby 3.4, Puma, PostgreSQL 17, Redis 7, ActionCable, `jwt`, Alba, rack-cors, rack-attack, bullet, RSpec + FactoryBot + shoulda-matchers |
| `web/` | Vite, React 19, TypeScript, TanStack Query, TanStack Router, zod, Jotai, `@rails/actioncable`, Tailwind 4, Vitest + React Testing Library + MSW, oxlint |

Infra: Docker Compose (db, redis, api, web), a root `Makefile`, GitHub Actions CI (one job per app), husky + lint-staged git hooks.

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
   in `package.json` and `web/package.json` (`packageManager`). If you later see `pnpm: command not found`, this step
   was skipped, often after switching Node with nvm (corepack shims are per Node version).

   ```bash
   node -v                  # v24.x
   corepack enable pnpm
   ```

4. **Ports 5432, 6379, 3000 and 5173 free** (stop any local Postgres or Redis).

**One-time setup:**

```bash
make setup   # starts db + redis in Docker, installs the git hooks, bundle install,
             # db:prepare + seed, pnpm install
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

**Git hooks** (husky + lint-staged, installed by `make setup` or `pnpm install` at the repo root).
Each hook checks only the packages your change touches, so a web-only commit never waits on rspec:

| Hook | When `api/` changed | When `web/` changed |
| --- | --- | --- |
| pre-commit | `bin/rubocop` on the staged Ruby files, then the full `rspec` suite | `oxlint` on the staged TS/JS files, then the full `vitest` suite |
| pre-push | `bin/rails zeitwerk:check` (eager-loads the app, as production does) | `pnpm build` (`tsc -b` + `vite build`) |

- The pre-commit hook runs on exactly what you're committing: unstaged edits and untracked files are
  set aside while it runs and put back afterwards, so a new file you forgot to `git add` fails the
  tests. Deleting a file, or moving one out of a package, counts as a change to that package.
- Don't edit files while it runs. If it ends with "Failed to restore unstaged changes", nothing is
  lost: your edits are in the stash named "lint-staged automatic backup" (`git stash list`).
- In a merge commit, lint-staged only checks files that differ from both parents, so merging
  `main`'s api changes into a web-only branch doesn't run rspec. Run `make test` after such merges.
- It runs the whole suite of a touched package, not only related tests, so a change that breaks a
  caller elsewhere is caught. `rspec` needs Postgres: run `make services` first.
- pre-push compares the pushed commits with what the remote already has (with `origin/main` for a
  new branch) and builds the working tree, so commit or stash anything you aren't pushing.
- Skip once with `git commit --no-verify` / `git push --no-verify`. The config is in
  `lint-staged.config.mjs` and `.husky/`.
- **GUI git clients** (Fork, Tower, VS Code) may not have your shell's `PATH`, so the hooks can't
  find `pnpm`, `bundle` or rbenv's Ruby, or they pick up an older system Node (lint-staged needs
  Node 22.22.1 or newer). Put the PATH setup (e.g. `eval "$(rbenv init -)"`) in
  `~/.config/husky/init.sh`, which husky sources before every hook.

**Run a single test:**

```bash
cd api && bundle exec rspec spec/requests/health_spec.rb        # one file
cd api && bundle exec rspec spec/requests/health_spec.rb:4      # one example, by line
cd web && pnpm test src/lib/api.test.ts                         # one file
cd web && pnpm test -t "part of the test name"                  # by name
```

**Troubleshooting:**

- **`pnpm: command not found`:** run `corepack enable pnpm` (again after each new Node install via nvm).
- **Commit blocked with `PG::ConnectionBad` / `connection refused`:** the pre-commit hook runs
  rspec for any `api/` change, which needs Postgres: `make services`, then commit again.
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

See [Folder structure](#folder-structure): what each folder holds, how they connect, and why
there are more than Rails' defaults.

### Demo logins

The seed creates two accounts, both with the password `property-demo-2026`:

| Email               | Role  |
| ------------------- | ----- |
| `demo@example.com`  | user  |
| `admin@example.com` | admin (admin screens are planned, not built yet) |

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

## Folder structure

Two apps side by side. `web/` calls `api/` over HTTP (`/api/v1/...`) and a WebSocket (`/cable`);
in development Vite proxies both, so the browser only ever talks to one origin.

```
property-search/
├── api/                 Rails JSON API + ActionCable
├── web/                 React single-page app (Vite)
├── docker/              pgAdmin's server list
├── docker-compose.yml   db, redis, api, web
├── Makefile             shortcuts for both apps
├── .github/workflows/   CI: one job per app
└── .husky/, lint-staged.config.mjs   pre-commit hooks
```

### Why `api/app/` has more than `models/` and `controllers/`

Rails only fixes a handful of names under `app/`: `models/`, `controllers/`, `channels/`, `jobs/`,
`mailers/` and `views/` (this app is API-only, so there are no views or mailers). Everything else is
a team choice, and adding one costs nothing: Zeitwerk, Rails' autoloader, treats **every** folder
directly under `app/` as a root. So `app/queries/properties/search_query.rb` is just
`Properties::SearchQuery`, with no `require` and no config; the folder name never appears in the
class name.

The extra folders exist to keep the two defaults thin. A model answers "what is valid data?", a
controller answers "which request, which status code?", and anything that is neither gets its own
home instead of growing a 500-line model or controller. `services/`, `queries/` and `resources/`
are common community conventions (`resources/` is the name the Alba gem uses for serializers), not
Rails features.

How a search request passes through them:

```
GET /api/v1/properties?minPrice=500000
  → controllers/api/v1/properties_controller.rb   picks the allowed params, nothing else
  → queries/properties/search_query.rb             validates filters (422 if bad), builds the SQL,
                                                   keyset-pages with properties/cursor.rb
  → models/property.rb                             table, enums, scopes, validations
  → resources/property_resource.rb                 Property → camelCase JSON
  → controllers/api/v1/base_controller.rb          render_page: { data, meta }
```

And a live price change:

```
property.update!(price_cents: ...)        (a rake demo task, the console, later the admin UI)
  → models/property.rb                    after_update_commit, only if price or status changed
  → services/property_change_notifier.rb  finds the users watching it
  → channels/watchlist_channel.rb         broadcasts to each watcher's own stream
  → web/src/features/watchlist/useWatchlistChannel.ts   patches the cached property in place
```

| Folder | From | Holds | Belongs here when… |
| ------ | ---- | ----- | ------------------ |
| `app/models` | Rails | `User`, `Property`, `PropertyEvent`, `WatchlistItem`: associations, enums, validations, scopes, callbacks | it describes one table's data and rules |
| `app/controllers` | Rails | `api/v1/*` controllers; `BaseController` holds `current_user`, `authenticate!`, the sign-in cookie, the origin check and `render_page`; `ApplicationController` turns exceptions into JSON errors | it maps an HTTP request to a status code. Each action calls one query or model method and renders |
| `app/resources` | Alba | `PropertyResource`, `UserResource` | it decides what JSON the client sees. One `PropertyResource` serves search, the watchlist and live updates, so all three send the same shape |
| `app/queries` | ours | `Properties::SearchQuery` + `Cursor`, `Watchlist::ListQuery` + `Cursor` | it is read-only: params in, records and paging `meta` out. Specced directly, without HTTP |
| `app/services` | ours | `AuthToken` (JWT issue/verify, cookie options), `PropertyChangeNotifier` (live-update fan-out), `SearchCache` (the version cached counts hang off) | it is an action that is neither HTTP nor one model's job |
| `app/channels` | Rails | `ApplicationCable::Connection` (signs the socket in from the auth cookie), `WatchlistChannel` | it is the WebSocket version of a controller |
| `app/jobs` | Rails | Only the generated base class. The notifier runs inline (see [Real-time](#real-time-prd)) | — |
| `lib/` | Rails | `client_ip.rb` and `json_exceptions_app.rb` (Rack-level code); `tasks/` (`demo:*`, `search:explain`) | it runs outside a request, or must load at boot. The two Rack files are `require`d by `config/application.rb` for middleware, before `app/` is loaded, so they are kept out of autoloading |
| `config/` | Rails | `routes.rb`; `initializers/` (CORS, rack-attack, Alba, JWT secret check); `pagination.yml` (default and max `limit`) | it is set once at boot |
| `db/` | Rails | `migrate/`, `schema.rb`, `seeds.rb`; `seeds/` holds `PropertyGenerator` and `suburbs.csv` (real suburb/postcode pairs), too big for `seeds.rb` | — |
| `spec/` | RSpec | Mirrors `app/`: `requests/` (a controller end to end, through routing and middleware), `models/`, `queries/`, `services/`, `channels/`, `tasks/`; `factories/`; `support/` (shared helpers) | — |

### The order the folders appeared

None of the custom folders were planned up front. Each appeared when the first code that didn't
fit the existing ones was written, in the order the features were built:

1. **Scaffold:** `rails new` gave `models/`, `controllers/` and `jobs/`. The web app started with
   `router.tsx`, `lib/` (the fetch wrapper, cable consumer and `QueryClient`), `features/auth/` and `test/`.
2. **Auth:** `controllers/api/v1/` (versioned, so a v2 could live beside it later);
   `resources/` for the first JSON response (`UserResource`); `services/` for `AuthToken`, because
   signing a JWT is neither a model nor HTTP; `lib/` for the client-IP and JSON-error Rack code;
   `channels/application_cable/`, whose connection signs the socket in with the same cookie. Web got
   `routes/` for the layout and login pages.
3. **Property data:** `db/seeds/`, once the generator and the suburb CSV outgrew `seeds.rb`.
4. **Search API:** `queries/`. Filter validation, sorting and keyset cursors were too much for a
   controller action and are read-only, so they are not a service either.
5. **Watchlist API:** no new folders; `Watchlist::ListQuery` followed the search pattern.
6. **Search and watchlist UI:** `web/src/components/ui/`, once both pages needed the property card,
   the endless list and the loading skeletons.
7. **Live updates:** `WatchlistChannel`, `PropertyChangeNotifier` and `lib/tasks/demo.rake` went into
   folders that already existed.
8. **Rate limits and caching:** `SearchCache`, again in `services/`.

### `web/src/`

React has even fewer conventions than Rails, so this layout is also a choice:

| Folder | Holds |
| ------ | ----- |
| `main.tsx`, `router.tsx` | Entry point; `router.tsx` is the single route table (the counterpart of `config/routes.rb`), with auth guards and URL validation |
| `routes/` | `RootLayout` and the small login/signup pages, which only arrange feature components |
| `features/<name>/` | Everything for one area: `api.ts` (fetch calls), TanStack Query hooks, components, zod schemas, types. `auth/`, `properties/` and `watchlist/` line up with the API's auth/me, properties and watchlist controllers |
| `lib/` | Plumbing that knows no feature: the fetch wrapper, the cable consumer, the `QueryClient`, every query key in one place (so hooks, cache patches and tests can't drift apart), shared API types |
| `components/ui/` | Pieces used by more than one feature: `PropertyCard`, `InfiniteResults`, `Skeleton`, `Toaster` |
| `test/` | MSW server and handlers, render helpers, browser fakes. Tests themselves sit next to the code as `*.test.ts(x)` |

The folders are grouped by **feature** rather than by kind (`components/`, `hooks/`, `services/`),
so a watchlist change stays inside one folder. `lib/` never imports from `features/`. Features do
import each other where the areas overlap: the watchlist reuses the property types, formatting and
cache helpers, and the search results show the watchlist's `WatchButton`.

## Trying the live updates

1. Open the app in two browser windows (or a normal and a private one) and sign in as
   `demo@example.com` in both. "Live" with a green dot by your name means the live connection is up.
2. Watch a property or two from the search page.
3. From a terminal in `api/`, find the ids you watch and change one:

```bash
bin/rails demo:watched
```

```bash
bin/rails "demo:change_property[42,price=820000]"
```

`42` stands for an id from the list. The change can also be `price=withheld` or
`status=for_sale|under_offer|sold|withdrawn`; prices are whole dollars ($1,000 to $1 billion).
Bad input exits with status 1 and a usage message.

Both windows update the card in place and show a toast such as "12 Smith St: $850k → $820k"
within about a second (a window that isn't showing that card still gets the toast). To change random watched properties instead (`COUNT`, default 3):

```bash
bin/rails demo:simulate_changes
```

With everything in Docker (`make up`), prefix each command with `docker compose exec api`, e.g.
`docker compose exec api bin/rails demo:watched`.

A card whose new status no longer matches the current filters (e.g. it just sold) stays in the
list with its new badge until the next refetch, rather than vanishing under the cursor.

## Design decisions

### Auth ([PRD](PRD.md#security-hardening))

- One HS256 JWT in an `HttpOnly; SameSite=Lax` cookie (`Secure` in production). Fixed 24 h `exp`: after that you sign in again. No renewal yet; sliding renewal with a 14-day cap is [planned](PRD.md#milestone-9--nice-to-have-hardening).
- Signing secret: `JWT_SECRET` if set, otherwise a key derived from `secret_key_base` for this one purpose (`key_generator.generate_key("auth/jwt")`), so the JWT key is never the same as Rails' own secret. The app refuses to boot with a `JWT_SECRET` under 32 bytes: a short HS256 key could be brute-forced offline from any user's own cookie. `master.key` is gitignored, so a fresh clone works without it; production sets `JWT_SECRET` (or `SECRET_KEY_BASE`).
- Production refuses to boot without `FRONTEND_ORIGIN`, or with an entry that isn't a bare origin (e.g. a trailing slash), instead of answering every write with a silent 403.
- Why a JWT rather than Rails' encrypted session cookie: both are stateless; the JWT gives explicit `exp` and claims, verified by one code path for REST and ActionCable, and it is the option the brief names. `HttpOnly` keeps it away from JavaScript either way.
- Trade-off: nothing is stored server-side, so a token copied before logout stays valid for up to 24 h. Instant revocation (a `sessions` table) is [planned](PRD.md#milestone-9--nice-to-have-hardening).
- Assumes web and API are on the same site (e.g. `app.` and `api.` subdomains); in dev the Vite proxy gives one origin.
- CSRF (another site making the browser send a request with your cookie): `SameSite=Lax` (the browser won't attach the cookie to cross-site `POST`s) plus an `Origin` check against `FRONTEND_ORIGIN` on every `POST`/`PUT`/`PATCH`/`DELETE`.
- Logout disconnects all of that user's live sockets on every device; other devices simply reconnect with their still-valid cookie.
- Where it lives: `AuthToken` (`api/app/services/auth_token.rb`) issues and verifies the token; `Api::V1::BaseController` reads the cookie (`authenticate!`) and runs the `Origin` check; `ApplicationCable::Connection` reuses `AuthToken`. On the web, `apiFetch` sends `credentials: 'include'` and never sees the token; `requireAuth` guards routes in `beforeLoad`; a 401 anywhere else clears the user's cached data, shows "You've been signed out" and re-runs the route guards, so only a protected page goes to `/login?next=…` and search stays put (only same-app paths are accepted as `next`). Logging out in one tab signs out the app's other tabs through a `BroadcastChannel('auth')` (see [Search & watchlist UI](#search--watchlist-ui-prd)).

**Threat model**

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

Known, accepted gaps:

- **Signup reveals whether an email is registered** ("has already been taken"). Hiding it needs an email-verification flow, which this app doesn't have; the `auth/ip` throttle limits how fast anyone can probe.
- **Rate limits use fixed one-minute windows**, so up to ~20 attempts can land across a window boundary. `Retry-After` reports the time left in the current window.
- **Rate limiting in Docker Compose** sees the Vite container as the peer, so all browsers share one bucket there. In production, set `TRUSTED_PROXIES` to the load balancer's range.
- **Tokens have zero clock leeway** (`iat` in the future is rejected). Fine for one API instance; several instances need synced clocks (NTP).
- **Malformed JSON bodies are logged raw in development** (Rails' debug-level parse-error log, password included). Production logs at `info` and doesn't write them.
- **Logout is idempotent:** it always clears the cookie (even an expired or tampered one) and returns 204. Disconnecting sockets is best effort: if Redis is down, the error is reported and the cookie is still cleared.
- **An open WebSocket outlives its token.** The cookie is checked when the socket connects, so a socket opened just before `exp` keeps receiving that user's updates until it drops, the user logs out, or the server restarts. Re-checking `exp` on the connection is planned hardening.
- **Subdomain deployment needs a proxy or a base URL.** The web app calls same-origin `/api/v1` and `/cable` paths, so `app.` + `api.` subdomains need either a reverse proxy in front of `app.` or a configurable API base URL. CORS and cable origins are already driven by `FRONTEND_ORIGIN`.

### Real-time ([PRD](PRD.md#real-time-design-actioncable))

- Both callbacks are guarded by `saved_change_to_price_cents? || saved_change_to_status?` (in after-callbacks `*_changed?` is already false).
- `Property#after_update` (runs inside the save's transaction) writes a `property_events` row alongside the price/status change, so history can't miss a change.
- `after_update_commit` (runs only after the transaction commits) calls `PropertyChangeNotifier`, so watchers only hear about changes that were actually saved.
- Broadcasts run inline, with no job: each is a ~1 ms Redis publish, and inline delivery also works from rake tasks and the console. At scale it would move to a Solid Queue job with retries.
- One per-user `WatchlistChannel` stream instead of one per property: one subscription per user, and a user can only ever receive their own stream. Subscription params are ignored, and the channel has no actions (`subscribed` is private, so a client can't re-run it).
- The message is `{ type: "property.updated", property, changes }`: `property` is the same shape as REST (with `watched: true`, since only watchers get it) and `changes` holds `[old, new]` for `priceCents` and/or `status`. A save that changes both writes two event rows and sends one message.
- **Ordering:** every property carries a `version` (its `lock_version`, bumped on each save) in REST and in the message. The client (`useWatchlistChannel`, mounted once in the root layout) replaces a cached card only when the message's `version` is newer than **that card's**, checked per cached copy, so a late or repeated message never puts an older price back, even when search and the watchlist hold different versions. It toasts each new version once per tab, also when no list on that tab holds the card, and never for a message older than what it already shows. Close prices are written in full ("$2,005,000 → $2,000,000") rather than as two identical short forms.
- The patch keeps the card's own `watched` flag (a watch click still in flight decides that). Before patching, it cancels batches already loading for lists that show the card, as the watch toggle does, so an older response can't land on top of it; a list still on its first load is left alone, since cancelling it would leave it stuck on its skeletons.
- If Redis is down after a change commits, the error is reported and the save still succeeds; watchers see the new values on their next refetch.
- **Reconnects:** ActionCable retries by itself. After a *re*connect the watchlist refetches and search batches are marked stale (refreshed on their next view, not all at once), since updates sent while the socket was down are gone. A live update that arrives mid-refetch restarts that refetch rather than cancelling it for good. A dot and a word by the user's name show the state ("Live", "Connecting…", "Offline"); if the server refuses the socket (for example the cookie expired), it reads "Offline".
- Demo tasks (`api/lib/tasks/demo.rake`) use `update!`, so they go through the same callbacks an admin edit will. The seed uses `insert_all` on purpose, so seeding broadcasts nothing.
- Trade-off: a sign-out anywhere disconnects that user's sockets everywhere (see Auth); other devices reconnect and refetch their watchlist, which is harmless.

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
- Every `properties` index appears in at least one plan below, so none was dropped. (`watchlist_items(property_id)` serves the live-update fan-out; the `property_events` index serves change history.)
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

Every piece of state has exactly one owner, picked by where it has to survive:

| Kind | Owner | What | Why there |
| --- | --- | --- | --- |
| Server state | TanStack Query | search batches, the watchlist, `/me`, the property-type labels | It's a copy of the server's data: Query owns caching, refetching, de-duplicating requests, cancelling stale ones and optimistic updates, which would all be hand-written in a client store. |
| URL state | TanStack Router search params, validated by `searchSchema` (zod) in `validateSearch` | `q`, min/max price, beds, property types, the two "exclude" toggles, sort | Filters must survive refresh, back/forward and a shared link. In the URL they do with no sync code. Cursors stay in the Query cache, not the URL. |
| Client state | Jotai | toasts, the live-connection status | Small, app-wide UI state with no server copy. One atom per concern, so a toast never re-renders the results grid. |

- Filters are never copied into Jotai or `useState`: the page reads them from the URL and writes them back with `navigate`. The only local copy is the text box while you type, which writes to the URL 300 ms after the last keystroke (with `replace`, so typing doesn't fill the history).
- The search query key is the normalised filter object (`propertyKeys.list(filters)` in `web/src/lib/queryKeys.ts`), so a filter change is a new cache entry starting from the first batch, and going back to earlier filters reuses their cached batches.
- Why not Redux/Zustand for everything: server data in a client store means hand-writing caching and invalidation; URL state in a client store means syncing it both ways.

### Search & watchlist UI ([PRD](PRD.md#frontend-architecture))

- **Search page** (`web/src/features/properties`): `FilterBar` writes every filter to the URL. Price min/max are selects with fixed steps, and a max below the min is disabled. Changing a filter starts again from the first batch; a slow response for older filters only lands in their own cache entry, so it can never replace newer results. Text under 2 characters isn't sent (the API would ignore it), so typing one letter doesn't refetch.
- **The URL is checked, not trusted:** `searchSchema` drops any invalid value from a hand-edited URL (an unknown sort or property type, beds over 5, a max below the min, control characters in `q`) instead of sending a request the API would answer with a 422. Property types can be a JSON array (what the app writes) or the API's comma form (`house,villa`). Unknown keys such as `utm_source` are ignored: they don't count as a filter or split the cache. The router merges raw URL values back in for keys the validator leaves out, so `validateSearch` always returns every filter key. Property-type *values* are hard-coded there as a URL contract; their *labels* come from `GET /property_types`.
- **`InfiniteResults`** (`web/src/components/ui`) is shared by search and the watchlist. An `IntersectionObserver` with a 600 px margin on a sentinel after the list loads the next batch before you reach the end, guarded by `hasNextPage && !isFetchingNextPage` so it never double-fetches. Cards are de-duplicated by `id`. Loading shows skeleton cards (a row of them at the bottom for later batches); a failed first load shows an error with Retry, worded by cause (connection, server, or a rejected request), and 4xx errors aren't retried automatically; a failed later batch shows an inline Retry and keeps what's loaded; the end shows "End of results"; an empty result says which filters to loosen.
- **Infinite-scroll traps, and how each is handled:** the list keeps every loaded batch in the Query cache and the router restores scroll position, so going back doesn't lose your place; there is no footer under the list to chase; a "Back to top" button appears once you've scrolled past the first screen with more than one batch loaded, and moves focus to the page heading (smooth scrolling only when reduced motion isn't requested); and a visible "Load more" button works for keyboard and screen-reader users. It stays mounted while loading ("Loading…", `aria-disabled`) and becomes "Retry" after a failure, so focus is never dropped; when the last batch arrives, focus moves to "End of results". The list is not virtualised; off-screen cards skip layout and paint instead (see [N+1, rate limiting & caching](#n1-rate-limiting--caching-prd)).
- **Watch toggle** (`web/src/features/watchlist/useToggleWatch.ts`): the card changes at once in every cached list (search batches and the watchlist). Each click sends the state it wants, and clicks for one property share a TanStack Query mutation `scope`, so they run one at a time in click order and a PUT and DELETE can't finish out of order. If a request fails and no later click is queued, the card goes back to the last state the server confirmed and a toast says so. Signed-out users go to `/login?next=…` and come back to the same page.
- **Unwatching on the watchlist page keeps the card in place** (now showing "Watch", so one click undoes it) and marks the watchlist stale; it refreshes on your next visit.
- **Toasts by default** (`web/src/components/ui/Toaster.tsx`): sign in/up/out confirmations, form-wide login and signup errors, a failed watch, and sign-outs. Field errors stay next to their input, and a search that fails to load stays on the page with its Retry. The toast region is always in the DOM with `aria-live="polite"`, so screen readers announce new toasts. Toasts last 5 s (errors 10 s) and pause while hovered or focused.
- **Logout** stays on a public page (filters kept) and leaves `/watchlist` for search. If the logout request fails, the app says so and keeps you signed in, since the cookie may still be valid; a 401 counts as already signed out.
- **Cross-tab sign-out:** logout posts `signed-out` on a `BroadcastChannel('auth')`. Other tabs clear the user's data (user, watchlist, `watched` flags) and show "You were signed out in another tab"; a tab on `/watchlist` goes to `/login?next=/watchlist`, and a tab on search stays where it is in its signed-out view. A tab that was already signed out shows nothing.
- **Accessibility:** the watch button is a toggle (`aria-pressed`) whose name starts with its visible text ("Watch"/"Watching") followed by the address; selected property-type chips show a tick, not just a colour.
- **Performance:** cards are memoised and a toggle replaces only that property's object in the cache, so one click re-renders one card. Routes are code-split (`lazyRouteComponent`).
- A click cancels any list fetch already in flight before patching the cache, because that fetch copied the pages before the click and would write them back over it (TanStack Query's standard optimistic-update step). A cancelled next batch goes back to its earlier state and the sentinel asks for it again.
- Trade-off: filters have no mobile drawer yet; they wrap instead.

### N+1, rate limiting & caching ([PRD](PRD.md#non-functional-requirements))

- `bullet` is in the development and test groups: it logs in development and raises in the test suite (`Bullet.raise = true`), so any request spec with an N+1 fails. `spec/config/bullet_spec.rb` proves it still raises.
- rack-attack is the only limiter (no Rails 8 `rate_limit`). Login and signup use the scaffold's `auth/ip` throttle (10/min per IP), returning 429 with the shared error shape and `Retry-After`. It gets its own `Rack::Attack.cache.store` (Redis in dev/prod, `MemoryStore` in test), since the test `Rails.cache` is a null store.
- **Per-route throttles** (`api/config/initializers/rack_attack.rb`), all returning the same 429 body with `Retry-After`:

  | Rule | Limit | Keyed by |
  | ---- | ----- | -------- |
  | `api/ip` | 300 per 5 min, every `/api/*` request | client IP |
  | `auth/ip` | 10 per min, login and signup | client IP |
  | `search/ip` | 120 per min, `GET /properties` (bursts; `api/ip` caps the sustained rate) | client IP |
  | `watchlist/user` | 60 per min, `PUT`/`DELETE /watchlist/:id` (reads don't count) | user id from the JWT, checked in the middleware without a DB query |

  The web app says so: a rate-limited search or next batch shows "Too many requests in a short time" with Retry (it isn't retried automatically), and a rate-limited watch click rolls back with its own toast. `search/ip` also counts `HEAD` and the `.json` suffix.
- **Cached counts:** `totalCount` (first batch only) comes from `Rails.cache` (Redis) for 60 s, keyed by the parsed filters that change it (not the cursor, limit or user) and by `SearchCache.version`. Every property create, update or delete bumps that version after commit, so all cached counts miss at once; the seed bumps it too, since `insert_all` skips callbacks.
- **No custom ETag on search.** Rails' default `Rack::ETag` hashes the rendered body, and `Rack::ConditionalGet` answers `304 Not Modified` when it matches, so a repeat search saves the transfer but still runs the query. Because the ETag is the body's own hash, a 304 can never hand a browser a body from older code or older data. An ETag computed before the query (from the data version, the user, their watchlist and the params) would also have skipped the query, but it needed a hand-bumped version or a deploy revision to notice code changes; forgetting either would serve old bodies, so it was dropped for the simpler default. `Cache-Control: private, max-age=0, must-revalidate`, so browsers revalidate every time and shared caches never store it.
- **Property types** are a constant list served with `Cache-Control: public, max-age=3600` rather than copied into Redis.
- **No list virtualisation.** Each result card has `content-visibility: auto`, so the browser skips layout and paint for cards far off screen, while every card stays in the DOM, in find-in-page and in the screen-reader list. Its placeholder height is a formula that matches the real card (a 3:2 photo as wide as the grid cell plus a 190 px text block, measured from the list's own width with container units; within a few pixels of the real card at phone, tablet and desktop widths), so Back lands on the same card. Only the height is set: a placeholder width would widen the single phone column. TanStack Virtual would have needed row chunking for the responsive grid, fought router scroll restoration, and hidden off-screen cards from find-in-page and assistive tech; it would pay off at thousands of cards, not hundreds.
- Known gaps: if Redis loses a search cache version bump, cached counts can be stale for up to 60 s (a failed bump is reported); writes that skip callbacks (`update_all`, `insert_all`, `delete`) don't bump it, and nothing in the app uses them on properties outside the seed; in Docker Compose every browser shares one IP bucket for `search/ip` too.

## Notes from a JS/TS developer learning Rails

_To be written as I go._

- What surprised me: _TODO_
- What I hand-rolled and would now replace with a Rails built-in: _TODO_

## What I'd do next

- Admin screens to list, create, edit and delete properties, with changes reaching watchers live.
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
