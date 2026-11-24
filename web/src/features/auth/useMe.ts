import { queryOptions, useQuery } from '@tanstack/react-query'
import { fetchMe } from './authApi'

export const authKeys = {
  me: ['me'] as const,
}

export const meQueryOptions = queryOptions({
  queryKey: authKeys.me,
  queryFn: fetchMe,
  staleTime: 5 * 60_000,
})

/** `data` is the signed-in user, `null` when signed out, `undefined` while loading. */
export function useMe() {
  return useQuery(meQueryOptions)
}
