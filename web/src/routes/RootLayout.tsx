import { Link, Outlet, useNavigate } from '@tanstack/react-router'
import { useLogout } from '@/features/auth/useAuthMutations'
import { useMe } from '@/features/auth/useMe'

const navLink = 'text-sm font-medium text-slate-600 hover:text-slate-900 [&.active]:text-indigo-600'

function AccountNav() {
  const { data: user, isPending } = useMe()
  const logoutMutation = useLogout()
  const navigate = useNavigate()

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
      <span className="text-sm text-slate-500">{user.name}</span>
      <button
        type="button"
        className={navLink}
        disabled={logoutMutation.isPending}
        onClick={() => logoutMutation.mutate(undefined, { onSettled: () => navigate({ to: '/search' }) })}
      >
        Log out
      </button>
    </div>
  )
}

export function RootLayout() {
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
    </div>
  )
}
