# Property Search

A small property search app, built for a fullstack coding challenge (3–4 h timebox).
Users search Australian listings, filter by price, bedrooms and property type, scroll through
results that keep loading, open any listing for its photo, description and price history, and save properties to a watchlist that updates live when a watched
property's price or status changes. The Docker Compose project is called `property-search`.

**Status:** built: auth and minimum security, property data and seeds, the search and watchlist
APIs, the search and watchlist UI, live watchlist updates, rate limits and caching, and listing
photos with a page for each property. Admin screens
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
there are more than Rails' defaults. How each feature works, and why, is in
[docs/features/](docs/features/README.md).

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
  seeding never broadcasts. The only `property_events` it writes are its own: a status change for each
  listing it creates under offer, sold or withdrawn, and a price change or two for about one in five
  listings with a price, so the history on a property page has something to show.
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
  names from its default locale don't look Australian.
- **Agents, galleries and open homes:** 24 agents (three per state, at a made-up agency, with phone
  numbers from the range the ACMA reserves for fiction and `example.com` emails), a gallery of the
  rooms each listing has, and open homes in the three weeks after you seed. Reseed to get new ones.
- **A photo and a write-up for every listing:** `image_url` points at one of 35 outside photos in
  `web/public/images/properties/` (from Unsplash, credited in `CREDITS.md` there) chosen to suit the
  property type, and `description` is three short generated paragraphs. If your database was
  seeded before these existed, run `make seed` again to get them.

## Folder structure

Two apps side by side. `web/` calls `api/` over HTTP (`/api/v1/...`) and a WebSocket (`/cable`);
in development Vite proxies both, so the browser only ever talks to one origin.

```
property-search/
├── api/                 Rails JSON API + ActionCable
├── web/                 React single-page app (Vite)
├── docs/features/       one living doc per feature: how it works and why
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
9. **Property page and photos:** more resources (`PropertyDetailResource`, `PropertyEventResource`,
   `AgentResource`, `InspectionResource`), three small models (`Agent`, `Inspection`,
   `PropertyPhoto`), `db/seeds/listing_extras.rb`, and `web/public/images/properties/` for the listing photos, which the
   web app serves as static files.

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
   `demo@example.com` in both.
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

The short version for reviewers. Each feature's full reasoning (what was chosen, what was turned
down and why, the rules a change must keep, and the known gaps) lives in
[docs/features/](docs/features/README.md).

### Auth ([PRD](PRD.md#security-hardening))

- One HS256 JWT in an `HttpOnly; SameSite=Lax` cookie (`Secure` in production), with a fixed 24 h
  expiry. One code path (`AuthToken`) checks it for REST and for the WebSocket, and the web app
  never sees the token.
- CSRF protection is `SameSite=Lax` plus an `Origin` check against `FRONTEND_ORIGIN` on every write.
- Trade-off: nothing is stored server-side, so a token copied before logout stays valid until it
  expires. Revocation and sliding renewal are [planned](PRD.md#security-hardening).
- Being signed out from elsewhere (a 401, or a logout in another tab) clears the user's data and
  shows a toast; only a protected page goes to `/login?next=…`.
- Why each choice, what was rejected, and the code map: [docs/features/auth.md](docs/features/auth.md).

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

Known, accepted gaps (signup reveals registered emails, fixed rate-limit windows, a socket that
outlives its token, and more) are listed in [docs/features/auth.md](docs/features/auth.md#known-gaps).

### Real-time ([PRD](PRD.md#real-time-design-actioncable))

- A price or status change writes a `property_events` row in the same transaction. Watchers are told
  only after commit, inline (no job), on one `WatchlistChannel` stream per user.
- The message reuses the REST shape plus `version` (the row's `lock_version`). The client replaces a
  cached card only when the message is newer than that card, so a late or repeated message can't put
  an older price back.
- After a reconnect the watchlist refetches and search is marked stale, since messages sent while
  offline are gone.
- Details: [docs/features/live-updates.md](docs/features/live-updates.md).

### Search & pagination ([PRD](PRD.md#api-design))

- Keyset pagination with a signed cursor (`[sort value, id]`, with `listed_at` in microseconds, the
  precision Postgres stores), so deep pages cost the same as the first.
- Search only returns active listings (`for_sale`, `under_offer`); there is no `status` param.
- Every param is type-checked, and a bad request gets a 422 listing every bad field at once.
- `watched` comes from one `LEFT JOIN`, so a page is one query; the total is a separate, cached `COUNT`.
- The watchlist API is keyed on the property (`PUT`/`DELETE /watchlist/:propertyId`), idempotent, and
  always scoped to `current_user`, so there is no IDOR.
- Honest limits: no jumping to page N, and in a price sort a listing whose price changes mid-scroll
  can appear twice (de-duplicated on the client) or be missed.
- Params, decisions and known gaps: [docs/features/search.md](docs/features/search.md) and
  [docs/features/watchlist.md](docs/features/watchlist.md).

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

- Filters live only in the URL, checked by a zod schema that quietly drops invalid values instead of
  sending a request the API would reject.
- One `InfiniteResults` list serves search and the watchlist. It loads the next batch 600 px before
  the end and has a "Load more" button for keyboard users, skeletons, inline Retry, an end marker and
  "Back to top". Every loaded batch stays cached, so Back returns to the same place.
- The watch toggle changes the card at once. Clicks for one property run in order, and a failure goes
  back to the last state the server confirmed, with a toast.
- Every card has a photo and opens the property's page: a photo gallery, description, details, price
  and status history, the agent with call and email links, upcoming open homes (in the listing's
  local time), a Google Maps link and the watch toggle. The address is the card's one link,
  stretched over the whole card, so the Watch button still only toggles. Opened from a card, the
  page shows the card's details at once while the rest loads; "Back to results" returns to the same
  place. Details: [docs/features/property-detail.md](docs/features/property-detail.md).
- Toasts by default; field errors and a search that fails to load stay on the page.
- Accessibility: the watch button is a real toggle (`aria-pressed`), toasts are announced
  (`aria-live`), and selected chips show a tick, not just a colour.
- Details: [docs/features/search.md](docs/features/search.md) and
  [docs/features/watchlist.md](docs/features/watchlist.md).

### N+1, rate limiting & caching ([PRD](PRD.md#non-functional-requirements))

- `bullet` raises in the test suite, so any request spec with an N+1 query fails.
- rack-attack is the only rate limiter. Every rule returns 429 with the shared error shape and
  `Retry-After`:

  | Rule | Limit | Keyed by |
  | ---- | ----- | -------- |
  | `api/ip` | 300 per 5 min, every `/api/*` request | client IP |
  | `auth/ip` | 10 per min, login and signup | client IP |
  | `search/ip` | 120 per min, `GET /properties` | client IP |
  | `watchlist/user` | 60 per min, watchlist writes | user id from the JWT, no DB query |

- Search's `totalCount` is cached in Redis for 60 s, keyed by the filters and a version that every
  property change bumps.
- Search uses Rails' default ETag (a hash of the body): a 304 saves the transfer and can never serve
  an old body. A custom ETag that also skipped the query was tried and dropped.
- Long lists aren't virtualised: each card has `content-visibility: auto`, so off-screen cards skip
  layout and paint but stay findable and readable by screen readers.
- Why each choice, and the known gaps: [docs/features/performance.md](docs/features/performance.md).

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
- On the property page: an enquiry form, floor plans, a full-screen photo viewer, "add to calendar"
  for open homes, and an embedded map.
- Move `PropertyChangeNotifier` into a Solid Queue job with retries once fan-out grows; lograge JSON logs.

---

Full plan, requirements and trade-offs: [PRD.md](PRD.md).
