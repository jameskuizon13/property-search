import type { QueryClient } from '@tanstack/react-query'
import {
  createRootRouteWithContext,
  createRoute,
  createRouter,
  lazyRouteComponent,
  redirect,
  type RouterHistory,
} from '@tanstack/react-router'
import { z } from 'zod'
import { requireAuth } from '@/features/auth/requireAuth'
import { safeNext } from '@/features/auth/safeNext'
import { meQueryOptions } from '@/features/auth/useMe'
import { parseSearchFilters } from '@/features/properties/searchSchema'
import { LoginPage, SignupPage } from '@/routes/AuthPages'
import { RootLayout } from '@/routes/RootLayout'

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
  // Filters live in the URL; see searchSchema.
  validateSearch: parseSearchFilters,
  // Code-split: each page loads on first visit (or on hover, via preload).
  component: lazyRouteComponent(() => import('@/features/properties/SearchPage'), 'SearchPage'),
})

const watchlistRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/watchlist',
  // Keep these two together on every protected route: the guard enforces it,
  // and the flag tells logout to leave the page.
  beforeLoad: requireAuth,
  staticData: { requiresAuth: true },
  component: lazyRouteComponent(() => import('@/features/watchlist/WatchlistPage'), 'WatchlistPage'),
})

// Public, like search. The page checks the id itself and shows "not found"
// for anything that isn't a plain positive integer.
const propertyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/properties/$propertyId',
  component: lazyRouteComponent(() => import('@/features/properties/PropertyPage'), 'PropertyPage'),
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

const routeTree = rootRoute.addChildren([
  indexRoute,
  searchRoute,
  propertyRoute,
  watchlistRoute,
  loginRoute,
  signupRoute,
])

// Sign-outs from outside this tab (a 401, another tab logging out) are
// handled in RootLayout by useSessionEvents.
export function createAppRouter(queryClient: QueryClient, history?: RouterHistory) {
  return createRouter({
    routeTree,
    context: { queryClient },
    history,
    defaultPreload: 'intent',
    scrollRestoration: true,
  })
}

export type AppRouter = ReturnType<typeof createAppRouter>

declare module '@tanstack/react-router' {
  interface Register {
    router: AppRouter
  }
  interface HistoryState {
    /** Set by a card's link: the list the property page was opened from, for its back link. */
    from?: 'search' | 'watchlist'
  }
  interface StaticDataRouteOption {
    /** Set on routes guarded by requireAuth, so logout knows to leave them. */
    requiresAuth?: boolean
  }
}
