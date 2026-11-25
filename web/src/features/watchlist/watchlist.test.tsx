import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { delay, http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { signedIn, signedOut } from '@/test/authHandlers'
import { scrollSentinelIntoView } from '@/test/intersectionObserver'
import { makeProperty, page, rateLimited, serverError } from '@/test/propertyHandlers'
import { renderApp } from '@/test/renderApp'
import { server } from '@/test/server'
import { toasts } from '@/test/utils'

const smithSt = makeProperty({ id: 42, streetAddress: '12 Smith St', watched: false })

function searchReturns(...properties: ReturnType<typeof makeProperty>[]) {
  return http.get('*/api/v1/properties', () => page(properties, { totalCount: properties.length }))
}

const watchButton = (address = '12 Smith St') =>
  screen.findByRole('button', { name: new RegExp(`^Watch(ing)? ${address}$`) })

describe('WatchButton', () => {
  it('updates at once, before the server answers', async () => {
    server.use(
      signedIn(),
      searchReturns(smithSt),
      http.put('*/api/v1/watchlist/42', async () => {
        await delay(100)
        return HttpResponse.json({ data: { ...smithSt, watched: true } }, { status: 201 })
      }),
    )
    const user = userEvent.setup()
    renderApp('/search')
    const button = await watchButton()
    expect(button).toHaveAttribute('aria-pressed', 'false')

    await user.click(button)

    expect(button).toHaveAttribute('aria-pressed', 'true')
    expect(button).toHaveAccessibleName('Watching 12 Smith St')
  })

  it('rolls back with a toast when the request fails', async () => {
    server.use(signedIn(), searchReturns(smithSt), http.put('*/api/v1/watchlist/42', serverError))
    const user = userEvent.setup()
    renderApp('/search')
    const button = await watchButton()

    await user.click(button)

    expect(await toasts().findByText("Couldn't update your watchlist. Please try again.")).toBeInTheDocument()
    expect(button).toHaveAttribute('aria-pressed', 'false')
  })

  it('says so when watching too quickly (429), and rolls back', async () => {
    server.use(
      signedIn(),
      searchReturns(smithSt),
      http.put('*/api/v1/watchlist/42', rateLimited),
    )
    const user = userEvent.setup()
    renderApp('/search')
    const button = await watchButton()

    await user.click(button)

    expect(await toasts().findByText(/changing your watchlist too quickly/)).toBeInTheDocument()
    expect(button).toHaveAttribute('aria-pressed', 'false')
  })

  it('sends fast clicks one at a time, in order, and ends in the last click’s state', async () => {
    const calls: string[] = []
    let inFlight = 0
    let maxInFlight = 0
    const handle = (method: string) => async () => {
      calls.push(method)
      inFlight++
      maxInFlight = Math.max(maxInFlight, inFlight)
      await delay(30)
      inFlight--
      return method === 'PUT' ? HttpResponse.json({ data: smithSt }) : new HttpResponse(null, { status: 204 })
    }
    server.use(
      signedIn(),
      searchReturns(smithSt),
      http.put('*/api/v1/watchlist/42', handle('PUT')),
      http.delete('*/api/v1/watchlist/42', handle('DELETE')),
    )
    const user = userEvent.setup()
    renderApp('/search')
    const button = await watchButton()

    await user.click(button)
    await user.click(button)
    await user.click(button)

    expect(button).toHaveAttribute('aria-pressed', 'true')
    await waitFor(() => expect(calls).toEqual(['PUT', 'DELETE', 'PUT']))
    await waitFor(() => expect(inFlight).toBe(0))
    expect(maxInFlight).toBe(1)
    expect(button).toHaveAttribute('aria-pressed', 'true')
  })

  it('goes back to the last confirmed state when the last of several clicks fails', async () => {
    let puts = 0
    server.use(
      signedIn(),
      searchReturns(smithSt),
      http.put('*/api/v1/watchlist/42', async () => {
        puts++
        await delay(20)
        return puts === 1 ? HttpResponse.json({ data: smithSt }) : serverError()
      }),
      http.delete('*/api/v1/watchlist/42', async () => {
        await delay(20)
        return serverError()
      }),
    )
    const user = userEvent.setup()
    renderApp('/search')
    const button = await watchButton()

    // watch (succeeds), unwatch (fails), watch (fails): the server says watched.
    // A naive rollback to "before the last click" would show unwatched here;
    // the single-click test above covers having no rollback at all.
    await user.click(button)
    await user.click(button)
    await user.click(button)

    expect(await toasts().findByText("Couldn't update your watchlist. Please try again.")).toBeInTheDocument()
    expect(toasts().getAllByText("Couldn't update your watchlist. Please try again.")).toHaveLength(1)
    expect(button).toHaveAttribute('aria-pressed', 'true')
  })

  it('isn’t undone by a batch that was already loading when it was clicked', async () => {
    server.use(
      signedIn(),
      http.get('*/api/v1/properties', async ({ request }) => {
        if (!new URL(request.url).searchParams.get('cursor')) {
          return page([smithSt], { hasMore: true, nextCursor: 'c1', totalCount: 2 })
        }
        await delay(100)
        return page([makeProperty({ id: 43, streetAddress: '13 Smith St' })], { hasMore: false })
      }),
      http.put('*/api/v1/watchlist/42', () => HttpResponse.json({ data: smithSt }, { status: 201 })),
    )
    const user = userEvent.setup()
    const { queryClient } = renderApp('/search')
    const button = await watchButton()

    await user.click(screen.getByRole('button', { name: 'Load more' }))
    await user.click(button)
    // The click cancelled that batch (back to its earlier state); the sentinel,
    // still in view, asks for it again, as a real IntersectionObserver would.
    await waitFor(() => expect(queryClient.isFetching()).toBe(0))
    scrollSentinelIntoView()

    await screen.findByText('End of results')
    await waitFor(() => expect(queryClient.isMutating()).toBe(0))
    expect(screen.getByRole('article', { name: '13 Smith St' })).toBeInTheDocument()
    expect(button).toHaveAttribute('aria-pressed', 'true')
  })

  it('sends a signed-out user to sign in, then back to the same page', async () => {
    server.use(signedOut(), searchReturns(smithSt))
    const user = userEvent.setup()
    const { router } = renderApp('/search?minBedrooms=2')

    await user.click(await watchButton())

    await waitFor(() => expect(router.state.location.pathname).toBe('/login'))
    expect(router.state.location.search).toEqual({ next: '/search?minBedrooms=2' })
  })

  it('sends the user to sign in when the session expired', async () => {
    server.use(
      signedIn(),
      searchReturns(smithSt),
      http.put('*/api/v1/watchlist/42', () =>
        HttpResponse.json({ error: { code: 'unauthorized', message: 'expired' } }, { status: 401 }),
      ),
    )
    const user = userEvent.setup()
    const { router } = renderApp('/search')

    await user.click(await watchButton())

    await waitFor(() => expect(router.state.location.pathname).toBe('/login'))
    expect(router.state.location.search).toEqual({ next: '/search' })
    expect(toasts().getByText("You've been signed out")).toBeInTheDocument()
    expect(toasts().queryByText(/Couldn't update your watchlist/)).not.toBeInTheDocument()
  })
})

describe('watchlist page', () => {
  it('lists watched properties, including ones that have sold', async () => {
    server.use(
      signedIn(),
      http.get('*/api/v1/watchlist', () =>
        page(
          [
            makeProperty({ id: 1, streetAddress: '1 Sold Rd', status: 'sold', watched: true }),
            makeProperty({ id: 2, streetAddress: '2 Main St', watched: true }),
          ],
          { totalCount: 2 },
        ),
      ),
    )
    renderApp('/watchlist')

    const sold = await screen.findByRole('article', { name: '1 Sold Rd' })
    expect(within(sold).getByText('Sold')).toBeInTheDocument()
    expect(screen.getByText('2 properties')).toBeInTheDocument()
  })

  it('keeps an unwatched card in place, so one click re-watches it', async () => {
    server.use(
      signedIn(),
      http.get('*/api/v1/watchlist', () => page([{ ...smithSt, watched: true }], { totalCount: 1 })),
      http.delete('*/api/v1/watchlist/42', () => new HttpResponse(null, { status: 204 })),
    )
    const user = userEvent.setup()
    const { queryClient } = renderApp('/watchlist')
    const button = await watchButton()

    await user.click(button)

    await waitFor(() => expect(queryClient.isMutating()).toBe(0))
    expect(screen.getByRole('article', { name: '12 Smith St' })).toBeInTheDocument()
    expect(button).toHaveAttribute('aria-pressed', 'false')
    // Stale, so the next visit refetches it.
    expect(queryClient.getQueryState(['watchlist', 'list'])?.isInvalidated).toBe(true)
  })

  it('explains an empty watchlist', async () => {
    server.use(signedIn())
    renderApp('/watchlist')

    expect(await screen.findByRole('heading', { name: "You're not watching any properties yet" })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Search properties' })).toBeInTheDocument()
  })
})
