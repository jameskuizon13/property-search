# Feature docs

One living doc per feature: what was built, where the code is, the rules a change must not break,
and **why** things are the way they are, including the options that were turned down. Read the doc
before changing a feature; update it in the same change.

| Doc | Covers |
| --- | ------ |
| [auth.md](auth.md) | Sign up, log in, log out, `/me`, the JWT cookie, CSRF, cable auth, error envelope, signed-out handling in the web app |
| [property-data.md](property-data.md) | The `properties` and `property_events` tables, models, enums, constraints, seed data, `GET /property_types` |
| [search.md](search.md) | `GET /properties`, `Properties::SearchQuery`, the keyset cursor, indexes, the search page, filters in the URL, the infinite list |
| [watchlist.md](watchlist.md) | Watchlist API, the watch toggle, the watchlist page |
| [live-updates.md](live-updates.md) | Change events, `PropertyChangeNotifier`, `WatchlistChannel`, the client's cache patching, demo rake tasks |
| [performance.md](performance.md) | Rate limits, cached counts, HTTP caching, N+1 detection, cheap long lists |

## Where else things are written

| Place | Holds |
| ----- | ----- |
| [PRD.md](../../PRD.md) | The plan written before building: requirements, the milestone order, estimates and progress |
| [README.md](../../README.md) | How to run the app, and a short overview of the design for reviewers (threat model, `EXPLAIN` plans) |
| `docs/features/` | How each feature works **now**, and the decisions behind it, added to as it changes |
| `.claude/plans/` | The implementation plans written before each milestone, including the changes asked for in plan review. Historical: where a plan and a feature doc disagree, the feature doc is right |

## How to write an entry

Each doc has the same sections:

1. **What it does:** a few lines, plus the endpoints and screens.
2. **Where the code is:** the files that matter and what each one does.
3. **Rules that must stay true:** invariants a change could break by accident. Each says why.
4. **Decision log:** newest last, one entry per decision:

   ```markdown
   - **2026-11-25: Short name of the decision.** What was decided and why.
     _Rejected:_ the alternative, and why it lost.
   ```

   Add an entry whenever a choice is made that someone could reasonably undo later, especially
   when an obvious option was turned down. Don't rewrite old entries; if a decision is reversed,
   add a new entry that says so and links back.
5. **Known gaps:** what is accepted as not handled, and what is planned next.
6. **How to check it:** the specs, tests and manual steps that prove it works.
