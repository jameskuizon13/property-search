import type { PropertyTypeValue } from './searchSchema'

export type PropertyStatus = 'for_sale' | 'under_offer' | 'sold' | 'withdrawn'

/** The API's PropertyResource: one shape for search, the watchlist and (Milestone 6) live updates. */
export type Property = {
  id: number
  streetAddress: string
  suburb: string
  state: string
  postcode: string
  priceCents: number | null
  priceDisplay: string
  bedrooms: number
  bathrooms: number
  carSpaces: number
  landSizeSqm: number | null
  propertyType: PropertyTypeValue
  status: PropertyStatus
  listedAt: string
  imageUrl: string | null
  latitude: number | null
  longitude: number | null
  /** The property's `lock_version`: live updates apply only when newer than the cached card's. */
  version: number
  watched: boolean
}

/** One entry in a property's history. Prices are integer cents (null when withheld). */
export type PropertyEvent =
  | { id: number; kind: 'price_changed'; from: number | null; to: number | null; createdAt: string }
  | { id: number; kind: 'status_changed'; from: PropertyStatus; to: PropertyStatus; createdAt: string }

/** `GET /properties/:id`: the list shape plus what only the property page shows. */
export type PropertyDetail = Property & {
  description: string | null
  /** The most recent price and status changes, newest first. Amounts are null while the price is withheld. */
  history: PropertyEvent[]
  /** False when older changes exist beyond `history`. */
  historyComplete: boolean
}

/** What `WatchlistChannel` sends when a watched property's price or status changes. */
export type PropertyUpdatedMessage = {
  type: 'property.updated'
  /** The REST shape; `watched` is always true (only watchers receive it). */
  property: Property
  /** Only the attributes that changed, as `[old, new]`. */
  changes: { priceCents?: [number | null, number | null]; status?: [PropertyStatus, PropertyStatus] }
}
