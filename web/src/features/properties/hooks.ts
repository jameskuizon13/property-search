import { useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query'
import { propertyKeys } from '@/lib/queryKeys'
import { nextCursor } from '@/lib/types'
import { fetchProperties, fetchProperty, fetchPropertyTypes, type PropertyTypeOption } from './api'
import { findCachedProperty } from './cache'
import type { SearchFilters } from './searchSchema'
import type { PropertyDetail } from './types'

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

/**
 * One property's page. Opened from a card, it shows that card's data at once
 * (placeholder data, with no description or history yet) while the full
 * detail loads. The default retry policy already leaves a 404 alone.
 */
export function useProperty(id: number, { enabled = true } = {}) {
  const queryClient = useQueryClient()
  return useQuery({
    enabled,
    queryKey: propertyKeys.detail(id),
    queryFn: ({ signal }) => fetchProperty(id, signal),
    placeholderData: (): PropertyDetail | undefined => {
      const card = findCachedProperty(queryClient, id)
      return (
        card && {
          description: null,
          history: [],
          historyComplete: true,
          photos: card.imageUrl ? [{ url: card.imageUrl, caption: 'Main photo' }] : [],
          agent: null,
          inspections: [],
          timeZone: '',
          ...card,
        }
      )
    },
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
