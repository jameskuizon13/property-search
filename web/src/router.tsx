import type { QueryClient } from '@tanstack/react-query'
import {
  createRootRouteWithContext,
  createRoute,
  createRouter,
  redirect,
  type RouterHistory,
} from '@tanstack/react-router'
import { z } from 'zod'
import { requireAuth } from '@/features/auth/requireAuth'
import { safeNext } from '@/features/auth/safeNext'
import { authKeys, meQueryOptions } from '@/features/auth/useMe'
import { setUnauthorizedHandler } from '@/lib/api'
import { disconnectConsumer } from '@/lib/cable'
import { LoginPage, SignupPage } from '@/routes/AuthPages'
import { RootLayout } from '@/routes/RootLayout'
import { SearchPage } from '@/routes/SearchPage'
import { WatchlistPage } from '@/routes/WatchlistPage'

export type RouterContext = { queryClient: QueryClient }

const rootRoute = createRootRouteWithContext<RouterContext>()({
  component: RootLayout,
})

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  beforeLoad: () => {
    throw redirect({ to: '/search' })
  },
})

const searchRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/search',
  component: SearchPage,
})

const watchlistRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/watchlist',
  beforeLoad: requireAuth,
  component: WatchlistPage,
})

const authSearch = z.object({ next: z.string().optional() })

// Signed-in users skip the login/signup pages and go straight to `next`.
async function redirectIfSignedIn({ context, search }: { context: RouterContext; search: { next?: string } }) {
  const user = await context.queryClient.ensureQueryData(meQueryOptions)
  if (user) throw redirect({ href: safeNext(search.next) })
}

const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/login',
  validateSearch: authSearch,
  beforeLoad: redirectIfSignedIn,
  component: LoginPage,
})

const signupRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/signup',
  validateSearch: authSearch,
  beforeLoad: redirectIfSignedIn,
  component: SignupPage,
})

const routeTree = rootRoute.addChildren([indexRoute, searchRoute, watchlistRoute, loginRoute, signupRoute])

export function createAppRouter(queryClient: QueryClient, history?: RouterHistory) {
  const router = createRouter({
    routeTree,
    context: { queryClient },
    history,
    defaultPreload: 'intent',
    scrollRestoration: true,
  })

  // Any 401 outside /me and login means the cookie expired or was cleared:
  // drop cached user data and send the user to sign in, then back here.
  setUnauthorizedHandler(() => {
    disconnectConsumer()
    queryClient.clear()
    queryClient.setQueryData(authKeys.me, null)
    const { pathname, href } = router.state.location
    if (pathname !== '/login' && pathname !== '/signup') {
      void router.navigate({ to: '/login', search: { next: href } })
    }
  })

  return router
}

export type AppRouter = ReturnType<typeof createAppRouter>

declare module '@tanstack/react-router' {
  interface Register {
    router: AppRouter
  }
}
