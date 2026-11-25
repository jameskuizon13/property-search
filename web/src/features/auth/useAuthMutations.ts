import { useMutation, useQueryClient, type QueryClient } from '@tanstack/react-query'
import { useToast } from '@/components/ui/toast'
import { ApiError } from '@/lib/api'
import { login, logout, signup } from './authApi'
import { broadcastSignOut, clearUserData } from './session'
import type { User } from './types'
import { authKeys } from './useMe'

function setSignedIn(queryClient: QueryClient, user: User) {
  // Anything cached while signed out (e.g. `watched` flags) is now stale.
  queryClient.removeQueries({ predicate: (q) => q.queryKey[0] !== authKeys.me[0] })
  queryClient.setQueryData(authKeys.me, user)
}

export function useLogin() {
  const queryClient = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: login,
    onSuccess: (user) => {
      setSignedIn(queryClient, user)
      toast('Signed in', 'success')
    },
  })
}

export function useSignup() {
  const queryClient = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: signup,
    onSuccess: (user) => {
      setSignedIn(queryClient, user)
      toast('Account created', 'success')
    },
  })
}

/** A 401 from logout means the session had already ended: that counts as signed out. */
async function logoutOrAlreadyOut() {
  try {
    await logout()
  } catch (error) {
    if (!(error instanceof ApiError && error.status === 401)) throw error
  }
}

export function useLogout() {
  const queryClient = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: logoutOrAlreadyOut,
    onSuccess: () => {
      clearUserData(queryClient)
      broadcastSignOut()
      toast('Signed out', 'success')
    },
    // If the request failed the cookie may still be valid, so don't pretend:
    // clearing local state would sign the user back in on the next refresh.
    onError: () => toast("Couldn't sign out. Please try again.", 'error'),
  })
}
