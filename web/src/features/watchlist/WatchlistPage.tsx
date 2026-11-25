import { Link } from '@tanstack/react-router'
import { useRef } from 'react'
import { InfiniteResults } from '@/components/ui/InfiniteResults'
import { EmptyState } from '@/components/ui/states'
import { useRenderProperty } from '@/features/properties/useRenderProperty'
import { useWatchlist } from './useWatchlist'

/**
 * Protected by requireAuth. Most recently watched first; not limited to
 * active listings, so a watched property that sells stays here as "Sold".
 */
export function WatchlistPage() {
  const query = useWatchlist()
  const renderItem = useRenderProperty()
  const headingRef = useRef<HTMLHeadingElement>(null)

  return (
    <main className="mx-auto max-w-6xl px-4 py-8">
      <h1 ref={headingRef} tabIndex={-1} className="mb-6 text-2xl font-semibold focus:outline-none">
        Your watchlist
      </h1>
      <InfiniteResults
        query={query}
        renderItem={renderItem}
        label="Watched properties"
        topRef={headingRef}
        errorTitle="We couldn't load your watchlist"
        empty={
          <EmptyState title="You're not watching any properties yet">
            <p>Watch a property from search to follow its price and status here.</p>
            <Link
              to="/search"
              className="inline-block rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500"
            >
              Search properties
            </Link>
          </EmptyState>
        }
      />
    </main>
  )
}
