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
  watched: boolean
}
