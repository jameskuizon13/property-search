import { ApiError } from '@/lib/api'

/** Form-level message for an auth mutation error (field errors are shown inline). */
export function authErrorMessage(error: Error | null): string | null {
  if (!error) return null
  if (error instanceof ApiError) {
    if (error.status === 401) return 'Invalid email or password'
    if (error.status === 422) return null
    if (error.status === 429) return 'Too many attempts. Please wait a minute and try again.'
  }
  return 'Something went wrong. Please try again.'
}
