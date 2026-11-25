import type { InfiniteData, QueryClient } from '@tanstack/react-query'
import { propertyKeys, watchlistKeys } from '@/lib/queryKeys'
import type { Page } from '@/lib/types'
import type { Property } from './types'

type PropertyPages = InfiniteData<Page<Property>>

const PROPERTY_LISTS = [propertyKeys.lists(), watchlistKeys.all]

function patchPages(data: PropertyPages | undefined, id: number, patch: Partial<Property>) {
  if (!data) return data
  let changed = false
  const pages = data.pages.map((page) => {
    if (!page.data.some((p) => p.id === id)) return page
    changed = true
    return { ...page, data: page.data.map((p) => (p.id === id ? { ...p, ...patch } : p)) }
  })
  return changed ? { ...data, pages } : data
}

/**
 * Updates one property in every cached search batch and the watchlist.
 * Untouched pages and cards keep their identity, so only that card re-renders.
 * Used by the watch toggle now, and by live updates in Milestone 6.
 */
export function patchCachedProperty(queryClient: QueryClient, id: number, patch: Partial<Property>) {
  for (const queryKey of PROPERTY_LISTS) {
    queryClient.setQueriesData<PropertyPages>({ queryKey }, (data) => patchPages(data, id, patch))
  }
}

/** The property as currently cached, from whichever list has it. */
export function findCachedProperty(queryClient: QueryClient, id: number): Property | undefined {
  for (const queryKey of PROPERTY_LISTS) {
    for (const [, data] of queryClient.getQueriesData<PropertyPages>({ queryKey })) {
      for (const page of data?.pages ?? []) {
        const found = page.data.find((p) => p.id === id)
        if (found) return found
      }
    }
  }
  return undefined
}
