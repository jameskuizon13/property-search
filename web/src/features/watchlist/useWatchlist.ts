import { useInfiniteQuery } from '@tanstack/react-query'
import { watchlistKeys } from '@/lib/queryKeys'
import { nextCursor } from '@/lib/types'
import { fetchWatchlist } from './api'

/** The signed-in user's watched properties, most recently added first. */
export function useWatchlist() {
  return useInfiniteQuery({
    queryKey: watchlistKeys.list(),
    queryFn: ({ pageParam, signal }) => fetchWatchlist(pageParam, signal),
    initialPageParam: null as string | null,
    getNextPageParam: nextCursor,
  })
}
