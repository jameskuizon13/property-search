import { z } from 'zod'

/**
 * The search filters live in the URL, validated here (the route's
 * `validateSearch`). The URL is their only home: no copy in Jotai, so
 * back/forward, refresh and shared links work with no sync code.
 *
 * Property-type values are hard-coded (a URL contract); their labels come from
 * GET /property_types. Anything invalid in a hand-edited URL is dropped
 * quietly instead of sending the API a request it would reject with a 422.
 */
export const PROPERTY_TYPES = [
  'house',
  'apartment_unit',
  'townhouse',
  'villa',
  'land',
  'acreage',
  'rural',
  'block_of_units',
  'retirement_living',
] as const
export type PropertyTypeValue = (typeof PROPERTY_TYPES)[number]

export const SORTS = ['newest', 'price_asc', 'price_desc'] as const
export type Sort = (typeof SORTS)[number]

export const BEDROOM_OPTIONS = [1, 2, 3, 4, 5] as const

/** Whole AUD. The price selects only offer these. */
export const PRICE_STEPS = [
  100_000, 200_000, 300_000, 400_000, 500_000, 600_000, 700_000, 800_000, 900_000, 1_000_000, 1_250_000, 1_500_000,
  2_000_000, 2_500_000, 3_000_000, 4_000_000, 5_000_000, 10_000_000,
]

const MAX_PRICE = 1_000_000_000
const MAX_Q_LENGTH = 100
/** Shorter text is ignored by the API, so it isn't sent (or cached) either. */
export const MIN_Q_LENGTH = 2

export type SearchFilters = {
  q?: string
  minPrice?: number
  maxPrice?: number
  minBedrooms?: number
  propertyTypes?: PropertyTypeValue[]
  excludeUnderOffer?: true
  excludePriceWithheld?: true
  sort?: Sort
}

/** A patch from the filter bar: `undefined` or `false` clears a filter. */
export type FilterPatch = { [K in keyof SearchFilters]?: SearchFilters[K] | false }

const price = z.number().int().min(0).max(MAX_PRICE).optional().catch(undefined)
const flag = z.literal(true).optional().catch(undefined)

/** NUL and other control characters: the API rejects them with a 422. */
const hasControlChars = (text: string) => [...text].some((ch) => ch.charCodeAt(0) < 32 || ch.charCodeAt(0) === 127)

const isPropertyType = (value: unknown): value is PropertyTypeValue =>
  PROPERTY_TYPES.includes(value as PropertyTypeValue)

/**
 * Drops default and empty values so they never appear in the URL, and a max
 * price below the min (the UI blocks it; a hand-edited URL can't force a 422).
 */
export function cleanFilters(filters: FilterPatch): SearchFilters {
  const out: SearchFilters = {}
  if (filters.q) out.q = filters.q
  if (typeof filters.minPrice === 'number') out.minPrice = filters.minPrice
  if (typeof filters.maxPrice === 'number' && !(out.minPrice != null && filters.maxPrice < out.minPrice)) {
    out.maxPrice = filters.maxPrice
  }
  if (filters.minBedrooms) out.minBedrooms = filters.minBedrooms
  if (filters.propertyTypes && filters.propertyTypes.length > 0) out.propertyTypes = filters.propertyTypes
  if (filters.excludeUnderOffer) out.excludeUnderOffer = true
  if (filters.excludePriceWithheld) out.excludePriceWithheld = true
  if (filters.sort && filters.sort !== 'newest') out.sort = filters.sort
  return out
}

export const searchSchema = z
  .object({
    // The router parses `?q=3065` as a number, so accept that and turn it back into text.
    q: z
      .preprocess(
        (v) => (typeof v === 'number' ? String(v) : v),
        z
          .string()
          .trim()
          .max(MAX_Q_LENGTH)
          .refine((text) => !hasControlChars(text)),
      )
      .optional()
      .catch(undefined),
    minPrice: price,
    maxPrice: price,
    minBedrooms: z.number().int().min(1).max(BEDROOM_OPTIONS.length).optional().catch(undefined),
    // A JSON array (what the app writes) or the API's comma form, `house,villa`.
    propertyTypes: z
      .preprocess((v) => (typeof v === 'string' ? v.split(',') : v), z.array(z.unknown()))
      .transform((values) => [...new Set(values.filter(isPropertyType))])
      .optional()
      .catch(undefined),
    excludeUnderOffer: flag,
    excludePriceWithheld: flag,
    sort: z.enum(SORTS).optional().catch(undefined),
  })
  .transform(cleanFilters)

const NO_FILTERS: { [K in keyof Required<SearchFilters>]: undefined } = {
  q: undefined,
  minPrice: undefined,
  maxPrice: undefined,
  minBedrooms: undefined,
  propertyTypes: undefined,
  excludeUnderOffer: undefined,
  excludePriceWithheld: undefined,
  sort: undefined,
}

/**
 * The route's `validateSearch`. Every filter key is returned, `undefined` when
 * dropped: the router merges the raw URL values back in for any key the
 * validator leaves out, which would let `?sort=bogus` through.
 */
export function parseSearchFilters(search: Record<string, unknown>): SearchFilters {
  return { ...NO_FILTERS, ...searchSchema.parse(search) }
}

/**
 * What is actually sent (and used as the query key): text under 2 characters
 * is left out, as the API would ignore it, so typing one letter doesn't
 * refetch identical results. Types are sorted so their order doesn't matter.
 */
export function toApiFilters(filters: SearchFilters): SearchFilters {
  const { q, ...rest } = filters
  return {
    ...rest,
    ...(q && q.length >= MIN_Q_LENGTH && { q }),
    ...(rest.propertyTypes && { propertyTypes: [...rest.propertyTypes].sort() }),
  }
}

export function isPriceSort(filters: SearchFilters) {
  return filters.sort === 'price_asc' || filters.sort === 'price_desc'
}
