import { useMe } from '@/features/auth/useMe'

// Placeholder until the watchlist UI lands (Batch 5). Protected by requireAuth.
export function WatchlistPage() {
  const { data: user } = useMe()
  return (
    <main className="mx-auto max-w-6xl px-4 py-8">
      <h1 className="text-2xl font-semibold">Your watchlist</h1>
      <p className="mt-2 text-slate-600">Signed in as {user?.email}. Watched properties will show here.</p>
    </main>
  )
}
