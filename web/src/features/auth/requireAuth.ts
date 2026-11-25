import type { QueryClient } from '@tanstack/react-query'
import { redirect, type ParsedLocation } from '@tanstack/react-router'
import { meQueryOptions } from './useMe'

/** Route `beforeLoad` guard: signed-out users go to /login and come back afterwards. */
export async function requireAuth({
  context,
  location,
}: {
  context: { queryClient: QueryClient }
  location: ParsedLocation
}) {
  const user = await context.queryClient.ensureQueryData(meQueryOptions)
  if (!user) {
    throw redirect({ to: '/login', search: { next: location.href } })
  }
  return { user }
}
