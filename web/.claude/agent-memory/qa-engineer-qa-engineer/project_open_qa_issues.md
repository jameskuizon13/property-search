---
name: project-open-qa-issues
description: Issues reported in the Milestone 5 (search & watchlist UI) QA on 2026-11-25, to re-verify in later milestones
metadata:
  type: project
---

Reported 2026-11-25 (Milestone 5 QA, verdict: ship after small fixes, no blockers):
- InfiniteResults "Load more" / inline "Retry" unmount on click, so focus drops to <body> (keyboard/SR users).
- `?q=` containing a NUL byte reaches the API -> 422 -> "check your connection" error state (schema doesn't strip control chars).
- Unknown URL keys (e.g. utm_source) leak into `filters`: spurious "Clear filters" button and query-key fragmentation.
- ErrorState copy always says "Check your connection" even for 4xx/5xx; query retry:1 retries 4xx.
- Logout navigates to bare /search, dropping URL filters (pre-existing navigate, new impact).
- WatchButton accessible name "Watch <address>" doesn't contain visible "Watching" (WCAG 2.5.3); chip selected state is colour-only.
- Toasts auto-dismiss at 5 s with no pause on hover/focus; Back to top keeps focus at the bottom and ignores reduced motion.

Recurring weak spot: focus management when buttons are conditionally rendered; client/server validation parity.
**Why:** next QA should confirm these were fixed or consciously accepted.
**How to apply:** re-run the repro for each at the start of the next milestone QA. See [[project-qa-setup]].
