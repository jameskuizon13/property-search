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

/** What `WatchlistChannel` sends when a watched property's price or status changes. */
export type PropertyUpdatedMessage = {
  type: 'property.updated'
  /** The REST shape; `watched` is always true (only watchers receive it). */
  property: Property
  /** Only the attributes that changed, as `[old, new]`. */
  changes: { priceCents?: [number | null, number | null]; status?: [PropertyStatus, PropertyStatus] }
}
