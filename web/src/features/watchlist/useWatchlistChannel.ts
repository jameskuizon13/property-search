import { useQueryClient, type QueryClient } from '@tanstack/react-query'
import { useSetAtom } from 'jotai'
import { useEffect } from 'react'
import { useToast } from '@/components/ui/toast'
import { useMe } from '@/features/auth/useMe'
import { applyPropertyUpdate, cancelListsHolding, newestCachedVersion } from '@/features/properties/cache'
import { describeChanges } from '@/features/properties/format'
import type { PropertyUpdatedMessage } from '@/features/properties/types'
import { getConsumer } from '@/lib/cable'
import { cableStatusAtom } from '@/lib/cableStatus'
import { propertyKeys, watchlistKeys } from '@/lib/queryKeys'

function isPropertyUpdate(message: unknown): message is PropertyUpdatedMessage {
  if (typeof message !== 'object' || message === null) return false
  const { type, property, changes } = message as Partial<PropertyUpdatedMessage>
  return (
    type === 'property.updated' &&
    typeof property?.id === 'number' &&
    typeof property.version === 'number' &&
    typeof changes === 'object' &&
    changes !== null
  )
}

/**
 * Per query client: the newest version of each property this client has
 * announced, so a repeated message never toasts twice even when no list
 * holds the card.
 */
const announcedByClient = new WeakMap<QueryClient, Map<number, number>>()

function announced(queryClient: QueryClient) {
  let versions = announcedByClient.get(queryClient)
  if (!versions) announcedByClient.set(queryClient, (versions = new Map()))
  return versions
}

/**
 * Live watchlist updates, mounted once in the root layout. While signed in it
 * holds one `WatchlistChannel` subscription (the server streams only this
 * user's updates). Each update patches every cached card older than it and
 * shows a toast, so the card changes in place on search and the watchlist.
 */
export function useWatchlistChannel() {
  const { data: user } = useMe()
  const userId = user?.id
  const queryClient = useQueryClient()
  const toast = useToast()
  const setStatus = useSetAtom(cableStatusAtom)

  useEffect(() => {
    if (userId === undefined) return

    setStatus('connecting')
    const subscription = getConsumer().subscriptions.create('WatchlistChannel', {
      connected({ reconnected }: { reconnected: boolean }) {
        setStatus('connected')
        if (!reconnected) return
        // Updates sent while the socket was down are gone: refetch the
        // watchlist and any open property page, and mark search stale so it
        // refreshes on its next view instead of refetching every loaded batch now.
        void queryClient.invalidateQueries({ queryKey: watchlistKeys.all })
        void queryClient.invalidateQueries({ queryKey: propertyKeys.details() })
        void queryClient.invalidateQueries({ queryKey: propertyKeys.lists(), refetchType: 'none' })
      },
      disconnected({ willAttemptReconnect }: { willAttemptReconnect: boolean }) {
        // false: the server refused us (e.g. the cookie expired) or we closed it.
        setStatus(willAttemptReconnect ? 'connecting' : 'disconnected')
      },
      rejected() {
        setStatus('disconnected')
      },
      async received(message: unknown) {
        if (!isPropertyUpdate(message)) return
        const { id, version } = message.property
        // A batch already loading for a list that shows this card copied its
        // rows before the update and would write the old values back over it.
        const resume = await cancelListsHolding(queryClient, id)
        // Checked after the await: another message may have landed meanwhile.
        const newest = newestCachedVersion(queryClient, id)
        applyPropertyUpdate(queryClient, message.property)
        resume()
        // Toast every new change once, even when no list on this tab holds the
        // card; not when a cached card (or an earlier toast) is already as new.
        const versions = announced(queryClient)
        if (version <= (versions.get(id) ?? -1) || (newest !== undefined && newest >= version)) return
        versions.set(id, version)
        toast(describeChanges(message), 'info')
      },
    })

    return () => {
      subscription.unsubscribe()
      setStatus('disconnected')
      // The next user to sign in on this tab starts with a clean slate.
      announcedByClient.delete(queryClient)
    }
  }, [userId, queryClient, toast, setStatus])
}
