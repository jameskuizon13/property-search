import { useMutation, useQueryClient, type QueryClient } from '@tanstack/react-query'
import { useRouter } from '@tanstack/react-router'
import { useToast } from '@/components/ui/toast'
import { findCachedProperty, patchCachedProperty } from '@/features/properties/cache'
import { ApiError } from '@/lib/api'
import { propertyKeys, watchlistKeys } from '@/lib/queryKeys'
import { unwatchProperty, watchProperty } from './api'

/**
 * Per query client and property: the last state the server confirmed, kept
 * while a run of clicks is in flight so a failed last click can go back to it.
 */
const confirmedByClient = new WeakMap<QueryClient, Map<number, boolean>>()

function confirmedStates(queryClient: QueryClient) {
  let states = confirmedByClient.get(queryClient)
  if (!states) confirmedByClient.set(queryClient, (states = new Map()))
  return states
}

/**
 * Watch or unwatch one property. Each call says the state wanted (not
 * "toggle"), so the end state is the last click's. Mutations for the same
 * property share a `scope`, so they run one after another in click order: a
 * PUT and a DELETE can never finish out of order.
 *
 * The card updates at once in every cached list. If a request fails and no
 * later click is queued, it goes back to the last state the server confirmed
 * and a toast says so; a later click decides otherwise.
 */
export function useToggleWatch(propertyId: number) {
  const queryClient = useQueryClient()
  const router = useRouter()
  const toast = useToast()
  const scopeId = `watch-${propertyId}`
  const confirmed = confirmedStates(queryClient)
  // Clicks for this property not yet finished, this one included: TanStack
  // runs onMutate/onError/onSettled while the mutation still counts as pending.
  const clicksInFlight = () => queryClient.isMutating({ predicate: (m) => m.options.scope?.id === scopeId })

  return useMutation({
    scope: { id: scopeId },
    mutationFn: async (watch: boolean) => {
      await (watch ? watchProperty(propertyId) : unwatchProperty(propertyId))
    },
    onMutate: async (watch) => {
      if (clicksInFlight() === 1) {
        confirmed.set(propertyId, findCachedProperty(queryClient, propertyId)?.watched ?? !watch)
      }
      // A batch already loading copied the pages before this click and would
      // write them back over the patch, undoing it. Cancelling sends it back
      // to its earlier state; the list's sentinel then asks for it again.
      await Promise.all([
        queryClient.cancelQueries({ queryKey: propertyKeys.lists() }),
        queryClient.cancelQueries({ queryKey: watchlistKeys.all }),
      ])
      patchCachedProperty(queryClient, propertyId, { watched: watch })
    },
    onSuccess: (_data, watch) => {
      confirmed.set(propertyId, watch)
    },
    onError: (error) => {
      // A 401 already signed the user out (apiFetch's handler); send them to
      // sign in and back here instead of reporting a failed watch.
      if (error instanceof ApiError && error.status === 401) {
        const { pathname, href } = router.state.location
        if (pathname !== '/login') void router.navigate({ to: '/login', search: { next: href } })
        return
      }
      if (clicksInFlight() > 1) return
      patchCachedProperty(queryClient, propertyId, { watched: confirmed.get(propertyId) })
      toast("Couldn't update your watchlist. Please try again.", 'error')
    },
    onSettled: () => {
      if (clicksInFlight() > 1) return
      confirmed.delete(propertyId)
      // Mark the watchlist stale without refetching it now: on the watchlist
      // page an unwatched card stays put (one click re-watches it) instead of
      // vanishing under the cursor. It refreshes on the next visit.
      void queryClient.invalidateQueries({ queryKey: watchlistKeys.all, refetchType: 'none' })
    },
  })
}
