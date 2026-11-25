import type { Property } from '@/features/properties/types'
import { apiFetch } from '@/lib/api'
import type { Page } from '@/lib/types'

export function fetchWatchlist(cursor: string | null, signal?: AbortSignal) {
  const query = cursor ? `?${new URLSearchParams({ cursor })}` : ''
  return apiFetch<Page<Property>>(`/watchlist${query}`, { signal })
}

/** Idempotent: watching twice is fine. */
export function watchProperty(id: number) {
  return apiFetch<{ data: Property }>(`/watchlist/${id}`, { method: 'PUT' })
}

/** Idempotent: unwatching something not watched is fine. */
export function unwatchProperty(id: number) {
  return apiFetch<void>(`/watchlist/${id}`, { method: 'DELETE' })
}
