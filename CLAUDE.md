# property-search

A Rails 8.1 API (`api/`) and a Vite + React app (`web/`) for searching Australian property listings
and keeping a live-updating watchlist. How to run it: `README.md`. The plan, milestones and
progress: `PRD.md`.

## Feature docs: read first, update in the same change

`docs/features/` has one living doc per feature (`auth`, `property-data`, `property-detail`, `search`, `watchlist`,
`live-updates`, `performance`). Each lists the code map, the rules that must stay true, a dated
decision log (including what was rejected, and why) and known gaps.

- **Before changing a feature, read its doc.** Don't reintroduce something its decision log says
  was rejected without saying so and asking first.
- **In the same change, update the doc:** the code map if files moved, the rules if one changed, the
  known gaps, and a new decision-log entry for any choice someone could reasonably undo later. Never
  rewrite old entries; add a new one that reverses them.
- **A new feature gets a new doc** in the same shape (see `docs/features/README.md`), added to the
  index there.
- Where a plan in `.claude/plans/` disagrees with a feature doc, the feature doc is right: plans are
  written before building and aren't updated afterwards.

## Docs conventions

- The README describes what is built and what is planned in plain words. It never names
  milestones; milestones, estimates and the progress table live only in `PRD.md`.
- The README's "Design decisions" is a short overview for reviewers that links to the feature docs.
  Keep the detail in the feature doc, not in both places.

## Checks

- `make test` runs both suites (`make test-api`, `make test-web`).
- API: `cd api && bundle exec rspec`, `bin/rubocop`. Web: `cd web && pnpm test`, `pnpm lint`,
  `pnpm typecheck`.
- The pre-commit hook lints and tests the packages a commit touches; pre-push runs
  `bin/rails zeitwerk:check` and `pnpm build`.
