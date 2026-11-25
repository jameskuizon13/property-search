import { Link, Outlet, useNavigate, useRouter } from '@tanstack/react-router'
import { useAtomValue } from 'jotai'
import { Toaster } from '@/components/ui/Toaster'
import { useLogout } from '@/features/auth/useAuthMutations'
import { useMe } from '@/features/auth/useMe'
import { useSessionEvents } from '@/features/auth/useSessionEvents'
import { useWatchlistChannel } from '@/features/watchlist/useWatchlistChannel'
import { cableStatusAtom, type CableStatus } from '@/lib/cableStatus'

const navLink = 'text-sm font-medium text-slate-600 hover:text-slate-900 [&.active]:text-indigo-600'

// Each state has a visible word, not just a colour (WCAG 1.4.1), and dot
// colours with at least 3:1 contrast on white (WCAG 1.4.11).
const liveStatus: Record<CableStatus, { text: string; label: string; dot: string }> = {
  connected: { text: 'Live', label: 'Live updates on', dot: 'bg-emerald-600' },
  connecting: { text: 'Connecting…', label: 'Connecting to live updates…', dot: 'bg-amber-600' },
  disconnected: { text: 'Offline', label: 'Live updates off. Refresh the page to reconnect.', dot: 'bg-slate-500' },
}

/** Live-updates state by the user's name; its own atom, so status changes re-render only this. */
function LiveStatus() {
  const { text, label, dot } = liveStatus[useAtomValue(cableStatusAtom)]
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-slate-600" title={label}>
      <span aria-hidden="true" className={`size-2 rounded-full ${dot}`} />
      <span aria-hidden="true">{text}</span>
      <span className="sr-only">{label}</span>
    </span>
  )
}

function AccountNav() {
  const { data: user, isPending } = useMe()
  const logoutMutation = useLogout()
  const navigate = useNavigate()
  const router = useRouter()

  if (isPending) return null

  if (!user) {
    return (
      <div className="flex items-center gap-4">
        <Link to="/login" className={navLink}>
          Sign in
        </Link>
        <Link
          to="/signup"
          className="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-500"
        >
          Sign up
        </Link>
      </div>
    )
  }

  return (
    <div className="flex items-center gap-4">
      <span className="inline-flex items-center gap-2 text-sm text-slate-500">
        <LiveStatus />
        {user.name}
      </span>
      <button
        type="button"
        className={navLink}
        disabled={logoutMutation.isPending}
        onClick={() =>
          logoutMutation.mutate(undefined, {
            // Leave a page that needs an account; stay on a public one, filters and all.
            onSuccess: () => {
              if (router.state.matches.some((match) => match.staticData.requiresAuth)) void navigate({ to: '/search' })
            },
          })
        }
      >
        Log out
      </button>
    </div>
  )
}

export function RootLayout() {
  useSessionEvents()
  useWatchlistChannel()
  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white">
        <nav className="mx-auto flex max-w-6xl items-center justify-between gap-6 px-4 py-3">
          <div className="flex items-center gap-6">
            <Link to="/search" className="text-lg font-semibold text-slate-900">
              Property Search
            </Link>
            <Link to="/search" className={navLink}>
              Search
            </Link>
            <Link to="/watchlist" className={navLink}>
              Watchlist
            </Link>
          </div>
          <AccountNav />
        </nav>
      </header>
      <Outlet />
      <Toaster />
    </div>
  )
}
