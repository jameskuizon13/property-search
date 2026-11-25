# Property data

## What it does

The listings everything else searches, watches and updates: the `properties` table, its change
history in `property_events`, the property-type list the UI shows, and a seed that fills a
database with realistic Australian listings. Admin screens to edit properties are planned, not
built; until then data comes from the seed and the `demo:*` rake tasks (see
[live-updates.md](live-updates.md)).

`GET /api/v1/property_types` → `{ data: [{ value: "house", label: "House" }, …] }`, public,
`Cache-Control: public, max-age=3600`.

## Where the code is

| File | Role |
| ---- | ---- |
| `api/db/migrate/*_create_properties.rb` | Columns, CHECK constraints, partial and text indexes |
| `api/db/migrate/*_create_property_events.rb` | The change-history table |
| `api/db/migrate/*_add_description_to_properties.rb` | The listing's write-up, shown on the property page |
| `api/db/migrate/*_add_property_type_bedrooms_statistics.rb` | MCV statistics for narrow searches (see [search.md](search.md)) |
| `api/app/models/property.rb` | Enums, validations, caps, `Property.active`, `format_price`, the change callbacks |
| `api/app/models/property_event.rb` | `price_changed` / `status_changed` rows |
| `api/app/resources/property_resource.rb` | The JSON shape shared by search, the watchlist and live updates |
| `api/app/resources/property_detail_resource.rb`, `property_event_resource.rb` | The property page's shape (see [property-detail.md](property-detail.md)) |
| `api/app/controllers/api/v1/property_types_controller.rb` | The type list, HTTP-cached |
| `api/db/seeds.rb`, `api/db/seeds/property_generator.rb`, `api/db/seeds/suburbs.csv` | Demo accounts and generated listings over 120 real suburb/postcode pairs, each with a photo and a write-up |
| `web/public/images/properties/` | The photos the seed points `image_url` at, with `CREDITS.md` |
| `web/src/features/properties/types.ts`, `format.ts` | The client's `Property` type; price and status formatting |

## Rules that must stay true

- **`Property.active` must match the partial-index predicate exactly**
  (`status IN ('for_sale', 'under_offer')`). If the scope and the index condition drift apart,
  Postgres silently stops using the indexes. A spec runs `EXPLAIN` to check it.
- **Enums are string-backed, with a CHECK constraint each.** Integer enums would turn index
  predicates into `status IN (0, 1)`. The model's lists and the CHECKs must agree; a spec inserts
  every allowed value.
- **Price is two columns:** `price_cents` (nullable, used for filters and sorts) and
  `price_display` (the text on the card, e.g. "Contact agent"). A withheld price is `nil` cents.
- **Write properties with `update!`/`save!`,** never `update_all`/`update_columns`, outside the
  seed. Those skip the callbacks that log events, notify watchers and bump the search cache.
- **One save per transaction.** The commit callback only sees the last save's changes, so a second
  save in the same transaction would log the first change but never broadcast it.
- **The seed stays silent:** `insert_all` on purpose, so seeding broadcasts nothing and writes no
  events except its own status changes (see the decision log). It bumps `SearchCache` itself at the end.

## Decision log

- **2026-11-22: Field names and statuses follow Domain's API.** `minPrice`, `propertyTypes`,
  `for_sale`/`under_offer`/`sold`/`withdrawn`, price and display price kept apart, because many
  listings hide the price. Feels familiar to anyone in the industry.
- **2026-11-22: A short, realestate.com.au-style type list** (9 values).
  _Rejected:_ Domain's 20+ types (noise for a demo).
- **2026-11-22: `property_events` has exactly two kinds,** price and status change, matching what
  Domain's Shortlist alerts on.
- **2026-11-25: `role` added to `users` with the property data,** so the seed can create the admin
  account ahead of the admin screens.
- **2026-11-25: Caps on `price_cents` ($1 billion) and `land_size_sqm` (int max).** Without them an
  oversized value passed validation and then failed the save with a `RangeError`: a 500 instead of
  a 422.
- **2026-11-25: Seed built with Ruby's `Random`, not Faker.** Faker is a dev/test gem, and its
  default street names don't look Australian. A fixed random seed makes it deterministic; listing
  dates are relative to when you seed.
- **2026-11-25: The seed includes edge cases on purpose:** rows sharing a `listed_at` exactly, and
  rows sharing its millisecond but not its microseconds, so the keyset cursor has ties to get right.
- **2026-11-25: Seeding skips itself in test and in production.** In test, CI's `db:prepare` was
  seeding 10,000 rows into the test database. In production the demo accounts have a known
  password; forcing it needs `SEED_DEMO_DATA=1` and `SEED_DEMO_PASSWORD`.
- **2026-11-25: Deleting a property deletes its history** (FK cascade). Admins will be steered to
  status `withdrawn`, which keeps it.
- **2026-11-25: `GET /property_types` is HTTP-cached for an hour,** not copied into Redis: it is a
  Ruby constant, so a Redis copy would add nothing.
- **2026-11-26: The seed gives every listing a photo and a description** (reverses the earlier
  "`image_url` empty, placeholder in the UI"). The photo is one of 31 in
  `web/public/images/properties`, picked from the sets that suit the type (land gets land, an
  apartment gets an apartment building); the description is three short template paragraphs.
  Both come from a second random stream (`random_seed + 1`), so every other generated value is
  unchanged. Details and reasons in [property-detail.md](property-detail.md).
- **2026-11-26: A write-up never contradicts the facts beside it.** Each highlight sentence says
  which listings it fits (an ensuite needs two bathrooms, a backyard needs 200 m² of land), after
  the walkthrough found "1 bath" next to "its own ensuite".
- **2026-11-26: The seed writes one status change for each listing it creates under offer, sold or
  withdrawn** (reverses "the seed writes no events"), dated 1–30 days after listing, so the
  history on a sold listing says when it sold. It still never broadcasts.
- **2026-11-26: `description` is a nullable text column, capped at 5,000 characters,** so a
  listing can be created before its write-up exists.

## Known gaps

- Seed ids come from the table's sequence, so they change on every reseed (`bin/rails demo:watched`
  finds real ones).
- No admin screens yet. The reviewed plan is `.claude/plans/milestone-9-admin.md`.

## How to check it

- `spec/models/property_spec.rb`, `property_event_spec.rb`, `user_spec.rb`,
  `spec/db/property_generator_spec.rb`, `spec/requests/api/v1/property_types_spec.rb`.
- `make seed` (or `SEED_COUNT=100000 make seed` for the `EXPLAIN` plans); details in the README's
  "Seed data".
