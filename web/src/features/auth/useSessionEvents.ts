import { useQueryClient } from '@tanstack/react-query'
import { useRouter } from '@tanstack/react-router'
import { useEffect } from 'react'
import { useToast } from '@/components/ui/toast'
import { setUnauthorizedHandler } from '@/lib/api'
import { clearUserData, onSignOutElsewhere } from './session'
import { authKeys } from './useMe'

/**
 * Handles being signed out from outside this tab: a 401 on any request (the
 * cookie expired or was cleared on another device) or a logout in another
 * tab. Clears the user's data, shows a toast, and re-runs the current route's
 * guards, so only a protected page (/watchlist) goes to /login?next=…; a
 * public page like search stays put in its signed-out view.
 */
export function useSessionEvents() {
  const queryClient = useQueryClient()
  const router = useRouter()
  const toast = useToast()

  useEffect(() => {
    function signedOut(message: string) {
      const wasSignedIn = queryClient.getQueryData(authKeys.me) != null
      clearUserData(queryClient)
      if (wasSignedIn) toast(message)
      void router.invalidate()
    }

    setUnauthorizedHandler(() => signedOut("You've been signed out"))
    const stopListening = onSignOutElsewhere(() => signedOut('You were signed out in another tab'))
    return () => {
      setUnauthorizedHandler(null)
      stopListening()
    }
  }, [queryClient, router, toast])
}
