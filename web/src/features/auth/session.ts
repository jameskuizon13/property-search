import type { QueryClient } from '@tanstack/react-query'
import { disconnectConsumer } from '@/lib/cable'
import { propertyKeys, watchlistKeys } from '@/lib/queryKeys'
import { authKeys } from './useMe'

/**
 * Forget everything that belonged to the signed-in user: the socket, the user,
 * the watchlist, and the `watched` flags in search results and on property
 * pages (those refetch, as both are public). Shared by logout, a 401, and a sign-out in another tab.
 */
export function clearUserData(queryClient: QueryClient) {
  disconnectConsumer()
  queryClient.setQueryData(authKeys.me, null)
  queryClient.removeQueries({ queryKey: watchlistKeys.all })
  void queryClient.resetQueries({ queryKey: propertyKeys.lists() })
  void queryClient.resetQueries({ queryKey: propertyKeys.details() })
}

const CHANNEL = 'auth'
const SIGNED_OUT = 'signed-out'

/** Tells the app's other tabs in this browser that the user logged out. */
export function broadcastSignOut() {
  if (typeof BroadcastChannel === 'undefined') return
  const channel = new BroadcastChannel(CHANNEL)
  channel.postMessage(SIGNED_OUT)
  channel.close()
}

/** Calls `onSignOut` when another tab logs out. Returns the cleanup. */
export function onSignOutElsewhere(onSignOut: () => void) {
  if (typeof BroadcastChannel === 'undefined') return () => {}
  const channel = new BroadcastChannel(CHANNEL)
  channel.onmessage = (event: MessageEvent) => {
    if (event.data === SIGNED_OUT) onSignOut()
  }
  return () => channel.close()
}
