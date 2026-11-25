# Auth

## What it does

Users sign up, log in and log out. The API keeps them signed in with one JWT in an `HttpOnly`
cookie, valid for a fixed 24 hours. The same cookie authenticates the WebSocket. Search is public;
the watchlist and the live-updates socket need sign-in. Every error, from any endpoint, comes back
in one JSON shape.

| Endpoint | Auth | Result |
| -------- | ---- | ------ |
| `POST /api/v1/auth/signup` | – | 201 + user, sets the cookie; 422 with field errors |
| `POST /api/v1/auth/login` | – | 200 + user, sets the cookie; 401 `invalid_credentials`; 429 when throttled |
| `DELETE /api/v1/auth/logout` | – | 204 always; clears the cookie and closes the user's sockets |
| `GET /api/v1/me` | yes | The user, including `role` |

Web: login and signup pages, a guard on protected routes, and handling for being signed out from
elsewhere (a 401, or a logout in another tab).

## Where the code is

| File | Role |
| ---- | ---- |
| `api/app/services/auth_token.rb` | Issues and verifies the JWT; cookie options; the secret and its length check |
| `api/app/controllers/api/v1/base_controller.rb` | `current_user`, `authenticate!`, `sign_in`/`sign_out`, the `Origin` check (`verify_origin!`) |
| `api/app/controllers/api/v1/auth_controller.rb`, `me_controller.rb` | The four endpoints |
| `api/app/controllers/application_controller.rb` | `rescue_from` → JSON errors; `string_params` (rejects non-strings and NUL bytes) |
| `api/lib/json_exceptions_app.rb` | JSON for unknown routes and 500s (`config.exceptions_app`) |
| `api/lib/client_ip.rb` | The client IP for rate limits, believing `X-Forwarded-For` only from `TRUSTED_PROXIES` |
| `api/app/channels/application_cable/connection.rb` | Signs the socket in from the same cookie |
| `api/app/models/user.rb`, `api/app/resources/user_resource.rb` | User rules; the JSON shape (never `password_digest`) |
| `api/config/application.rb` | Cookie middleware, `FRONTEND_ORIGIN` parsing, the JSON exceptions app |
| `api/config/initializers/` | `auth_token.rb` (boot-time secret check), `cors.rb`, `rack_attack.rb` (`auth/ip`), `filter_parameter_logging.rb` |
| `web/src/lib/api.ts` | `apiFetch`: `credentials: 'include'`, error parsing, the 401 hook |
| `web/src/features/auth/` | Forms, `useMe`, `useAuthMutations`, `requireAuth`, `safeNext`, `session.ts` (clear user data, `BroadcastChannel`), `useSessionEvents` |
| `web/src/routes/AuthPages.tsx`, `RootLayout.tsx` | The login and signup pages; the header with sign-in state |

## Rules that must stay true

- **The web app never sees the token.** No `localStorage`, no JS memory: an injected script must
  have nothing to steal. `apiFetch` sends `credentials: 'include'` and that is all.
- **Every write passes the `Origin` check.** `POST`/`PUT`/`PATCH`/`DELETE` must carry an `Origin`
  in `FRONTEND_ORIGIN`, or get 403. Request specs set it with the `json_headers` helper; one spec
  leaves it out on purpose.
- **REST and the socket use one check.** Both go through `AuthToken.user_from`. A second way to
  authenticate would be a second place to get it wrong.
- **`role` is never a param.** Sign-up always creates a normal user; only the seed makes an admin.
- **Errors never leak internals.** Everything goes through `rescue_from` or `JsonExceptionsApp`;
  bad input types are 400s, not 500s.
- **`?next=` only takes same-app paths** (`safeNext`), checked again after normalising.
- **A login form's 401 is a wrong password,** not a sign-out (it opts out with `allowUnauthorized`).

## Decision log

- **2026-11-23: JWT in an `HttpOnly` cookie, not a session cookie or a `Bearer` header.** The brief
  names JWT; it carries an explicit `exp` and is checked by one code path for REST and ActionCable.
  _Rejected:_ a token in `localStorage` (readable by XSS); Rails' encrypted session cookie (also
  fine, but no explicit claims and not what the brief names).
- **2026-11-23: Fixed 24-hour expiry, no renewal.** Kept the first milestone small.
  _Rejected for now:_ sliding renewal with a 14-day cap. Planned, see `.claude/plans/milestone-9-hardening.md`.
- **2026-11-23: Nothing stored on the server.** No session table, so logout can't cut off a copied
  token; it stays valid until `exp`. Accepted trade-off. _Planned:_ a `sessions` table with
  revocation and "log out everywhere".
- **2026-11-23: CSRF = `SameSite=Lax` + `Origin` check.** Two layers with no token to manage.
  _Rejected:_ a double-submit CSRF token (more moving parts for little gain at this size).
- **2026-11-23: rack-attack only, no Rails 8 `rate_limit`.** The scaffold already had it and its
  JSON 429. It needs its own store, because the test `Rails.cache` is a null store.
- **2026-11-25: Logout disconnects the user's sockets on every device.** One line, no
  per-connection bookkeeping; other devices reconnect with their still-valid cookie. Best effort:
  if Redis is down the error is reported and the cookie is still cleared.
- **2026-11-25: The default JWT key is derived, not reused.** `key_generator.generate_key("auth/jwt")`
  instead of `secret_key_base` itself; `JWT_SECRET` under 32 bytes refuses to boot, since a short
  HS256 key can be brute-forced from any user's own cookie.
- **2026-11-25: Production refuses to boot** without `FRONTEND_ORIGIN`, or with an entry that isn't
  a bare origin, instead of answering every write with a silent 403.
- **2026-11-25: `ip_spoofing_check` is off.** It raised an empty 500 above the error handler; rate
  limits use `ClientIp`, not `remote_ip`.
- **2026-11-25: Signed out from elsewhere = clear the user's data, toast, re-run route guards.**
  Only a protected page goes to `/login?next=…`; search stays put in its signed-out view. Another
  tab's logout arrives over `BroadcastChannel('auth')`.
  _Rejected:_ always redirecting to login (search doesn't need an account).
- **2026-11-25: Toasts for form-wide errors and confirmations; field errors stay inline.** A field
  error must stay next to its input while it's fixed. Toasts live in an always-present
  `aria-live="polite"` region, last 5 s (errors 10 s) and pause while hovered or focused.
- **2026-11-25: Logout keeps you where you are on a public page** (filters kept) and leaves
  `/watchlist` for search. If the logout request fails, the app says so and keeps you signed in,
  since the cookie may still be valid; a 401 there counts as already signed out. A tab that was
  already signed out shows nothing when another tab logs out.

## Known gaps

From the README's threat model, still true:

- Signup reveals whether an email is registered. Hiding it needs email verification.
- Rate limits use fixed one-minute windows (up to ~20 attempts across a boundary).
- In Docker Compose every browser shares one rate-limit bucket (the Vite container is the peer).
- Zero clock leeway on `iat`; several API instances need synced clocks.
- An open socket outlives its token until it drops or the user logs out.
- Malformed JSON bodies are logged raw in development (Rails' debug-level parse error, password
  included). Production logs at `info` and doesn't write them.
- `app.` + `api.` subdomains need a reverse proxy or a configurable API base URL.

Planned next: sliding renewal, sessions with revocation, per-email login throttling, breached
passwords, 2FA (`.claude/plans/milestone-9-hardening.md`, PRD "Security hardening").

## How to check it

- API: `spec/requests/api/v1/auth_spec.rb`, `me_spec.rb`, `spec/services/auth_token_spec.rb`,
  `spec/channels/application_cable/connection_spec.rb`, `spec/requests/errors_spec.rb`,
  `rate_limit_spec.rb`, `spec/lib/client_ip_spec.rb`, `spec/config/filter_parameters_spec.rb`.
- Web: `web/src/features/auth/auth.test.tsx`, `safeNext.test.ts`, `web/src/lib/api.test.ts`.
- Threat model with the spec for each control: README, "Design decisions → Auth".
- By hand: sign in as `demo@example.com` in two tabs, log out in one; the other shows "You were
  signed out in another tab".
