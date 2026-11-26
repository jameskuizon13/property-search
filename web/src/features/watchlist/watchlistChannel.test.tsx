import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { InfiniteData } from '@tanstack/react-query'
import { delay, http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { describeChanges, formatCompactPrice } from '@/features/properties/format'
import type { Property, PropertyUpdatedMessage } from '@/features/properties/types'
import { watchlistKeys } from '@/lib/queryKeys'
import type { Page } from '@/lib/types'
import { signedIn, signedOut } from '@/test/authHandlers'
import { scrollSentinelIntoView } from '@/test/intersectionObserver'
import { fakeCable } from '@/test/cable'
import { makeProperty, page } from '@/test/propertyHandlers'
import { renderApp } from '@/test/renderApp'
import { server } from '@/test/server'
import { toasts } from '@/test/utils'

const smithSt = makeProperty({ id: 42, streetAddress: '12 Smith St', version: 3, watched: true })

function searchReturns(...properties: Property[]) {
  return http.get('*/api/v1/properties', () => page(properties, { totalCount: properties.length }))
}

function update(property: Partial<Property>, changes: PropertyUpdatedMessage['changes']): PropertyUpdatedMessage {
  return { type: 'property.updated', property: { ...smithSt, ...property, watched: true }, changes }
}

const priceDrop = update(
  { priceCents: 82_000_000, priceDisplay: '$820,000', version: 4 },
  { priceCents: [85_000_000, 82_000_000] },
)

async function subscription() {
  await waitFor(() => expect(fakeCable.active()).toHaveLength(1))
  return fakeCable.active()[0]
}

async function receive(message: unknown) {
  const { mixin } = await subscription()
  await act(async () => {
    await mixin.received?.(message)
  })
}

async function openSearch(...properties: Property[]) {
  server.use(signedIn(), searchReturns(...properties))
  const app = renderApp('/search')
  await screen.findByRole('heading', { name: '12 Smith St' })
  return app
}

describe('live watchlist updates', () => {
  it('subscribes to the user’s WatchlistChannel once signed in', async () => {
    await openSearch(smithSt)
    expect((await subscription()).channel).toBe('WatchlistChannel')
  })

  it('doesn’t subscribe when signed out', async () => {
    server.use(signedOut(), searchReturns(smithSt))
    renderApp('/search')
    await screen.findByRole('heading', { name: '12 Smith St' })
    expect(fakeCable.subscriptions).toHaveLength(0)
  })

  it('patches the card in place and shows a toast', async () => {
    await openSearch(smithSt)
    await receive(priceDrop)

    expect(await screen.findByText('$820,000')).toBeInTheDocument()
    expect(screen.queryByText('$850,000')).not.toBeInTheDocument()
    expect(toasts().getByText('12 Smith St: $850k → $820k')).toBeInTheDocument()
  })

  it('shows a new status badge, keeping the card in the list', async () => {
    await openSearch(smithSt)
    await receive(update({ status: 'sold', version: 4 }, { status: ['for_sale', 'sold'] }))

    expect(await screen.findByText('Sold')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: '12 Smith St' })).toBeInTheDocument()
    expect(toasts().getByText('12 Smith St: For sale → Sold')).toBeInTheDocument()
  })

  it.each([
    ['older', 2],
    ['the same', 3],
  ])('ignores an update with %s version, with no toast', async (_label, version) => {
    await openSearch(smithSt)
    await receive({ ...priceDrop, property: { ...priceDrop.property, version } })

    expect(screen.getByText('$850,000')).toBeInTheDocument()
    expect(toasts().queryByText(/12 Smith St:/)).not.toBeInTheDocument()
  })

  it('applies a repeated message only once', async () => {
    await openSearch(smithSt)
    await receive(priceDrop)
    await receive(priceDrop)
    expect(toasts().getAllByText('12 Smith St: $850k → $820k')).toHaveLength(1)
  })

  it('ignores messages that aren’t property updates', async () => {
    await openSearch(smithSt)
    await receive({ type: 'something.else' })
    await receive({ type: 'property.updated', property: { id: 42 } })
    await receive(null)
    expect(screen.getByText('$850,000')).toBeInTheDocument()
  })

  it('keeps the card’s own watched state (a click in flight decides it)', async () => {
    await openSearch({ ...smithSt, watched: false })
    await receive(priceDrop)

    await screen.findByText('$820,000')
    expect(screen.getByRole('button', { name: /^Watch 12 Smith St$/ })).toHaveAttribute('aria-pressed', 'false')
  })

  it('checks the version of each cached copy separately', async () => {
    const { queryClient } = await openSearch(smithSt)
    // The watchlist already holds a newer copy than search does.
    const newer = { ...smithSt, priceCents: 79_000_000, priceDisplay: '$790,000', version: 5 }
    queryClient.setQueryData<InfiniteData<Page<Property>>>(watchlistKeys.list(), {
      pages: [{ data: [newer], meta: { limit: 20, hasMore: false } }],
      pageParams: [null],
    })

    await receive(priceDrop)

    expect(await screen.findByText('$820,000')).toBeInTheDocument()
    const watchlist = queryClient.getQueryData<InfiniteData<Page<Property>>>(watchlistKeys.list())
    expect(watchlist?.pages[0].data[0]).toMatchObject({ priceDisplay: '$790,000', version: 5 })
  })

  it('refetches the watchlist after a reconnect, not on the first connect, and leaves search for later', async () => {
    let watchlistRequests = 0
    let searchRequests = 0
    server.use(
      signedIn(),
      http.get('*/api/v1/watchlist', () => {
        watchlistRequests += 1
        return page([smithSt])
      }),
      http.get('*/api/v1/properties', () => {
        searchRequests += 1
        return page([smithSt], { totalCount: 1 })
      }),
    )
    const { router } = renderApp('/search')
    await screen.findByRole('heading', { name: '12 Smith St' })
    await router.navigate({ to: '/watchlist' })
    await waitFor(() => expect(watchlistRequests).toBe(1))
    const { mixin } = await subscription()

    act(() => mixin.connected?.({ reconnected: false }))
    expect(watchlistRequests).toBe(1)

    act(() => mixin.connected?.({ reconnected: true }))
    await waitFor(() => expect(watchlistRequests).toBe(2))
    expect(searchRequests).toBe(1) // marked stale, not refetched in the background
  })

  it('restarts a reconnect refetch that a live update interrupted', async () => {
    let watchlistRequests = 0
    server.use(
      signedIn(),
      http.get('*/api/v1/watchlist', async () => {
        watchlistRequests += 1
        if (watchlistRequests === 2) await delay(100) // the reconnect refetch
        return page([watchlistRequests === 1 ? smithSt : priceDrop.property])
      }),
    )
    const { queryClient } = renderApp('/watchlist')
    await screen.findByRole('heading', { name: '12 Smith St' })
    const { mixin } = await subscription()

    act(() => mixin.connected?.({ reconnected: true }))
    await waitFor(() => expect(watchlistRequests).toBe(2))
    await receive(priceDrop)

    await waitFor(() => expect(watchlistRequests).toBe(3))
    await waitFor(() => expect(queryClient.isFetching()).toBe(0))
    expect(screen.getByText('$820,000')).toBeInTheDocument()
  })

  it('keeps the patch when a next batch of that list was already loading', async () => {
    server.use(
      signedIn(),
      http.get('*/api/v1/properties', async ({ request }) => {
        if (!new URL(request.url).searchParams.get('cursor')) {
          return page([smithSt], { hasMore: true, nextCursor: 'c1', totalCount: 2 })
        }
        await delay(100)
        return page([makeProperty({ id: 43, streetAddress: '13 Smith St' })], { hasMore: false })
      }),
    )
    const user = userEvent.setup()
    const { queryClient } = renderApp('/search')
    await screen.findByRole('heading', { name: '12 Smith St' })

    await user.click(screen.getByRole('button', { name: 'Load more' }))
    await receive(priceDrop)
    // The update cancelled that batch (back to its earlier state); the
    // sentinel, still in view, asks for it again.
    await waitFor(() => expect(queryClient.isFetching()).toBe(0))
    scrollSentinelIntoView()

    await screen.findByText('End of results')
    expect(screen.getByRole('heading', { name: '13 Smith St' })).toBeInTheDocument()
    expect(screen.getByText('$820,000')).toBeInTheDocument()
  })

  it('still loads a list whose first batch was in flight when an update arrived', async () => {
    let releaseSearch: () => void = () => {}
    const searchHeld = new Promise<void>((resolve) => (releaseSearch = resolve))
    server.use(
      signedIn(),
      http.get('*/api/v1/properties', async () => {
        await searchHeld
        return page([smithSt], { totalCount: 1 })
      }),
    )
    renderApp('/search')
    await receive(priceDrop)
    releaseSearch()

    expect(await screen.findByRole('heading', { name: '12 Smith St' })).toBeInTheDocument()
  })

  it('toasts a change even when no list on this tab holds the card, once per version', async () => {
    server.use(signedIn(), searchReturns(makeProperty({ id: 7, streetAddress: '1 Other Rd' })))
    renderApp('/search')
    await screen.findByRole('heading', { name: '1 Other Rd' })
    await receive(priceDrop)
    await receive(priceDrop)

    expect(toasts().getAllByText('12 Smith St: $850k → $820k')).toHaveLength(1)
  })

  it('doesn’t toast when the cached card is already as new as the message', async () => {
    await openSearch({ ...smithSt, version: 4, priceCents: 82_000_000, priceDisplay: '$820,000' })
    await receive(priceDrop)
    expect(toasts().queryByText(/12 Smith St:/)).not.toBeInTheDocument()
  })

  it('unsubscribes on logout', async () => {
    server.use(http.delete('*/api/v1/auth/logout', () => new HttpResponse(null, { status: 204 })))
    await openSearch(smithSt)
    const sub = await subscription()

    await userEvent.setup().click(screen.getByRole('button', { name: 'Log out' }))

    await waitFor(() => expect(sub.unsubscribe).toHaveBeenCalled())
    expect(fakeCable.active()).toHaveLength(0)
  })
})

describe('live update wording', () => {
  it('formats prices compactly', () => {
    expect(formatCompactPrice(85_000_000)).toBe('$850k')
    expect(formatCompactPrice(125_000_000)).toBe('$1.25M')
    expect(formatCompactPrice(99_999_900)).toBe('$1M')
  })

  it('describes a price and status change together, a withheld price in the card’s own words', () => {
    expect(
      describeChanges(
        update(
          { status: 'under_offer', priceCents: null, priceDisplay: 'Contact agent' },
          { priceCents: [85_000_000, null], status: ['for_sale', 'under_offer'] },
        ),
      ),
    ).toBe('12 Smith St: $850k → Contact agent, For sale → Under offer')
    expect(describeChanges(update({}, { priceCents: [null, 85_000_000] }))).toBe('12 Smith St: price withheld → $850k')
  })

  it('shows full amounts when the short forms would read the same', () => {
    expect(describeChanges(update({}, { priceCents: [200_500_000, 200_000_000] }))).toBe(
      '12 Smith St: $2,005,000 → $2,000,000',
    )
    expect(describeChanges(update({}, { priceCents: [82_000_000, 82_004_000] }))).toBe(
      '12 Smith St: $820,000 → $820,040',
    )
  })
})
