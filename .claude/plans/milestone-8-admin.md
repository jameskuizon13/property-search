# Milestone 8 — Admin UI for properties: implementation plan

Branch: `feature/milestone-8-admin`, stacked on Milestone 7's branch while those PRs are open.
Source: PRD user story 7, FR-7, API design (admin rows + paragraph), Frontend architecture (admin
routes, `admin/` feature folder, `requireAdmin`), Data model (`updated_at` index), Testing strategy
(admin request specs, `PropertyForm` tests), Delivery plan → Milestone 8.

The seed already creates `admin@example.com` (role `admin`); `GET /me` already returns `role`.

## API

1. **Migration:** btree `(updated_at DESC, id DESC)` on `properties` (not partial: the admin list
   shows every status). README gets its `EXPLAIN` for the default admin list page.
2. **`Api::V1::Admin::BaseController < Api::V1::BaseController`**: `before_action :authenticate!`,
   then `require_admin!` (403 `forbidden`, "Admins only"). The role is read from the DB user loaded
   for this request (`current_user.admin?`), never from the token or a param. The existing CSRF
   `Origin` check is inherited.
3. **`Api::V1::Admin::PropertiesController`** (routes under `namespace :admin`, `format: false`):
   - `index`: `page` (≥ 1, default 1), `perPage` (1–100, default 50), `q` (same rules as search:
     trimmed, ignored under 2 chars, max 100; matches suburb/street ILIKE or postcode prefix, all
     statuses). Bad values → 422 with camelCase details. Order `updated_at DESC, id DESC`,
     `OFFSET`/`LIMIT`. `meta: { page, perPage, totalCount, totalPages }`. A page past the end returns
     `data: []` with the real totals (UI clamps). A small `Admin::PropertiesQuery` object keeps the
     controller thin and reuses `SearchQuery`'s text matcher (extract `Properties::TextMatch`).
   - `show`: one property (`AdminPropertyResource`).
   - `create`: 201; 422 with field errors.
   - `update` (`PATCH`): requires `lockVersion` (missing → 400 `parameter_missing`); assigns it and
     saves, so Rails' optimistic locking raises `StaleObjectError` → 409 `stale_record` ("This
     property was changed by someone else. Reload to see the latest version.").
   - `destroy`: 204; watchlist items and events cascade (FKs).
   - Ids validated like the watchlist (`/\A[1-9]\d{0,18}\z/`, else 404).
   - `rescue_from ActiveRecord::StaleObjectError` → 409 in `Api::V1::BaseController` (PRD error map).
4. **Params:** body `{ "property": { …camelCase… } }`. Allow-list: `streetAddress, suburb, state,
   postcode, latitude, longitude, priceCents, priceDisplay, bedrooms, bathrooms, carSpaces,
   landSizeSqm, propertyType, status, listedAt, imageUrl`. Keys are underscored after permitting;
   every value must be a JSON scalar (string/number/null) or it's a 400, as `string_params` does for
   auth. `id`, timestamps, `lockVersion` (only via the top-level param on update) and anything
   unknown are never mass-assigned. Create defaults `listed_at` to now when omitted.
5. **`price_display` default** (`Property` `before_validation`): when blank, it becomes the formatted
   price, or "Contact agent" when the price is withheld. The admin form leaves it blank unless the
   agent wants custom text ("Auction", "Offers over $800k"), so a price change never leaves the old
   display text behind.
6. **`AdminPropertyResource`**: every field of `PropertyResource` (minus `watched`) plus
   `lockVersion`, `createdAt`, `updatedAt`.
7. **`GET /api/v1/admin/property_options`**: `{ propertyTypes: [{value,label}], statuses: [...],
   states: [...] }` from the model constants, so the form's dropdowns come from the API (FR-7).
8. Live updates need nothing new: admin writes go through `update!`, so `property_events` and the
   cable broadcast fire as with the rake tasks (spec'd).

## Web

9. **`requireAdmin`** (`features/auth/requireAdmin.ts`): signed out → `/login?next=…`; signed in but not
   admin → redirect to `/search` (and a toast "Admins only" via a search flag? No: keep it a plain
   redirect; the server's 403 is the real check). Routes carry `staticData: { requiresAuth: true }`
   so logout leaves them.
10. **Routes** (code-split): `/admin/properties` (search params `page`, `q` validated with zod and
    `.catch`), `/admin/properties/new`, `/admin/properties/$id/edit` (`$id` must be a positive int,
    else not-found view).
11. **Nav:** an "Admin" link shown only when `useMe().data?.role === 'admin'`.
12. **`AdminPropertiesPage`** (`features/admin/`): text filter (debounced 300 ms into the URL,
    `replace`), a real `<table>` with caption and column headers (address, suburb/state/postcode,
    price, type, status, updated), each address linking to its edit page; "Add property" button;
    numbered pager (`nav aria-label="Pagination"`, previous/next, a window of page numbers with
    `aria-current="page"`). Loading skeleton rows, empty state, inline error with Retry. A page
    past the end redirects to the last page. `useAdminProperties(page, q)` with
    `placeholderData: keepPreviousData` so paging doesn't flash.
13. **`PropertyForm`** (create and edit): grouped fields with labels; type, status and state as
    `<select>`s from `property_options`; price in **dollars** (converted to cents), blank = withheld;
    price text optional ("Leave blank to show the price"); beds/baths/cars/land size number inputs;
    listed date (`datetime-local`) on create; lat/long optional. 422 → errors next to each field
    (camelCase keys map 1:1 to field names) and focus moves to the first invalid field; form-wide
    errors (500, network) → toast. 409 → an inline alert with a "Reload latest" button (refetches,
    resets the form) — inline because it needs an action, per the toast rule. Success → toast
    ("Property created" / "Changes saved"), back to the list, and invalidate the admin queries plus
    `propertyKeys.lists()` and `watchlistKeys.all`.
14. **Delete:** a "Delete" button on the edit page opens an inline confirmation panel (focus moves
    into it; Escape/Cancel closes and returns focus) that says the property also leaves every
    watchlist and offers "Mark as withdrawn instead" (a PATCH with `status: withdrawn`) next to
    "Delete permanently". Success → toast and back to the list.
15. Field and API types in `features/admin/types.ts`; query keys in `lib/queryKeys.ts` (`adminKeys`).

## Tests

- **API request specs** (`spec/requests/api/v1/admin/properties_spec.rb`, `property_options_spec.rb`):
  401 signed out, 403 normal user (each endpoint), admin index paging/meta/q/ordering/bad params,
  page past end, show, create 201 + 422 field errors (camelCase), `role`/`id`/`lockVersion`
  ignored on create, non-scalar value → 400, update ok, missing lockVersion → 400, stale → 409,
  delete 204 + watchlist rows gone, 404 bad ids, foreign Origin 403, a price change by an admin
  writes a `property_events` row and broadcasts to watchers, blank `priceDisplay` auto-fills.
  Bullet stays quiet. Model spec for the `price_display` default.
- **Web** (`features/admin/admin.test.tsx`): normal user redirected away from `/admin/properties`;
  signed out → login with `next`; admin link only for admins; table renders + pager changes page
  in the URL; filter writes `q`; form shows 422 errors next to the right inputs; 409 shows the
  reload alert and Reload refetches; create success toast + navigation; delete confirm → DELETE;
  "Mark as withdrawn instead" → PATCH with status.

## Docs

README: admin section (routes, how to use with live updates in a second window, demo login),
Where things live, Demo logins (admin now has screens), Trying the live updates (admin variant),
EXPLAIN for the admin list, Build progress tick. PRD: anything that changed (property_options
endpoint, price_display default, delete confirmation as inline panel).

## Out of scope

User/role management, CSV import, image uploads, audit log (PRD out of scope / Milestone 9 list);
notifying watchers when a property is deleted (it simply disappears from their watchlist on next
refetch; documented as a gap).

## Changes after plan review (APPROVE WITH CHANGES)

Verified by the reviewer: assigning `lock_version` then saving raises `StaleObjectError` in
activerecord 8.1.4.1; an explicit `property` key disables param wrapping.

1. `price_display` recompute: when blank, OR when `price_cents` changes, `price_display` doesn't, and
   the old display equals the auto text for the old price (`format_price(old)` / "Contact agent").
   Custom text ("Auction") is kept. Specs for each case.
2. Replace `validate_presence_of(:price_display)` in property_spec (blank is now filled).
3. `lockVersion`: top-level, must be a non-negative integer (JSON integer or digit string) → else 400.
   Specs for null, "abc", array.
4. Params: check raw `params[:property]` is a hash and every value a scalar BEFORE permit; use
   `params.expect`; reject NUL bytes; `wrap_parameters false` in `Admin::BaseController`.
5. Cap `page` at 10,000 (422). UI clamps to page 1 when `totalPages` is 0.
6. `listedAt`: send `new Date(local).toISOString()`; default shown in local time; blank → now
   (`listed_at.presence`). Editable on edit too (FR-7 "every field").
7. Dollars: whole dollars only, `Math.round(n * 100)`, blank → null; `priceCents` errors map onto the
   dollars input with a dollar message.
8. After save/withdraw set/invalidate the admin detail query; edit route `staleTime: 0`; Reload
   remounts the form (`key={lockVersion}`); alert says unsaved edits are lost; withdraw PATCH sends
   `lockVersion` and handles 409.
9. 403 from admin API → refetch `me`, toast, redirect to /search (no Retry). 404 on edit/PATCH →
   toast, back to list.
10. `clearUserData` removes `adminKeys.all`.
11. `image_url`: http(s) only, ≤ 2048 chars; in the form. `listedAt` in the form.
12. Tests for all of the above (API: 3–5, 403 on property_options, display recompute on PATCH, NUL;
    web: logout from /admin → /search, 403 redirect, body has cents + ISO listedAt, q resets page).
Optional taken: one of `version`/`lockVersion` only (keep `lockVersion` in the admin resource);
copy the ILIKE matcher (don't extract); reuse FormField; `role="alert"` on 409; live region for
result count; `aria-disabled` pager ends; delete panel heading + `aria-labelledby`; document OFFSET
paging can skip/repeat rows during edits.
