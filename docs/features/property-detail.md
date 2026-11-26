# Property page and photos

## What it does

Every listing has a photo, and every card opens the property's own page at
`/properties/:id`: a photo gallery (the main photo, then the rooms the listing has), the status,
price, address, beds/baths/cars/land, the property type and listed date, the description, the price
and status history, the listing agent with "Call" and "Email" links, upcoming open homes in the
listing's local time, the location with an "Open in Google Maps" link, and the Watch button. "Back to results" (or "Back to watchlist")
returns to the same list and scroll position, with keyboard focus on the card that was opened. The page is public, like search; signing in only adds whether you watch it.

| Endpoint | Result |
| -------- | ------ |
| `GET /api/v1/properties/:id` | `{ data: <search shape> + description + history + historyComplete + photos + agent + inspections + timeZone }`. `photos` is the gallery in order, the main photo first (`{ url, caption }`); `agent` is `{ id, name, agency, phone, email }` or null; `inspections` are up to 6 open homes not yet over, soonest first (`{ id, startsAt, endsAt }`, UTC); `timeZone` is the listing's, e.g. `Australia/Perth`. `history` is the 20 most recent price and status changes, newest first; `historyComplete` is false when older ones exist. Any status, sold and withdrawn included. Unknown or malformed id → 404 |

A history entry is `{ id, kind, from, to, createdAt }`: for `price_changed`, `from`/`to` are integer
cents (null when withheld, and **always** null while the property's price is withheld now); for
`status_changed`, status values.

## Where the code is

| File | Role |
| ---- | ---- |
| `api/app/controllers/api/v1/properties_controller.rb` | `show`: the property, its recent events, `watched` for the signed-in user |
| `api/app/controllers/api/v1/base_controller.rb` | `property_id`: the id format check, shared with the watchlist |
| `api/app/resources/property_detail_resource.rb` | `PropertyResource` plus `description` and `history` |
| `api/app/resources/property_event_resource.rb` | One history entry; prices back to integer cents |
| `api/app/resources/agent_resource.rb`, `inspection_resource.rb` | The agent and an open home |
| `api/app/models/agent.rb`, `inspection.rb`, `property_photo.rb` | Agents (contact details only), open homes (`upcoming` scope), gallery photos |
| `api/db/migrate/*_create_agents.rb`, `*_create_inspections.rb`, `*_create_property_photos.rb` | The three tables, `properties.agent_id` (nullified on delete), CHECKs and indexes |
| `api/db/seeds/listing_extras.rb` | Seeds agents (one agency per state), each listing's gallery and its open homes |
| `api/db/migrate/*_add_description_to_properties.rb` | The `description` text column |
| `api/db/seeds/property_generator.rb` | `photo_for` and `description_for` (see [property-data.md](property-data.md)) |
| `web/public/images/properties/` | 60 demo photos (35 outside, 25 rooms and gardens), each at 960×640 and 480×320 (`-480.webp`), and `CREDITS.md` |
| `web/src/components/ui/PropertyCard.tsx` | The card: photo, the stretched address link, `StatusBadge`, `PropertyPhoto` |
| `web/src/features/properties/PropertyPage.tsx` | The page: loading, not-found and error states, details, history, location, back link |
| `web/src/features/properties/PhotoGallery.tsx` | The gallery: previous/next, arrow keys, counter, thumbnails |
| `web/src/features/properties/ListingContact.tsx` | `AgentCard` (call and email links) and `OpenHomes` |
| `web/src/components/ui/photoSources.ts` | `srcSetFor`, `smallPhoto`: the 480 px copies by name |
| `web/src/components/ui/Toggletip.tsx` | The ⓘ button that explains "Under offer" (also used by the search filters) |
| `web/src/features/properties/hooks.ts` | `useProperty`: the detail query, with the cached card as placeholder data |
| `web/src/features/properties/cache.ts` | Watch toggles and live updates reach the cached detail as well as the lists |
| `web/src/router.tsx` | The `/properties/$propertyId` route (code-split); `HistoryState.from` |
| `web/src/components/ui/returnFocus.ts`, `InfiniteResults.tsx` | Focus goes back to the opened card on return |
| `web/src/features/auth/session.ts` | `clearUserData` resets cached property pages on sign-out |
| `web/src/features/watchlist/useToggleWatch.ts` | Reloads an open property page once a watch click settles |

## Rules that must stay true

- **A card has exactly one link, its address, stretched over the card** with `::after`. Screen
  readers hear one link per card, named by the address, and the whole card is still clickable.
  The Watch button sits above it (`relative z-10`) so it toggles instead of opening the page. Don't
  wrap the card in a link: a button inside a link is invalid HTML and breaks keyboard use.
- **The detail response is the search shape plus fields,** so the page can start from a cached card
  (placeholder data) and the same cache helpers patch both. `description` and `history` stay out of
  `PropertyResource`, which search, the watchlist and live updates all send.
- **Every cache helper covers the detail as well as the lists** (`patchCachedProperty`,
  `findCachedProperty`, `applyPropertyUpdate`, `cancelListsHolding`, `newestCachedVersion`), and so
  does `clearUserData` on sign-out. A new helper must too, or a watch click, live update or sign-out
  will show on the cards but not on the page.
- **A watch click on a page still on its first load cancels that load** (it was sent before the
  click and would answer the old `watched`), and the page loads once the click settles. Meanwhile
  `WatchButton` shows the click from the pending mutation (`useMutationState`), because the
  placeholder the page shows is not in the cache, so the patch can't reach it.
- **Focus goes back to a card only on a return to the same history entry** (`__TSR_key`), never on
  a fresh visit to a list, and not after a modified (new-tab) click.
- **While a price is withheld, the history shows no amounts** (`hide_prices` in
  `PropertyEventResource`). Showing what it used to be would undo the agent's choice.
- **The back link comes from the card link's history state** (`from: 'search' | 'watchlist'`),
  never from "is there history": after a login round trip, going back only reaches the login page,
  which bounces straight back.
- **A live update patches the page only when its `version` is newer,** like the cards, then
  refetches the detail, because the message carries no history.
- **The id is checked before use:** the API answers 404 for anything but a plain positive integer
  (and the route has `format: false`, so `/properties/12.0` isn't property 12); the page shows "not
  found" for such an id without calling the API.
- **The 480 px copy is found by name:** `PropertyPhoto` adds a `srcset` only for paths matching
  `/images/properties/<set>-<nn>.webp`. Any other `image_url` (a future upload) gets a plain `src`.
- **Feature lines leave zero counts out** (`featureParts`): "Studio" for a home with no bedroom,
  only the size for land. Never "0 beds · 0 baths".
- **The main photo stays in `properties.image_url`;** `property_photos` holds only the rest, so
  search never joins it. The API puts the main photo first in `photos`.
- **Open-home times show in the listing's time zone** (`timeZone`, from `Property::TIME_ZONES`), with
  the zone added when the viewer is somewhere else: a Perth open home at 10 am never reads as 1 pm.
- **Agent phone numbers come from the ACMA's range reserved for fiction** (`ListingExtras::PHONES`)
  and emails use `example.com`, so the demo can never call or email a real person.
- **"Now" only on the newest status change** ("Now under offer (was for sale)"); older ones read
  "Changed to under offer (was for sale)". A listing can go back on the market, so an older "Now"
  would be false.
- **"Listed for sale at $X" only when X is known:** the oldest price change's `from`, or today's
  price if it never changed; plain "Listed for sale" while the price is withheld or the history is
  cut off.
- **Explanations open on click or tap, never on hover** (`Toggletip`), and sit outside any label
  they explain, so pressing ⓘ never ticks a checkbox. Not on result cards: one more tab stop per
  card, and the cards' `content-visibility: auto` would also break the bubble's `position: fixed`.
- **Only a listing for sale shows open homes.** One that went under offer or sold keeps its rows
  (they come back if it does), but the API returns none and the page says why.
- **Photo URLs are the web app's own paths** (`Property::PHOTO_PATH`, for `image_url` and gallery
  photos), and agent emails can't contain `?` or `#`, so a later admin form can't point visitors
  at an outside host or rewrite the `mailto:` link.
- **Gallery captions are only for rooms the listing has** (no "Bedroom" for a studio, no "Backyard"
  without 200 m² of land), like the write-ups.
- **Photos are served by the web app, not the API.** `image_url` is a path on the web origin
  (`/images/properties/house-01.webp`), so it works through the dev proxy and from any static host (a production web image is planned, not
  built).

## Decision log

- **2026-11-26: Photos and a property page, added after manual QA.** Every card read "No photo" and
  couldn't be opened, which made the app feel broken to anyone looking for a home. The plan had
  scoped photos out and called the detail page optional; this reverses both (see
  [property-data.md](property-data.md) for the seed side).
- **2026-11-26: Real photos stored in the repo** (31 Unsplash photos, credited in `CREDITS.md`;
  about 4.6 MB with the card copies added below), matched to the property type by the seed.
  _Rejected:_ hotlinking an image service (needs the network, and links can break or change);
  drawn placeholders per type (don't look like real listings).
- **2026-11-26: One photo per listing, one size.** 960×640 is about twice a card's width on a
  three-column layout, and the same files repeat across listings, so the browser caches them.
  _Rejected for now:_ a gallery (needs a `property_images` table and upload) and a separate
  thumbnail size.
- **2026-11-26: A `description` column, filled by the seed** from short templates, rather than
  text built from the other fields at request time, so an admin can write a real one later.
- **2026-11-26: Stretched link rather than a clickable `<article>`.** One focusable link per card,
  with the right name, and middle-click / open-in-new-tab work.
  _Rejected:_ an `onClick` on the card (not keyboard-accessible, no link semantics) and wrapping
  the card in `<a>` (invalid with the Watch button inside).
- **2026-11-26: The card's data shows at once while the rest loads** (placeholder data from any
  cached list), so opening a card never flashes a skeleton.
  _Rejected:_ prefetching the detail on hover. With `defaultPreload: 'intent'`, moving the mouse
  across the grid would send a request per card and eat into the per-IP rate limit.
- **2026-11-26: Back is real browser history** when the user came from inside the app, so the
  results, filters and scroll position come back as they were; a "Search properties" link when
  they arrived directly. (Refined below: which it is comes from history state.)
- **2026-11-26: Detail requests share only the general `api/ip` limit** (300 per 5 minutes), not
  `search/ip`. One page view is one request.
- **2026-11-26: Location is a Google Maps link,** built from the stored coordinates.
  _Rejected for now:_ an embedded map (an API key and a third-party script for one feature).

- **2026-11-26: A 480 px copy for cards, chosen with `srcset`** (partly reverses "one size"
  above). The home-buyer walkthrough saw grey boxes for 1–3 s on cards; the card copy is about
  40 KB against 110 KB. The page's main photo loads first (`fetchpriority="high"`, not lazy).
  _Rejected:_ an API field per size (a column for something only the demo photos have).
- **2026-11-26: Feature lines read like a listing site's** ("Studio", no "0 baths", land shows its
  size only), after the walkthrough found "0 beds · 2 baths" confusing.
- **2026-11-26: QA fixes.**
  - The back link is chosen from the card link's history state, after QA found "Back to results"
    did nothing after signing in from the page.
    _Rejected:_ `useCanGoBack` alone (true after the login round trip).
  - A Watch click while the page loads cancels that load and reloads the page once the click
    settles, after QA saw the page say "Watch" while the server said watched. (Revised after the CTO
    review: the first version restarted the load at once, which could still land before the click
    did; the button now shows the in-flight click itself.)
  - Sign-out resets cached property pages too, so the page stops showing "Watching".
  - Focus returns to the opened card (session storage, since the list remounts). Before this, keyboard
    users went back to the top of the page every time. The CTO review found it also fired on a fresh
    visit to a list, focusing a card far down the page, so it now checks the history entry.
  - A long word or URL in a description wraps instead of widening the page.
- **2026-11-26: No amounts in the history while the price is withheld.** QA found
  "Price withheld (was $620,000)" on a listing whose agent had hidden the price, readable by anyone
  through the public API. While `price_cents` is nil, every price event's `from` and `to` are null
  and the page says "Price updated". When a price is shown again, the full history comes back.
  _Rejected:_ dropping price events entirely (the dates still help a buyer); hiding only the last
  withheld amount (earlier events give the same number away).
- **2026-11-26: `historyComplete` from one extra row** (`LIMIT 21`), so the page can say "Earlier
  changes aren't shown" instead of a cut-off list that looks complete.

- **2026-11-26: Agents, open homes and a gallery, on the same branch as the page** (the user asked
  for the walkthrough's property-page gaps here, and the search gaps on a branch of their own).
  The data is seeded; nothing edits it yet (the admin plan should).
- **2026-11-26: Contact is a phone link and an email link,** not an enquiry form.
  _Rejected for now:_ a form that stores enquiries: it collects people's names, emails and phone
  numbers, which needs validation, rate limits, a retention rule and a way to reach the agent, all
  for a demo with fictional agents.
- **2026-11-26: Gallery photos in their own table** (`property_photos`: url, caption, position).
  _Rejected:_ an array column on `properties` (no captions, harder to reorder or upload one at a
  time later).
- **2026-11-26: Open homes are rows with start and end times,** shown while not over (an open home
  under way still shows). They're seeded for the three weeks after seeding, so they run out:
  reseed to get new ones.

- **2026-11-26: From the listing and search QA in another session (the user approved these):**
  - The newest status change says "Now under offer (was for sale)"; older ones "Changed to …".
    _Rejected:_ "Now" on every status line (false once a listing goes back on the market).
  - "Under offer" is explained by an ⓘ toggletip by the price and by the "Exclude under offer"
    filter: "The seller has accepted an offer, but the sale isn't final yet…".
    _Rejected:_ a hover tooltip (phones and keyboards can't use it); a toggletip on every card
    (a tab stop per card).
  - The first history line gives the listing price ("Listed for sale at $850,000").
  - The seed writes price changes, so the history shows prices (see
    [property-data.md](property-data.md)).
- **2026-11-26: Fixes from the second home-buyer walkthrough and QA round:**
  - Write-ups fit the listing's status and type: no "won't last" or "Inspection is highly
    recommended" once it's not for sale, land wording for land, and no "private inspection" line
    next to listed open homes. A studio no longer gets an ensuite.
  - More outside photos (12 houses instead of 8); the one with a "De Witt St" street sign and the
    Queenslander on stilts were swapped out.
  - Open homes at more varied times (Saturdays, Sundays and weekday evenings).
  - An interstate open home also shows your own time ("5:30 pm AWST (8:30 pm your time)"), with
    your weekday when it's a different date where you are.
  - The gallery shows the small copy behind the main photo while it loads (no blank box), moves on
    a sideways swipe, and keeps the current thumbnail in view.
  - The ⓘ bubble is placed with `position: fixed` inside the screen, so it never widens the page on
    a phone, and closes when focus moves away or the page scrolls.
    _Rejected:_ `absolute` under the button (cut off and widening the page near the right edge).
  - Thumbnail buttons are positioned, so their hidden labels can't widen the page either.
  - The call link has the country code (`tel:+61…`), so it works from overseas.
- **2026-11-26: Fixes from the CTO review of the above:**
  - Agent emails can't contain `%` either, so an encoded `?` or `,` can't sneak a recipient into
    the `mailto:` link.
  - Each gallery photo is a fresh `<img>` (keyed by URL), so the caption never runs ahead of a
    photo still loading; the small copy shows through instead.
  - The ⓘ bubble also closes on a resize or rotation, so it can't be left off-screen.
  - The listing-price test uses a price that changed, so it would catch the wrong number.

## Known gaps

- No enquiry form (by choice, see the decision log), no floor plans, no full-screen photo viewer, and
  no "add to calendar" for open homes.
- Open homes are seeded for three weeks after seeding; after that a reseed is needed.
- Descriptions are generated from templates, and 60 photos are shared by 10,000 listings, so
  different homes can look the same, even next to each other in the results.
- Each state has three agents, so the same agent turns up on many listings.
- Sold listings are reachable only from a watchlist or a link: search shows active listings only,
  and there is no sold search or "sold prices nearby" (a search feature, not built).
- The admin form (Milestone 9 in `PRD.md`) should edit `description`, the gallery, the agent and open
  homes; its plan predates all of them. It must also check `image_url` (an outside host would see every visitor's IP), and
  the page has no fallback for a photo that fails to load.
- Live updates reach the page only for properties you watch; anyone else sees a new price when the
  page refetches (after 30 s, on the next visit).
- If the detail fails to load, the error replaces the card's details that were showing.
- A fresh detail doesn't update the cards: a card for a property you don't watch can show an older
  price than its page until search refetches.
- Signing out on the page reloads it, and focus moves to its heading.
- Two cards with the same street address in different suburbs have the same link name for screen
  readers (adding the suburb would change every card heading the tests look up; worth doing with
  them).
- Ids are sequential and public, so sold and withdrawn listings, which search hides, can be listed
  one by one (only `api/ip` limits it).
- Watching while signed out goes to login and back, but the property isn't watched; the user
  clicks again (this predates the page).
- `/properties/` and `/properties/1/extra` show the router's bare "Not Found" (as any unknown
  path does).

## How to check it

- API: `spec/requests/api/v1/property_detail_spec.rb`; `spec/models/agent_spec.rb`,
  `inspection_spec.rb`, `property_photo_spec.rb`; photos, write-ups, agents, galleries and open homes
  in `spec/db/property_generator_spec.rb`.
- Web: `web/src/features/properties/property.test.tsx` (card opens the page, Watch stays a button,
  placeholder data, not found, bad id, retry, watch shows on the cards, live update, the back link
  from the watchlist and after signing in, focus back on the card, a watch click during loading,
  sign-out, the cut-off history, land facts, a reconnect, the gallery, the agent links, open homes,
  "Now" wording, the listing price, the under-offer explainer);
  `format.test.ts` for open-home times across time zones.
- Manually: `make seed`, open `/search`, click any card (photo or address), use "Back to results".
