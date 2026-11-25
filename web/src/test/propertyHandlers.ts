import { http, HttpResponse } from 'msw'
import type { Property } from '@/features/properties/types'
import type { PageMeta } from '@/lib/types'

let addressCounter = 0

export function makeProperty(overrides: Partial<Property> = {}): Property {
  const id = overrides.id ?? ++addressCounter + 1000
  return {
    id,
    streetAddress: `${id} Smith St`,
    suburb: 'Fitzroy',
    state: 'VIC',
    postcode: '3065',
    priceCents: 85_000_000,
    priceDisplay: '$850,000',
    bedrooms: 3,
    bathrooms: 2,
    carSpaces: 1,
    landSizeSqm: 320,
    propertyType: 'house',
    status: 'for_sale',
    listedAt: '2026-11-01T00:00:00Z',
    imageUrl: null,
    latitude: null,
    longitude: null,
    watched: false,
    ...overrides,
  }
}

export function makeProperties(count: number, firstId = 1, overrides: Partial<Property> = {}) {
  return Array.from({ length: count }, (_, i) => makeProperty({ id: firstId + i, ...overrides }))
}

export function page(data: Property[], meta: Partial<PageMeta> = {}) {
  return HttpResponse.json({ data, meta: { limit: 20, hasMore: false, ...meta } })
}

export const propertyTypes = [
  { value: 'house', label: 'House' },
  { value: 'apartment_unit', label: 'Apartment & Unit' },
  { value: 'townhouse', label: 'Townhouse' },
  { value: 'villa', label: 'Villa' },
  { value: 'land', label: 'Land' },
]

/** Defaults for every test: an empty search, an empty watchlist and the type list. */
export const defaultPropertyHandlers = [
  http.get('*/api/v1/property_types', () => HttpResponse.json({ data: propertyTypes })),
  http.get('*/api/v1/properties', () => page([], { totalCount: 0 })),
  http.get('*/api/v1/watchlist', () => page([], { totalCount: 0 })),
]

export const serverError = () =>
  HttpResponse.json({ error: { code: 'internal_error', message: 'Something went wrong' } }, { status: 500 })
