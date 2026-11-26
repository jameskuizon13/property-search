# Search

## What it does

Anyone can search active listings by suburb, street or postcode, filter by price, bedrooms,
property type and two "exclude" toggles, sort by newest or price, and scroll through results that
keep loading. Signed-in users also see which results they watch. Filters live in the URL.

`GET /api/v1/properties`: params `q`, `minPrice`, `maxPrice` (whole AUD, inclusive),
`minBedrooms`, `propertyTypes[]` (or comma-separated), `excludeUnderOffer`, `excludePriceWithheld`,
`sort` (`newest` | `price_asc` | `price_desc`), `cursor`, `limit` (default 20, max 50). Response
`{ data: [...], meta: { limit, hasMore, nextCursor?, totalCount? } }`; 422 with every bad field
listed in `error.details`, keyed by the camelCase param name. Booleans accept `true`/`false`/`1`/`0`.
There are no required params, so search never answers 400. `totalCount` comes only with the first
batch.

## Where the code is

| File | Role |
| ---- | ---- |
| `api/app/controllers/api/v1/properties_controller.rb` | Picks the allowed params, renders the page |
| `api/app/queries/properties/search_query.rb` | Parses and validates every param, builds the filters, sort, keyset condition, `watched` join and cached count |
| `api/app/queries/properties/cursor.rb` | The signed cursor: `[sort value, id]`, bound to its sort |
| `api/config/pagination.yml` | Default and maximum `limit` |
| `api/db/migrate/*_create_properties.rb`, `*_statistics.rb` | The indexes this query relies on |
| `api/lib/tasks/search.rake` | `search:explain`, which prints the plans the README shows |
| `web/src/features/properties/searchSchema.ts` | zod schema for the URL (`validateSearch`); turns URL filters into API params |
| `web/src/features/properties/SearchPage.tsx`, `FilterBar.tsx`, `PropertyResultCard.tsx` | The page |
| `web/src/features/properties/api.ts`, `hooks.ts` | `fetchProperties`, `useSearchProperties` (`useInfiniteQuery`), `usePropertyTypes` |
| `web/src/components/ui/InfiniteResults.tsx` | The list shared with the watchlist: sentinel, Load more, skeletons, Retry, end marker, Back to top |
| `web/src/lib/queryKeys.ts` | `propertyKeys.list(filters)` |

## Rules that must stay true

- **Search only ever runs on `Property.active`.** There is no `status` param; sold and withdrawn
  never appear. The scope matches the partial indexes (see [property-data.md](property-data.md)).
- **The cursor stores `listed_at` as integer microseconds,** Postgres's precision. JSON times only
  carry milliseconds, so a millisecond cursor skips or repeats rows that share one. A spec proves it.
- **Cursors are signed (HMAC-SHA256 over a JSON payload, URL-safe) and type-checked** before they
  reach SQL, and record their sort: a cursor
  from another sort, or a forged one, is a 422.
- **One query per page.** `watched` is a `LEFT JOIN` selected as a boolean; `totalCount` is a
  separate `COUNT` on the filtered scope *without* that join (calling `.count` on the relation with
  the custom select breaks the SQL). `bullet` raises on any N+1 in specs.
- **Validation happens in `SearchQuery`, not with `permit`.** `permit` silently drops an array sent
  where one value is expected; `SearchQuery` type-checks every value and answers 422.
- **The URL is the only home of the filters** (no Jotai or `useState` copy), apart from the text box
  while you type. The query key is the normalised filter object, so a filter change is a new cache
  entry and an old response can't land on newer filters.
- **The client never sends what the API would reject.** `searchSchema` drops invalid values from a
  hand-edited URL rather than causing a 422.

## Decision log

- **2026-11-22: Keyset (cursor) pagination, not `OFFSET`.** Stays fast at any depth, and new
  listings never shift rows already loaded.
  _Rejected:_ offset paging (slow deep pages, duplicates when rows are inserted). Accepted limits:
  no jumping to page N, and in a price sort a listing whose price changes mid-scroll can appear
  twice (de-duplicated by `id` on the client) or be missed.
- **2026-11-22: Price sorts leave out withheld prices,** and the UI says so. They have no number to
  sort by, and the partial price index has `price_cents IS NOT NULL`.
- **2026-11-22: Free text matches suburb or street anywhere, postcode by prefix.** Trigram GIN
  indexes serve `ILIKE '%q%'`; a `text_pattern_ops` btree serves `LIKE 'q%'` (`30` finds `3065`).
  `q` under 2 characters is ignored; `%` and `_` match literally.
- **2026-11-25: Extended (MCV) statistics on `(property_type, bedrooms)`.** Postgres assumed the
  columns were independent and walked the whole feed index for "villas, 4+ beds" (34 ms); with the
  statistics it picks the narrow index (0.03 ms). `schema.rb` can't record them, so the seed
  recreates them. Full story and plans: README, "Indexes".
- **2026-11-25: No `COUNT` when the first batch already holds every row.**
- **2026-11-25: A NUL byte in any value is a 422,** not a database error.
- **2026-11-25: Error detail keys are camelCase** (`maxPrice`), like every other JSON key.
- **2026-11-25: Filters in the URL, validated by zod in `validateSearch`.** Survive refresh,
  back/forward and shared links with no sync code. Unknown keys (`utm_source`) are ignored, so they
  don't split the cache or show "Clear filters".
  _Rejected:_ filters in Jotai or Redux (two-way sync with the URL).
- **2026-11-25: The schema accepts both spellings of property types,** a JSON array (what the app
  writes) and the API's comma form (`house,villa`), and drops control characters in `q`, beds over
  5 and a max price below the min. The router merges raw URL values back in for keys the validator
  leaves out, so `validateSearch` always returns every filter key. Type *values* are hard-coded as a
  URL contract; their *labels* come from `GET /property_types`.
- **2026-11-25: Text search is debounced 300 ms** and written with `replace`, so typing doesn't fill
  the history. Text under 2 characters isn't sent.
- **2026-11-25: The sentinel loads the next batch 600 px early,** guarded by
  `hasNextPage && !isFetchingNextPage`. A visible "Load more" button stays mounted while loading and
  turns into "Retry" on failure, so keyboard focus is never dropped.
- **2026-11-25: Every loaded batch stays cached (no `maxPages`),** so Back restores the same list
  and scroll position. Dropping early pages would need backwards cursors.
- **2026-11-25: No footer under the list,** "Back to top" after the first screen (with more than
  one batch loaded), focus moved to the heading, smooth scrolling only without reduced motion. When
  the last batch arrives, focus moves to "End of results". These are the infinite-scroll traps from
  the PRD's risks.
- **2026-11-25: Empty results say which filters to loosen.**
- **2026-11-25: Errors are worded by cause** (connection, server, rejected request), and 4xx errors
  aren't retried automatically.
- **2026-11-26: An ⓘ by "Exclude under offer" explains the term** (`Toggletip`, shared with the
  property page; see [property-detail.md](property-detail.md)). It sits outside the checkbox's
  label, so pressing it doesn't change the filter.

## Known gaps

- No jumping to page N (keyset); offset paging for API clients is planned
  (`.claude/plans/milestone-10-hardening.md`).
- A very common `q` that is rare among the newest listings could scan a lot of the feed index;
  never over 3 ms at 100k rows.
- Filters have no mobile drawer; they wrap.
- A card whose status changes so it no longer matches the filters stays until the next refetch (see
  [live-updates.md](live-updates.md)).

## How to check it

- API: `spec/requests/api/v1/properties_spec.rb` (filters, sorts, cursor walks with ties, 422s,
  `watched`, query count), `spec/queries/properties/cursor_spec.rb`, `spec/config/bullet_spec.rb`.
- Web: `web/src/features/properties/search.test.tsx`.
- Plans: `cd api && SEED_COUNT=100000 bin/rails db:seed:replant && bin/rails search:explain`;
  compare with the README's "EXPLAIN evidence".
