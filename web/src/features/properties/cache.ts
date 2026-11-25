import type { InfiniteData, QueryClient, QueryKey } from '@tanstack/react-query'
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
 * Used by the watch toggle (live updates use applyPropertyUpdate).
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

/**
 * Puts a live update into every cached list, card by card: only a card whose
 * `version` is older than the update's is replaced, so a late or repeated
 * message never puts an older price back, even when the search batches and
 * the watchlist hold different versions. The card keeps its own `watched`
 * flag: a click still in flight decides that, not the broadcast. Returns
 * whether any card changed.
 */
export function applyPropertyUpdate(queryClient: QueryClient, update: Property) {
  let applied = false
  const { watched: _ignored, ...fields } = update
  const replace = (data: PropertyPages | undefined) => {
    if (!data) return data
    let changed = false
    const pages = data.pages.map((page) => {
      if (!page.data.some((p) => p.id === update.id && p.version < update.version)) return page
      changed = true
      return {
        ...page,
        data: page.data.map((p) => (p.id === update.id && p.version < update.version ? { ...p, ...fields } : p)),
      }
    })
    if (!changed) return data
    applied = true
    return { ...data, pages }
  }
  for (const queryKey of PROPERTY_LISTS) {
    queryClient.setQueriesData<PropertyPages>({ queryKey }, replace)
  }
  return applied
}

function holds(data: unknown, id: number) {
  return !!(data as PropertyPages | undefined)?.pages?.some((page) => page.data.some((p) => p.id === id))
}

/**
 * Cancels list fetches in flight, but only for lists that already show this
 * property: a fetch started before a patch copied the old rows and would write
 * them back over it. Call before patching, then call the returned `resume`
 * after it.
 *
 * - A cancelled next batch goes back to its earlier state, and the list's
 *   sentinel asks for it again.
 * - A cancelled full refetch (a reconnect, an invalidation) would otherwise
 *   just stop, leaving the list stale with nothing to refetch it, so `resume`
 *   starts it again. Its fresh rows carry the new version, so they can't undo
 *   the patch.
 * - A list still on its first load holds no card and is left alone:
 *   cancelling it would leave it stuck on its skeletons.
 */
export async function cancelListsHolding(queryClient: QueryClient, id: number) {
  const interrupted: QueryKey[] = []
  await Promise.all(
    PROPERTY_LISTS.map((queryKey) =>
      queryClient.cancelQueries({
        queryKey,
        predicate: (query) => {
          if (!holds(query.state.data, id)) return false
          if (query.state.fetchStatus === 'fetching' && !query.state.fetchMeta?.fetchMore) {
            interrupted.push(query.queryKey)
          }
          return true
        },
      }),
    ),
  )
  return function resume() {
    for (const queryKey of interrupted) void queryClient.refetchQueries({ queryKey, exact: true })
  }
}

/** The highest `version` of this property in any cached list, or undefined if none holds it. */
export function newestCachedVersion(queryClient: QueryClient, id: number) {
  let newest: number | undefined
  for (const queryKey of PROPERTY_LISTS) {
    for (const [, data] of queryClient.getQueriesData<PropertyPages>({ queryKey })) {
      for (const page of data?.pages ?? []) {
        for (const p of page.data) if (p.id === id && (newest === undefined || p.version > newest)) newest = p.version
      }
    }
  }
  return newest
}
