---
name: qa-environment
description: How to run property-search for QA alongside another session (alt ports), demo accounts, seed id range, tricks for testing live updates, rate limits and ETags
metadata:
  type: reference
---

- Another session often holds ports 3000/5173. Run QA copies on 3001/5174:
  `cd api && FRONTEND_ORIGIN=http://localhost:5174 bin/rails server -p 3001 -P tmp/pids/qa-server.pid`,
  `cd web && API_PROXY_TARGET=http://localhost:3001 pnpm dev --port 5174 --strictPort`. Stop via the pid file / `pkill -f "vite.*--port 5174"`.
- Demo logins are in the README / seed (demo@example.com user, admin@example.com admin). Seeded property ids are NOT 1..n (were 130001..140000 on 2026-11-25); find real ids with `bin/rails demo:watched` or a runner.
- Dev cable uses shared Redis, so rake/runner broadcasts reach every running dev server.
- Live-update testing: a MutationObserver on `ol[aria-label=Notifications]` records toast times; `WatchlistChannel.broadcast_to(user, payload)` from `bin/rails runner` injects stale/duplicate messages; a raw `new WebSocket('ws://localhost:5174/cable', ['actioncable-v1-json'])` from the page tests stream auth. Delay `/api/v1/properties` by monkeypatching window.fetch, then navigate client-side with history.pushState + popstate.
- Origin check: `curl --http1.1` with Upgrade headers to /cable returns 404 for a disallowed Origin, 101 + unauthorized disconnect without a cookie.
- `api/spec` rspec run takes ~6 s; web `pnpm test` ~3 s.
- Rate limits (M7): counters are in the Docker Redis (`docker exec property-search-redis-1 redis-cli --scan --pattern 'rack-attack*'`), shared with the other session's servers; curl and the vite proxy both key as `::1`. Snapshot keys before/after a request to see which throttles matched without exhausting them. Keep api/ip (300/5min) well under the limit or everything on the machine is locked out for 5 min.
- ETag 304s show in `api/log/development.log` ("Completed 304"), not in the browser network tool (fetch sees 200).
- `demo:change_property` writes property_events rows; delete the ones you create afterwards.

Open issues to re-verify: M6 [[m6-open-issues]] (search stuck on "Loading properties" if a live update lands during first load; no toast when the card isn't cached; "$2M → $2M" rounding). M7 (2026-11-25): mobile (<602px) horizontal overflow from `contain-intrinsic-size` single value applying to width; Back restoration off by most of a card on mobile; next-batch 429 shows generic text; `.json` suffix and HEAD skip search/ip.
