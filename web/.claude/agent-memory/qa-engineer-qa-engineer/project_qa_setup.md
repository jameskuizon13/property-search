---
name: project-qa-setup
description: How to run and exercise the property-search app for QA (servers, demo login, browser tricks), plus demo-data hygiene rules
metadata:
  type: project
---

- Dev servers are usually already running: Rails API on :3000, Vite web on :5173 (proxies /api and /cable). Fallback: `make api` / `make web` from repo root. Web checks: `cd web && pnpm test|lint|typecheck|build` (dist is gitignored, tsc -b leaves the tree clean).
- Demo login is seeded (local only) and given in the brief; the demo user's watchlist was EMPTY as of 2026-11-25. Always unwatch anything you watched and leave the browser signed out.
- Avoid creating new accounts unless the user asks directly; signup 422 paths (taken email, short password) can be tested without creating one.
- Built-in browser works well: inject a `window.fetch` wrapper via javascript_tool to fake 401/500/503 for specific API paths (the app's apiFetch reads global fetch at call time). Same-origin iframes are a fast way to probe many /search?… URLs and read `performance` resource entries.
- BroadcastChannel cross-tab tests work with tabs_create; install a MutationObserver on the `[aria-label="Notifications"]` list to capture toasts (they auto-dismiss after 5 s).

**Why:** saves recon time next milestone; demo data is shared with the developer's manual testing.
**How to apply:** start every QA run here; re-verify the open issues in [[project-open-qa-issues]].
