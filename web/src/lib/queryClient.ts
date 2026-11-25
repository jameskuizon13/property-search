import { QueryClient } from '@tanstack/react-query'
import { ApiError } from './api'

/** Retry once for network errors and 5xx; a 4xx will fail the same way again. */
export function shouldRetry(failureCount: number, error: Error) {
  if (error instanceof ApiError && error.status < 500) return false
  return failureCount < 1
}

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, refetchOnWindowFocus: false, retry: shouldRetry },
  },
})
