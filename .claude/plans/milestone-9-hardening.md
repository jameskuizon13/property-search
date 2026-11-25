# Milestone 9 — Focused security hardening & extras: implementation plan

Branch: `feature/milestone-9-hardening`, stacked on Milestone 8's branch while those PRs are open.
Scope chosen by the user (2026-11-25): sliding renewal + 14-day cap, a sessions table with
revocation and `GET`/`DELETE /auth/sessions` (log out everywhere), a per-email login throttle,
offset paging, lograge. Everything else in the PRD's Milestone 9 list stays documented as "next".
Source: PRD Security hardening → "Milestone 9 — nice-to-have hardening", API design (sessions
rows, offset paging), Observability row, README "What I'd do next" and auth known gaps.

## 1. Server-side sessions (revocation)

- **Migration** `sessions`: `user_id` (FK, `on_delete: cascade`), `public_id` (string, 32 hex chars
  from `SecureRandom.hex(16)`, unique index; never the DB id in the token), `expires_at` (login +
  14 days, the hard cap), `revoked_at` (nullable), `last_seen_at`, `user_agent` (string ≤ 255,
  truncated), `ip` (string, from `ClientIp`), timestamps. Index `(user_id, revoked_at)` for the
  device list and "log out everywhere".
- **`Session` model** (`app/models/session.rb`; check the name doesn't clash with Rails'
  `ActionDispatch::Session` — it lives in a module, so a top-level `Session` is the Rails 8
  generator's own choice): `belongs_to :user`; scope `active` → `revoked_at IS NULL AND expires_at > now`;
  `revoke!`.
- **Token** (`AuthToken`): payload gains `sid` (the session's `public_id`) and `auth_time` (login
  time, integer). `encode(session, now:)`; `exp = min(now + 24 h, session.expires_at)`.
  `decode` returns a small `Claims` struct (`user_id`, `sid`, `iat`, `auth_time`) or nil, with the
  existing strict checks plus `sid` format and `auth_time <= iat`. `session_from(token)` →
  `Session.active.includes(:user).find_by(public_id: sid, user_id:)` (one query with the user, the
  same cost as today's `User.find_by`). Tokens issued before this milestone (no `sid`) are rejected,
  so everyone signs in once more (documented).
- **Sign-in** creates a `Session` (user agent, IP) and sets the cookie; **logout** revokes the
  current session (and still clears the cookie, idempotently, as now).
- **`BaseController#current_user`** goes through `current_session`. `current_session` is memoised.
- **Cable** `ApplicationCable::Connection`: `identified_by :current_user, :current_session`;
  revoking a session disconnects that session's sockets
  (`ActionCable.server.remote_connections.where(current_session: s).disconnect`, best effort like
  logout now). This also closes the known gap "an open WebSocket outlives its token" for revocation.

## 2. Sliding renewal with the 14-day cap

- In `BaseController`, an `after_action`-free approach: when `current_session` is loaded from a
  token whose `iat` is more than 1 hour old, re-issue the cookie with a fresh `iat` and
  `exp = min(now + 24 h, session.expires_at)`, and set `session.last_seen_at` (one UPDATE at most
  once an hour per session). Done lazily inside `current_session`, so only requests that
  authenticate pay. Not on `logout` / `DELETE /auth/sessions` (they clear the cookie).
- After 14 days from login, the session is expired: the next request is a 401 and the user signs
  in again.
- The JWT check stays strict (`exp`, `iat`, no leeway); renewal never extends past the cap.

## 3. Device list and "log out everywhere"

- `GET /api/v1/auth/sessions` (auth): the user's active sessions, newest first:
  `{ id: public_id, current: bool, createdAt, lastSeenAt, userAgent, ip }`.
- `DELETE /api/v1/auth/sessions` (auth): revoke every active session of the user (this one too),
  disconnect all their sockets, clear the cookie → 204. Web broadcasts `signed-out` to other tabs.
- `DELETE /api/v1/auth/sessions/:id` (auth): revoke one of the user's own sessions (scoped through
  `current_user.sessions`, so another user's id is a 404); if it's the current one, also clear the
  cookie → 204.
- Web: an **Account** page (`/account`, protected) with a "Signed-in devices" table: device (user
  agent shortened to browser + OS by a tiny parser, full string in `title`), signed in, last
  active, "This device" badge, a "Sign out" button per row, and "Sign out of all devices"
  (confirm inline). Results as toasts. The header's user name links to it.

## 4. Per-email login throttle

- rack-attack `auth/email`: `POST /api/v1/auth/login`, keyed by the normalised email
  (`strip.downcase`) read from the JSON body (body ≤ 4 KB parsed; anything unparsable → no key),
  two windows: 5 per minute and 20 per hour ("escalating"). Same 429 body + `Retry-After`.
  Counted on every attempt (rack-attack can't see the outcome). Trade-off documented: someone can
  lock a known email out of login for up to an hour; the IP limit still applies first; the fix is
  CAPTCHA / per-IP+email pairs, listed as next.

## 5. Offset paging (API clients)

- `GET /properties?offset=N` (0–10,000) when no `cursor` is sent; both → 422; offset > 10,000 → 422.
  `ORDER BY … LIMIT limit+1 OFFSET offset`; `meta.nextOffset` instead of `nextCursor`; `totalCount`
  on the first page (`offset` 0 or absent) as now. Included in the ETag key parts. Price sorts
  still drop withheld prices. The web app keeps using cursors.

## 6. lograge

- `gem "lograge"`; enabled in production (and opt-in in development with `LOGRAGE=1`): one JSON
  line per request with `request_id`, `user_id` (from the memoised session, never re-queried),
  status, duration, and params filtered by `filter_parameters`. Health check `/up` excluded.
  A spec asserts the custom options and filtering on a sample payload.

## Tests

- Model: `Session.active` (revoked, expired), `revoke!`.
- `AuthToken`: `sid`/`auth_time` required; exp capped at session expiry; old tokens without `sid`
  rejected; tampered `sid`.
- Requests (auth_spec, sessions_spec): login creates a session; logout revokes it (old cookie then
  401); renewal re-issues the cookie after 1 h but not before, never past 14 days; at 14 days a 401;
  `GET /auth/sessions` lists own only, `current` flag; `DELETE /auth/sessions` revokes all + 401
  everywhere; `DELETE /auth/sessions/:id` for own / other user's (404) / current (cookie cleared);
  Origin check on the DELETEs; IDOR.
- Cable: a revoked session's connection is rejected; revocation disconnects (`have_received`
  on remote_connections).
- Rate limit: 6th login for one email in a minute → 429 from different IPs; other emails fine;
  case/whitespace variants share a bucket; malformed JSON doesn't crash; hourly window.
- Offset paging: walk all rows with offsets; cursor + offset → 422; bounds; meta.
- lograge config spec.
- Web: account page lists devices, signs out one (row disappears, toast), sign out everywhere
  (redirect to /login? → to /search signed out with toast, BroadcastChannel posted); header link.

## Docs

README: Auth section (sessions, renewal, cap, revocation; threat-model rows updated; known gaps
updated — "open WebSocket outlives its token" now partly closed), Account page in UI notes, API
offset paging, logging, per-email throttle in the throttle table, Build progress tick 9, "What I'd
do next" trimmed to what's left. PRD: Milestone 9 list marks what was built.

## Changes after plan review (APPROVE WITH CHANGES; section 4 redesigned)

Verified: `RemoteConnection#valid_identifiers?` requires every `identified_by` key (actioncable 8.1.4.1).

1. Cable: `identified_by :current_user, :current_session`; every `remote_connections.where` passes
   both keys. Revoke (commit) first, then `disconnect(reconnect: false)`. Logout disconnects only its
   own session; "log out everywhere" plucks active sessions first and disconnects each.
2. Renewal in an `after_action` (not inside `current_session`): only when `@current_session` was
   loaded, no sign-out happened, and it wasn't revoked this request. Runs on 304s too (spec it).
   Cookie `expires` = the token's `exp`.
3. Per-email throttle moves into `AuthController#login`, failures only: key = SHA-256 of
   `User.normalize_value_for(:email, …)`; check counters before bcrypt → 429 + `Retry-After`;
   increment on failure in `Rack::Attack.cache.store`; tiers (email, IP) 5/min and email 20/h.
   `format: false` on auth routes. Document the remaining lockout risk.
4. `AuthToken.decode` returns Claims: update rack_attack (`claims&.user_id`), connection, specs.
5. `Session.active.eager_load(:user)` (1 query); `last_seen_at` via conditional `update_all`.
6. Login/signup revoke the session of any valid cookie already present (rotation).
7. Offset: add to `SEARCH_PARAMS`; absent ≡ 0 (and `offset=` empty ≡ absent) in key parts; total only
   when no cursor and offset 0; no `next_cursor` in offset mode; no `nextOffset` past the 10,000 bound.
8. lograge: `base_controller_class = "ActionController::API"`; `request_id` + `user_id` from
   `@current_session&.user_id` via `append_info_to_payload`; ignore `Rails::HealthController#show`;
   `payload[:params]` minus controller/action/format; note rack-attack 429s don't reach it.
9. `DELETE /auth/sessions/:id`: `format: false`, `id: /\h{32}/`; `Cache-Control: no-store` on GET.
Tests: the review's list (real internal-channel broadcast on logout/revoke, single deletion
Set-Cookie on logout with an old token, renewed cookie on 304, throttle bypass attempts, revoke
between load and renewal, watchlist throttle still keyed by user, no session query on public
requests from lograge, offset ETags and bound).
Optional taken: drop `auth_time` (DB `expires_at` is the cap); `sessions:prune` rake task; show the
user agent truncated rather than parsing it; document that a socket can outlive the 14-day cap.
