import { useMutation, useQueryClient, type QueryClient } from '@tanstack/react-query'
import { disconnectConsumer } from '@/lib/cable'
import { login, logout, signup } from './authApi'
import type { User } from './types'
import { authKeys } from './useMe'

function setSignedIn(queryClient: QueryClient, user: User) {
  // Anything cached while signed out (e.g. `watched` flags) is now stale.
  queryClient.removeQueries({ predicate: (q) => q.queryKey[0] !== authKeys.me[0] })
  queryClient.setQueryData(authKeys.me, user)
}

export function useLogin() {
  const queryClient = useQueryClient()
  return useMutation({ mutationFn: login, onSuccess: (user) => setSignedIn(queryClient, user) })
}

export function useSignup() {
  const queryClient = useQueryClient()
  return useMutation({ mutationFn: signup, onSuccess: (user) => setSignedIn(queryClient, user) })
}

export function useLogout() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: logout,
    // Clear local state even if the request fails: the user asked to leave.
    onSettled: () => {
      disconnectConsumer()
      queryClient.clear()
      queryClient.setQueryData(authKeys.me, null)
    },
  })
}
