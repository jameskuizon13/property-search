import { useInfiniteQuery, useQuery } from '@tanstack/react-query'
import { propertyKeys } from '@/lib/queryKeys'
import { nextCursor } from '@/lib/types'
import { fetchProperties, fetchPropertyTypes, type PropertyTypeOption } from './api'
import type { SearchFilters } from './searchSchema'

/**
 * Search results in batches. A new filter object is a new query key, so
 * changing a filter starts again from the first batch, and a slow response
 * for old filters only ever lands in the old filters' cache entry. All loaded
 * batches stay cached (no maxPages), so going back restores the same list.
 */
export function useSearchProperties(filters: SearchFilters) {
  return useInfiniteQuery({
    queryKey: propertyKeys.list(filters),
    queryFn: ({ pageParam, signal }) => fetchProperties(filters, pageParam, signal),
    initialPageParam: null as string | null,
    getNextPageParam: nextCursor,
    staleTime: 30_000,
  })
}

const propertyTypesQuery = { queryKey: propertyKeys.types, queryFn: fetchPropertyTypes, staleTime: Infinity }

export function usePropertyTypes() {
  return useQuery(propertyTypesQuery)
}

const toLabels = (options: PropertyTypeOption[]): Record<string, string> =>
  Object.fromEntries(options.map((o) => [o.value, o.label]))

/** value → label, e.g. `apartment_unit` → "Apartment & Unit". Undefined until loaded. */
export function usePropertyTypeLabels() {
  return useQuery({ ...propertyTypesQuery, select: toLabels }).data
}

/** Until the labels load, `apartment_unit` shows as "Apartment unit". */
export function fallbackLabel(value: string) {
  const text = value.replaceAll('_', ' ')
  return text.charAt(0).toUpperCase() + text.slice(1)
}
