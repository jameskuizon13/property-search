import type { InfiniteData, UseInfiniteQueryResult } from '@tanstack/react-query'
import { useEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from 'react'
import { ApiError } from '@/lib/api'
import type { Page } from '@/lib/types'
import { PropertyCardSkeleton, PropertyCardSkeletons } from './Skeleton'
import { ErrorState } from './states'

/** Start loading the next batch while the sentinel is still this far below the viewport. */
export const PREFETCH_MARGIN = '600px'
/** Not virtualised: off-screen cards skip layout and paint (see `offscreen-skip` in index.css). */
const OFFSCREEN_SKIP = 'offscreen-skip'
const FIRST_LOAD_SKELETONS = 6
const NEXT_PAGE_SKELETONS = 3

type Props<T extends { id: number }> = {
  query: UseInfiniteQueryResult<InfiniteData<Page<T>>, Error>
  renderItem: (item: T) => ReactNode
  /** Shown when the first batch is empty. */
  empty: ReactNode
  /** Accessible name of the list, e.g. "Search results". */
  label: string
  errorTitle: string
  /** Where "Back to top" moves keyboard focus: the page heading (give it tabIndex={-1}). */
  topRef?: RefObject<HTMLElement | null>
}

/** True once the page is scrolled more than a screen down. */
function useScrolledPastFirstScreen() {
  const [scrolled, setScrolled] = useState(false)
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > window.innerHeight)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])
  return scrolled
}

function scrollToTop(focusTarget: HTMLElement | null | undefined) {
  const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' })
  focusTarget?.focus({ preventScroll: true })
}

/**
 * One list for search and the watchlist: cards from every loaded batch, a
 * sentinel that fetches the next batch before the user reaches the end, and a
 * visible "Load more" button for keyboard and screen-reader users. Not
 * virtualised (see OFFSCREEN_SKIP and the README).
 */
export function InfiniteResults<T extends { id: number }>({
  query,
  renderItem,
  empty,
  label,
  errorTitle,
  topRef,
}: Props<T>) {
  const { data, error, isPending, isError, refetch, hasNextPage, isFetchingNextPage, isFetchNextPageError, fetchNextPage } =
    query
  const sentinelRef = useRef<HTMLDivElement>(null)
  const endRef = useRef<HTMLParagraphElement>(null)
  // Set when "Load more" or "Retry" is pressed: if that batch was the last,
  // the button goes away, so focus moves to "End of results" instead of <body>.
  const focusEndWhenDone = useRef(false)
  const scrolledDown = useScrolledPastFirstScreen()

  // Repeats are possible across batches (a price changes mid-scroll in a price
  // sort), so de-duplicate by id: a repeat never shows as two cards.
  const items = useMemo(() => {
    const seen = new Set<number>()
    const out: T[] = []
    for (const page of data?.pages ?? []) {
      for (const item of page.data) {
        if (seen.has(item.id)) continue
        seen.add(item.id)
        out.push(item)
      }
    }
    return out
  }, [data])

  const canAutoLoad = !!hasNextPage && !isFetchingNextPage && !isFetchNextPageError

  // Recreated whenever a fetch finishes: a new observer reports the sentinel's
  // current state, so a sentinel that is still in view loads the next batch
  // too. The guard above also stops double fetches and retry loops.
  useEffect(() => {
    const sentinel = sentinelRef.current
    if (!sentinel || !canAutoLoad) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) void fetchNextPage()
      },
      { rootMargin: `0px 0px ${PREFETCH_MARGIN} 0px` },
    )
    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [canAutoLoad, fetchNextPage])

  useEffect(() => {
    if (!focusEndWhenDone.current || isFetchingNextPage) return
    focusEndWhenDone.current = false
    if (!hasNextPage) endRef.current?.focus()
  }, [isFetchingNextPage, hasNextPage])

  function loadMore() {
    if (isFetchingNextPage) return
    focusEndWhenDone.current = true
    void fetchNextPage()
  }

  // One status region that stays mounted while its text changes, so screen
  // readers announce loading (a region inserted with its text is often missed).
  const status = (
    <p role="status" className="sr-only">
      {isPending ? 'Loading properties' : isFetchingNextPage ? 'Loading more properties' : ''}
    </p>
  )

  if (isPending) {
    return (
      <>
        {status}
        <div aria-hidden="true" className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <PropertyCardSkeletons count={FIRST_LOAD_SKELETONS} />
        </div>
      </>
    )
  }

  if (isError && !data) {
    return (
      <>
        {status}
        <ErrorState title={errorTitle} error={error} onRetry={() => void refetch()} />
      </>
    )
  }

  if (items.length === 0) {
    return (
      <>
        {status}
        {empty}
      </>
    )
  }

  const totalCount = data.pages[0]?.meta.totalCount

  return (
    <>
      {status}
      <section aria-label={label}>
        {totalCount != null && (
          <p className="mb-4 text-sm text-slate-600">
            {totalCount.toLocaleString('en-AU')} {totalCount === 1 ? 'property' : 'properties'}
          </p>
        )}
        <ul className="@container grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((item) => (
            <li key={item.id} className={OFFSCREEN_SKIP}>
              {renderItem(item)}
            </li>
          ))}
          {isFetchingNextPage &&
            Array.from({ length: NEXT_PAGE_SKELETONS }, (_, i) => (
              <li key={`skeleton-${i}`} aria-hidden="true">
                <PropertyCardSkeleton />
              </li>
            ))}
        </ul>

        <div className="mt-8 flex flex-col items-center gap-3 text-sm">
          {isFetchNextPageError && !isFetchingNextPage && (
            <p role="alert" className="text-red-800">
              {error instanceof ApiError && error.status === 429
                ? 'Too many requests in a short time. Wait a moment, then retry.'
                : "Couldn't load more properties."}
            </p>
          )}
          {hasNextPage ? (
            <>
              <div ref={sentinelRef} data-testid="results-sentinel" className="h-px w-full" />
              {/* One button that stays mounted through loading and failure, so
                  keyboard focus is never dropped. aria-disabled (not disabled)
                  because a disabled button loses focus. */}
              <button
                type="button"
                onClick={loadMore}
                aria-disabled={isFetchingNextPage || undefined}
                className="rounded-md border border-slate-300 bg-white px-4 py-2 font-medium text-slate-700 hover:bg-slate-50 aria-disabled:cursor-wait aria-disabled:opacity-60"
              >
                {isFetchingNextPage ? 'Loading…' : isFetchNextPageError ? 'Retry' : 'Load more'}
              </button>
            </>
          ) : (
            <p ref={endRef} tabIndex={-1} className="text-slate-500 focus:outline-none">
              End of results
            </p>
          )}
        </div>

        {data.pages.length > 1 && scrolledDown && (
          <button
            type="button"
            onClick={() => scrollToTop(topRef?.current)}
            className="fixed bottom-4 left-4 z-40 rounded-full bg-slate-900 px-4 py-2 text-sm font-medium text-white shadow-lg hover:bg-slate-700"
          >
            Back to top
          </button>
        )}
      </section>
    </>
  )
}
