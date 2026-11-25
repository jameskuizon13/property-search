import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { delay, http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import type { Property, PropertyDetail, PropertyUpdatedMessage } from '@/features/properties/types'
import { signedIn, signedOut } from '@/test/authHandlers'
import { fakeCable } from '@/test/cable'
import { makeProperty, page } from '@/test/propertyHandlers'
import { renderApp } from '@/test/renderApp'
import { server } from '@/test/server'
import { toasts } from '@/test/utils'

const smithSt = makeProperty({
  id: 42,
  streetAddress: '12 Smith St',
  imageUrl: '/images/properties/house-01.webp',
  latitude: -37.798,
  longitude: 144.978,
  version: 3,
})

function detail(overrides: Partial<PropertyDetail> = {}): PropertyDetail {
  return {
    ...smithSt,
    description: 'A light-filled family home.\n\nWalk to cafes and parks.',
    history: [
      { id: 2, kind: 'status_changed', from: 'for_sale', to: 'under_offer', createdAt: '2026-11-12T09:00:00Z' },
      { id: 1, kind: 'price_changed', from: 85_000_000, to: 82_000_000, createdAt: '2026-11-10T09:00:00Z' },
    ],
    historyComplete: true,
    ...overrides,
  }
}

const detailReturns = (data: PropertyDetail) =>
  http.get('*/api/v1/properties/:id', ({ params }) =>
    params.id === String(data.id)
      ? HttpResponse.json({ data })
      : HttpResponse.json({ error: { code: 'not_found', message: 'Property not found' } }, { status: 404 }),
  )

const searchReturns = (...properties: Property[]) =>
  http.get('*/api/v1/properties', () => page(properties, { totalCount: properties.length }))

describe('property cards', () => {
  it('open the property page from anywhere on the card, and Back returns to the results', async () => {
    const user = userEvent.setup()
    server.use(signedOut(), searchReturns(smithSt), detailReturns(detail()))
    const { router } = renderApp('/search?q=fitzroy')

    const card = (await screen.findByRole('heading', { name: '12 Smith St' })).closest('article')!
    // One link per card, named by its address.
    expect(within(card).getAllByRole('link')).toHaveLength(1)
    await user.click(within(card).getByRole('link', { name: '12 Smith St' }))

    expect(router.state.location.pathname).toBe('/properties/42')
    expect(await screen.findByText('Walk to cafes and parks.', { exact: false })).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: /back to results/i }))
    await waitFor(() => expect(router.state.location.href).toBe('/search?q=fitzroy'))
  })

  it('keep Watch as its own button: it toggles instead of opening the page', async () => {
    const user = userEvent.setup()
    server.use(
      signedIn(),
      searchReturns(smithSt),
      http.put('*/api/v1/watchlist/42', () => HttpResponse.json({ data: { ...smithSt, watched: true } })),
    )
    const { router } = renderApp('/search')

    await user.click(await screen.findByRole('button', { name: /^watch 12 smith st/i }))

    expect(screen.getByRole('button', { name: /^watching 12 smith st/i })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/search')
  })
})

describe('property page', () => {
  it('shows the photo, price, facts, description, history and a maps link', async () => {
    server.use(signedOut(), detailReturns(detail()))
    renderApp('/properties/42')

    expect(await screen.findByRole('heading', { level: 1, name: '12 Smith St' })).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Photo of 12 Smith St' })).toHaveAttribute(
      'src',
      '/images/properties/house-01.webp',
    )
    expect(screen.getByText('$850,000')).toBeInTheDocument()
    expect(screen.getByText('Fitzroy VIC 3065')).toBeInTheDocument()
    expect(screen.getByText('A light-filled family home.', { exact: false })).toBeInTheDocument()

    const history = screen.getByRole('region', { name: 'Price and status history' })
    const entries = within(history).getAllByRole('listitem').map((li) => li.textContent)
    expect(entries).toEqual([
      expect.stringContaining('Under offer (was for sale)'),
      expect.stringContaining('Price dropped from $850,000 to $820,000'),
      expect.stringContaining('Listed for sale'),
    ])

    expect(screen.getByRole('link', { name: /open in google maps/i })).toHaveAttribute(
      'href',
      'https://www.google.com/maps/search/?api=1&query=-37.798%2C144.978',
    )
    expect(document.title).toBe('12 Smith St, Fitzroy | Property Search')
  })

  it('shows the card’s details at once while the rest loads', async () => {
    const user = userEvent.setup()
    server.use(
      signedOut(),
      searchReturns(smithSt),
      http.get('*/api/v1/properties/:id', async () => {
        await delay('infinite')
        return HttpResponse.json({})
      }),
    )
    renderApp('/search')

    await user.click(await screen.findByRole('link', { name: '12 Smith St' }))

    expect(await screen.findByRole('heading', { level: 1, name: '12 Smith St' })).toBeInTheDocument()
    expect(screen.getByText('Loading description…')).toBeInTheDocument()
  })

  it('says when a property doesn’t exist, with a way back to search', async () => {
    server.use(signedOut(), detailReturns(detail()))
    renderApp('/properties/999')

    expect(await screen.findByRole('heading', { name: "We couldn't find this property" })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Search properties' })).toHaveAttribute('href', '/search')
  })

  it('treats an id that isn’t a plain number as not found, without asking the API', async () => {
    let requests = 0
    server.use(
      signedOut(),
      http.get('*/api/v1/properties/:id', () => {
        requests++
        return HttpResponse.json({ data: detail() })
      }),
    )
    renderApp('/properties/42abc')

    expect(await screen.findByRole('heading', { name: "We couldn't find this property" })).toBeInTheDocument()
    expect(requests).toBe(0)
  })

  it('offers a retry when loading fails', async () => {
    const user = userEvent.setup()
    let fail = true
    server.use(
      signedOut(),
      http.get('*/api/v1/properties/:id', () =>
        fail
          ? HttpResponse.json({ error: { code: 'internal_error', message: 'Boom' } }, { status: 500 })
          : HttpResponse.json({ data: detail() }),
      ),
    )
    renderApp('/properties/42')

    await screen.findByRole('heading', { name: "We couldn't load this property" })
    fail = false
    await user.click(screen.getByRole('button', { name: 'Retry' }))

    expect(await screen.findByRole('heading', { level: 1, name: '12 Smith St' })).toBeInTheDocument()
  })

  it('watches from the page, and the search card shows it too', async () => {
    const user = userEvent.setup()
    server.use(
      signedIn(),
      searchReturns(smithSt),
      detailReturns(detail()),
      http.put('*/api/v1/watchlist/42', () => HttpResponse.json({ data: { ...smithSt, watched: true } })),
    )
    const { router } = renderApp('/search')
    await user.click(await screen.findByRole('link', { name: '12 Smith St' }))
    await screen.findByText('Walk to cafes and parks.', { exact: false })

    await user.click(screen.getByRole('button', { name: /^watch 12 smith st/i }))
    expect(screen.getByRole('button', { name: /^watching 12 smith st/i })).toBeInTheDocument()

    act(() => router.history.back())
    await waitFor(() => expect(router.state.location.pathname).toBe('/search'))
    expect(await screen.findByRole('button', { name: /^watching 12 smith st/i })).toBeInTheDocument()
  })

  it('updates in place when a live price change arrives, and refetches the history', async () => {
    let served = detail({ watched: true })
    server.use(
      signedIn(),
      http.get('*/api/v1/properties/:id', () => HttpResponse.json({ data: served })),
    )
    renderApp('/properties/42')
    await screen.findByText('$850,000')

    served = detail({
      watched: true,
      priceCents: 80_000_000,
      priceDisplay: '$800,000',
      version: 4,
      history: [
        { id: 3, kind: 'price_changed', from: 85_000_000, to: 80_000_000, createdAt: '2026-11-20T09:00:00Z' },
        ...detail().history,
      ],
    })
    const message: PropertyUpdatedMessage = {
      type: 'property.updated',
      property: { ...smithSt, priceCents: 80_000_000, priceDisplay: '$800,000', version: 4, watched: true },
      changes: { priceCents: [85_000_000, 80_000_000] },
    }
    await waitFor(() => expect(fakeCable.active()).toHaveLength(1))
    await act(async () => {
      await fakeCable.active()[0].mixin.received?.(message)
    })

    expect(await screen.findByText('$800,000')).toBeInTheDocument()
    expect(await screen.findByText('Price dropped from $850,000 to $800,000')).toBeInTheDocument()
    expect(toasts().getByText('12 Smith St: $850k → $800k')).toBeInTheDocument()
  })

  it('says “Back to watchlist” when opened from the watchlist', async () => {
    const user = userEvent.setup()
    server.use(
      signedIn(),
      http.get('*/api/v1/watchlist', () => page([{ ...smithSt, watched: true }], { totalCount: 1 })),
      detailReturns(detail({ watched: true })),
    )
    const { router } = renderApp('/watchlist')

    await user.click(await screen.findByRole('link', { name: '12 Smith St' }))
    await user.click(await screen.findByRole('button', { name: /back to watchlist/i }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/watchlist'))
  })

  it('links to search, not back to the login page, after signing in from the page', async () => {
    const user = userEvent.setup()
    let signedInNow = false
    server.use(
      http.get('*/api/v1/me', () =>
        signedInNow
          ? HttpResponse.json({ data: { id: 1, email: 'demo@example.com', name: 'Demo User', role: 'user' } })
          : HttpResponse.json({ error: { code: 'unauthorized', message: 'You need to sign in' } }, { status: 401 }),
      ),
      http.post('*/api/v1/auth/login', () => {
        signedInNow = true
        return HttpResponse.json({ data: { id: 1, email: 'demo@example.com', name: 'Demo User', role: 'user' } })
      }),
      detailReturns(detail()),
    )
    const { router } = renderApp('/properties/42')

    await user.click(await screen.findByRole('button', { name: /^watch 12 smith st/i }))
    await waitFor(() => expect(router.state.location.pathname).toBe('/login'))
    await user.type(screen.getByLabelText(/email/i), 'demo@example.com')
    await user.type(screen.getByLabelText(/password/i), 'correct horse battery')
    await user.click(screen.getByRole('button', { name: /^log in|^sign in/i }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/properties/42'))
    expect(await screen.findByRole('link', { name: /search properties/i })).toHaveAttribute('href', '/search')
    expect(screen.queryByRole('button', { name: /back to/i })).not.toBeInTheDocument()
  })

  it('puts keyboard focus back on the card that was opened', async () => {
    const user = userEvent.setup()
    server.use(signedOut(), searchReturns(smithSt, makeProperty({ id: 43 })), detailReturns(detail()))
    renderApp('/search')

    await user.click(await screen.findByRole('link', { name: '12 Smith St' }))
    await user.click(await screen.findByRole('button', { name: /back to results/i }))

    await waitFor(() => expect(screen.getByRole('link', { name: '12 Smith St' })).toHaveFocus())
  })

  it('keeps a Watch click made while the page is still loading, with no flicker back', async () => {
    const user = userEvent.setup()
    let watched = false
    let releaseFirstLoad: () => void = () => {}
    const firstLoad = new Promise<void>((resolve) => (releaseFirstLoad = resolve))
    let releasePut: () => void = () => {}
    const putHeld = new Promise<void>((resolve) => (releasePut = resolve))
    let loads = 0
    server.use(
      signedIn(),
      searchReturns(smithSt),
      http.get('*/api/v1/properties/:id', async () => {
        // The first load was sent before the click, so it answers "not watched", late.
        const answer = detail({ watched })
        if (++loads === 1) await firstLoad
        return HttpResponse.json({ data: answer })
      }),
      http.put('*/api/v1/watchlist/42', async () => {
        await putHeld
        watched = true
        return HttpResponse.json({ data: { ...smithSt, watched: true } })
      }),
    )
    renderApp('/search')
    await user.click(await screen.findByRole('link', { name: '12 Smith St' }))
    await screen.findByText('Loading description…')
    const watchingButton = () => screen.getByRole('button', { name: /^watching 12 smith st/i })

    await user.click(screen.getByRole('button', { name: /^watch 12 smith st/i }))
    expect(await screen.findByRole('button', { name: /^watching 12 smith st/i })).toBeInTheDocument()

    // The stale load lands while the watch request is still in flight: it was
    // cancelled, so its answer is thrown away (the page is still loading) and
    // can't put "Watch" back once the request settles.
    releaseFirstLoad()
    await act(() => delay(50))
    expect(screen.getByText('Loading description…')).toBeInTheDocument()
    expect(watchingButton()).toHaveAttribute('aria-pressed', 'true')

    // Once the server agrees, the page loads, still watched.
    releasePut()
    await screen.findByText('Walk to cafes and parks.', { exact: false })
    expect(watchingButton()).toHaveAttribute('aria-pressed', 'true')
    expect(loads).toBe(2)
  })

  it('doesn’t move focus to a card after an ordinary visit to a list', async () => {
    const user = userEvent.setup()
    server.use(signedOut(), searchReturns(smithSt), detailReturns(detail()))
    const { router } = renderApp('/search')

    await user.click(await screen.findByRole('link', { name: '12 Smith St' }))
    await screen.findByText('Walk to cafes and parks.', { exact: false })
    // A fresh visit to search (a new history entry), not Back.
    await act(() => router.navigate({ to: '/search' }))

    await screen.findByRole('link', { name: '12 Smith St' })
    expect(screen.getByRole('link', { name: '12 Smith St' })).not.toHaveFocus()
  })

  it('stops showing “Watching” once the user signs out', async () => {
    const user = userEvent.setup()
    let signedInNow = true
    server.use(
      signedIn(),
      http.get('*/api/v1/properties/:id', () => HttpResponse.json({ data: detail({ watched: signedInNow }) })),
      http.delete('*/api/v1/auth/logout', () => {
        signedInNow = false
        return new HttpResponse(null, { status: 204 })
      }),
    )
    renderApp('/properties/42')
    await screen.findByRole('button', { name: /^watching 12 smith st/i })

    await user.click(await screen.findByRole('button', { name: 'Log out' }))

    expect(await screen.findByRole('button', { name: /^watch 12 smith st/i })).toHaveAttribute('aria-pressed', 'false')
  })

  it('says when older changes are left out, and hides amounts the API hid', async () => {
    server.use(
      signedOut(),
      detailReturns(
        detail({
          priceCents: null,
          priceDisplay: 'Contact agent',
          historyComplete: false,
          history: [{ id: 9, kind: 'price_changed', from: null, to: null, createdAt: '2026-11-20T09:00:00Z' }],
        }),
      ),
    )
    renderApp('/properties/42')

    expect(await screen.findByText('Price updated')).toBeInTheDocument()
    expect(screen.getByText("Earlier changes aren't shown.")).toBeInTheDocument()
  })

  it('lists no rooms for land', async () => {
    server.use(
      signedOut(),
      detailReturns(
        detail({ propertyType: 'land', bedrooms: 0, bathrooms: 0, carSpaces: 0, landSizeSqm: 800 }),
      ),
    )
    renderApp('/properties/42')

    const facts = await screen.findByRole('region', { name: 'Property details' })
    expect(within(facts).queryByText('Bedrooms')).not.toBeInTheDocument()
    expect(within(facts).getByText('800 m²')).toBeInTheDocument()
  })

  it('names the tab and gives the page a heading when the property isn’t found', async () => {
    server.use(signedOut(), detailReturns(detail()))
    renderApp('/properties/999')

    expect(await screen.findByRole('heading', { level: 1, name: "We couldn't find this property" })).toBeInTheDocument()
    expect(document.title).toBe('Property not found | Property Search')
  })

  it('refetches an open page after the live connection comes back', async () => {
    let loads = 0
    server.use(
      signedIn(),
      http.get('*/api/v1/properties/:id', () => {
        loads++
        return HttpResponse.json({ data: detail({ watched: true }) })
      }),
    )
    renderApp('/properties/42')
    await screen.findByText('Walk to cafes and parks.', { exact: false })
    await waitFor(() => expect(fakeCable.active()).toHaveLength(1))
    const { mixin } = fakeCable.active()[0]

    act(() => mixin.connected?.({ reconnected: false }))
    act(() => mixin.connected?.({ reconnected: true }))

    await waitFor(() => expect(loads).toBe(2))
  })
})
