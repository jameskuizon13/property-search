import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { delay, http } from 'msw'
import { describe, expect, it } from 'vitest'
import { signedOut } from '@/test/authHandlers'
import { scrollSentinelIntoView } from '@/test/intersectionObserver'
import { makeProperties, makeProperty, page, rateLimited, serverError } from '@/test/propertyHandlers'
import { renderApp } from '@/test/renderApp'
import { server } from '@/test/server'

/** Records the query string of every search request. */
function recordSearches(respond: (params: URLSearchParams) => Response | Promise<Response>) {
  const requests: URLSearchParams[] = []
  server.use(
    http.get('*/api/v1/properties', ({ request }) => {
      const params = new URL(request.url).searchParams
      requests.push(params)
      return respond(params)
    }),
  )
  return requests
}

const cards = () => within(screen.getByRole('region', { name: 'Search results' })).getAllByRole('article')

describe('search results', () => {
  it('shows skeletons, then the cards and the total', async () => {
    server.use(
      signedOut(),
      http.get('*/api/v1/properties', async () => {
        await delay(50)
        return page(
          [makeProperty({ id: 1, streetAddress: '12 Smith St', priceDisplay: '$850,000', status: 'under_offer' })],
          { totalCount: 1 },
        )
      }),
    )
    renderApp('/search')

    expect(await screen.findByText('Loading properties')).toBeInTheDocument()
    const card = await screen.findByRole('article', { name: '12 Smith St' })
    expect(within(card).getByText('$850,000')).toBeInTheDocument()
    expect(within(card).getByText('Under offer')).toBeInTheDocument()
    expect(within(card).getByText('3 beds · 2 baths · 1 car · 320 m²')).toBeInTheDocument()
    expect(within(card).getByText('House')).toBeInTheDocument()
    expect(screen.getByText('1 property')).toBeInTheDocument()
    expect(screen.getByText('End of results')).toBeInTheDocument()
  })

  it('explains which filters to loosen when nothing matches', async () => {
    server.use(signedOut())
    renderApp('/search?minBedrooms=5&excludeUnderOffer=true')

    expect(await screen.findByRole('heading', { name: 'No properties match your search' })).toBeInTheDocument()
    expect(screen.getByText(/fewer bedrooms, or including properties under offer/)).toBeInTheDocument()
  })

  it('shows an error with a retry that loads the results', async () => {
    let fail = true
    server.use(
      signedOut(),
      http.get('*/api/v1/properties', () => (fail ? serverError() : page(makeProperties(2), { totalCount: 2 }))),
    )
    const user = userEvent.setup()
    renderApp('/search')

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent("We couldn't load properties")
    expect(alert).toHaveTextContent('Something went wrong on our side')
    fail = false
    await user.click(within(alert).getByRole('button', { name: 'Retry' }))

    await waitFor(() => expect(cards()).toHaveLength(2))
  })

  it('says when the search was rate limited, without retrying on its own', async () => {
    let requests = 0
    server.use(
      signedOut(),
      http.get('*/api/v1/properties', () => {
        requests += 1
        return rateLimited()
      }),
    )
    renderApp('/search')

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('Too many requests in a short time')
    expect(requests).toBe(1)
  })

  it('skips layout for off-screen cards rather than virtualising the list', async () => {
    server.use(signedOut(), http.get('*/api/v1/properties', () => page(makeProperties(2), { totalCount: 2 })))
    renderApp('/search')
    await waitFor(() => expect(cards()).toHaveLength(2))
    for (const item of screen.getByRole('region', { name: 'Search results' }).querySelectorAll('ul > li')) {
      expect(item).toHaveClass('offscreen-skip')
    }
  })

  it('notes that price sorts leave out withheld prices', async () => {
    server.use(signedOut())
    renderApp('/search?sort=price_asc')

    expect(await screen.findByText(/Price sorts leave out listings with no price shown/)).toBeInTheDocument()
  })
})

describe('filters', () => {
  it('writes a filter to the URL and starts again from the first batch', async () => {
    const requests = recordSearches(() => page(makeProperties(1), { totalCount: 1 }))
    server.use(signedOut())
    const user = userEvent.setup()
    const { router } = renderApp('/search')
    await screen.findByText('1 property')
    expect(screen.queryByRole('button', { name: 'Clear filters' })).not.toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Bedrooms'), '3+')

    await waitFor(() => expect(router.state.location.search).toMatchObject({ minBedrooms: 3 }))
    expect(router.state.location.searchStr).toBe('?minBedrooms=3')
    await waitFor(() => expect(requests.at(-1)?.get('minBedrooms')).toBe('3'))
    expect(requests.at(-1)?.has('cursor')).toBe(false)

    await user.click(screen.getByRole('button', { name: 'Clear filters' }))
    await waitFor(() => expect(router.state.location.searchStr).toBe(''))
    expect(screen.getByLabelText('Bedrooms')).toHaveValue('')
  })

  it('debounces the text search and sends only the finished word', async () => {
    const requests = recordSearches(() => page([], { totalCount: 0 }))
    server.use(signedOut())
    const user = userEvent.setup()
    const { router } = renderApp('/search')
    await screen.findByRole('heading', { name: 'No properties match your search' })

    await user.type(screen.getByLabelText('Suburb, street or postcode'), 'fitz')

    await waitFor(() => expect(router.state.location.searchStr).toBe('?q=fitz'))
    await waitFor(() => expect(requests.at(-1)?.get('q')).toBe('fitz'))
    expect(requests.map((r) => r.get('q')).filter(Boolean)).toEqual(['fitz'])
  })

  it('shows only the latest filters when a slow response for older ones arrives late', async () => {
    server.use(
      signedOut(),
      http.get('*/api/v1/properties', async ({ request }) => {
        const beds = new URL(request.url).searchParams.get('minBedrooms')
        if (beds === '2') {
          await delay(150)
          return page([makeProperty({ id: 2, streetAddress: 'Slow St' })], { totalCount: 1 })
        }
        if (beds === '3') return page([makeProperty({ id: 3, streetAddress: 'Fast St' })], { totalCount: 1 })
        return page([makeProperty({ id: 1, streetAddress: 'First St' })], { totalCount: 1 })
      }),
    )
    const user = userEvent.setup()
    renderApp('/search')
    await screen.findByRole('article', { name: 'First St' })

    await user.selectOptions(screen.getByLabelText('Bedrooms'), '2+')
    await user.selectOptions(screen.getByLabelText('Bedrooms'), '3+')

    expect(await screen.findByRole('article', { name: 'Fast St' })).toBeInTheDocument()
    await new Promise((resolve) => setTimeout(resolve, 250))
    expect(screen.queryByRole('article', { name: 'Slow St' })).not.toBeInTheDocument()
    expect(screen.getByRole('article', { name: 'Fast St' })).toBeInTheDocument()
  })

  it('blocks a max price below the min price', async () => {
    server.use(signedOut())
    const user = userEvent.setup()
    renderApp('/search')

    await user.selectOptions(await screen.findByLabelText('Min price'), '$500k')

    const max = screen.getByLabelText('Max price')
    expect(within(max).getByRole('option', { name: '$400k' })).toBeDisabled()
    expect(within(max).getByRole('option', { name: '$500k' })).toBeEnabled()
  })

  it('drops invalid values from a hand-edited URL instead of failing the search', async () => {
    const requests = recordSearches(() => page([], { totalCount: 0 }))
    server.use(signedOut())
    const types = encodeURIComponent(JSON.stringify(['house', 'castle']))
    renderApp(`/search?propertyTypes=${types}&sort=bogus&minBedrooms=99&q=3065`)

    await waitFor(() => expect(requests.length).toBeGreaterThan(0))
    const params = requests.at(-1)!
    expect(params.get('propertyTypes')).toBe('house')
    expect(params.get('q')).toBe('3065')
    expect(params.has('sort')).toBe(false)
    expect(params.has('minBedrooms')).toBe(false)
  })

  it('drops control characters in the text, which the API would reject', async () => {
    const requests = recordSearches(() => page([], { totalCount: 0 }))
    server.use(signedOut())
    renderApp('/search?q=ab%00')

    expect(await screen.findByRole('heading', { name: 'No properties match your search' })).toBeInTheDocument()
    expect(requests.at(-1)?.has('q')).toBe(false)
  })

  it("accepts the API's comma form for property types", async () => {
    const requests = recordSearches(() => page([], { totalCount: 0 }))
    server.use(signedOut())
    renderApp('/search?propertyTypes=villa,house')

    await waitFor(() => expect(requests.at(-1)?.get('propertyTypes')).toBe('house,villa'))
  })

  it("doesn't treat unknown URL keys as filters", async () => {
    server.use(signedOut())
    const { queryClient } = renderApp('/search?utm_source=newsletter')

    await screen.findByRole('heading', { name: 'No properties match your search' })
    expect(screen.queryByRole('button', { name: 'Clear filters' })).not.toBeInTheDocument()
    expect(queryClient.getQueryCache().find({ queryKey: ['properties', 'list', {}], exact: true })).toBeDefined()
  })

  it('writes property types and the exclude toggles to the URL', async () => {
    const requests = recordSearches(() => page([], { totalCount: 0 }))
    server.use(signedOut())
    const user = userEvent.setup()
    const { router } = renderApp('/search')

    await user.click(await screen.findByRole('checkbox', { name: 'Villa' }))
    await user.click(screen.getByRole('checkbox', { name: 'House' }))
    await user.click(screen.getByRole('checkbox', { name: 'Exclude under offer' }))
    await user.click(screen.getByRole('checkbox', { name: 'Exclude price withheld' }))

    await waitFor(() =>
      expect(router.state.location.search).toMatchObject({
        propertyTypes: ['villa', 'house'],
        excludeUnderOffer: true,
        excludePriceWithheld: true,
      }),
    )
    await waitFor(() => expect(requests.at(-1)?.get('excludePriceWithheld')).toBe('true'))
    expect(requests.at(-1)?.get('propertyTypes')).toBe('house,villa')
    expect(requests.at(-1)?.get('excludeUnderOffer')).toBe('true')

    await user.click(screen.getByRole('checkbox', { name: 'Villa' }))
    await waitFor(() => expect(router.state.location.search).toMatchObject({ propertyTypes: ['house'] }))
  })

  it('ignores text shorter than two characters', async () => {
    const requests = recordSearches(() => page([], { totalCount: 0 }))
    server.use(signedOut())
    renderApp('/search?q=f')

    await waitFor(() => expect(requests.length).toBe(1))
    expect(requests[0].has('q')).toBe(false)
    expect(screen.getByLabelText('Suburb, street or postcode')).toHaveValue('f')
  })
})

describe('infinite scroll', () => {
  function pagedSearch({ failSecond = false } = {}) {
    let secondFails = failSecond
    return recordSearches(async (params) => {
      if (!params.get('cursor')) return page(makeProperties(20, 1), { hasMore: true, nextCursor: 'c1', totalCount: 25 })
      await delay(20)
      if (secondFails) {
        secondFails = false
        return serverError()
      }
      return page(makeProperties(5, 21), { hasMore: false })
    })
  }

  it('loads the next batch when the sentinel comes into view, once, and stops at the end', async () => {
    const requests = pagedSearch()
    server.use(signedOut())
    renderApp('/search')
    await screen.findByText('25 properties')
    expect(cards()).toHaveLength(20)

    scrollSentinelIntoView()
    scrollSentinelIntoView()

    await waitFor(() => expect(cards()).toHaveLength(25))
    expect(requests.filter((r) => r.get('cursor') === 'c1')).toHaveLength(1)
    expect(screen.getByText('End of results')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Load more' })).not.toBeInTheDocument()
  })

  it('has a Load more button for keyboard and screen-reader users', async () => {
    pagedSearch()
    server.use(signedOut())
    const user = userEvent.setup()
    renderApp('/search')
    await screen.findByText('25 properties')

    await user.click(screen.getByRole('button', { name: 'Load more' }))

    // That was the last batch, so the button goes and focus moves to the end marker, not <body>.
    await waitFor(() => expect(cards()).toHaveLength(25))
    expect(screen.getByText('End of results')).toHaveFocus()
  })

  it('keeps focus on the button while a batch loads', async () => {
    pagedSearch()
    server.use(signedOut())
    const user = userEvent.setup()
    renderApp('/search')
    await screen.findByText('25 properties')
    const button = screen.getByRole('button', { name: 'Load more' })

    await user.click(button)

    expect(button).toHaveFocus()
    expect(button).toHaveTextContent('Loading…')
    expect(button).toHaveAttribute('aria-disabled', 'true')
  })

  it('shows Back to top once scrolled down, and moves focus to the heading', async () => {
    pagedSearch()
    server.use(signedOut())
    const user = userEvent.setup()
    renderApp('/search')
    await screen.findByText('25 properties')
    scrollSentinelIntoView()
    await waitFor(() => expect(cards()).toHaveLength(25))
    expect(screen.queryByRole('button', { name: 'Back to top' })).not.toBeInTheDocument()

    Object.defineProperty(window, 'scrollY', { value: 5000, configurable: true })
    act(() => void window.dispatchEvent(new Event('scroll')))
    await user.click(screen.getByRole('button', { name: 'Back to top' }))

    expect(screen.getByRole('heading', { name: 'Search properties' })).toHaveFocus()
    Object.defineProperty(window, 'scrollY', { value: 0, configurable: true })
  })

  it('shows an inline retry when a batch fails, keeping the loaded results', async () => {
    pagedSearch({ failSecond: true })
    server.use(signedOut())
    const user = userEvent.setup()
    renderApp('/search')
    await screen.findByText('25 properties')

    scrollSentinelIntoView()

    expect(await screen.findByRole('alert')).toHaveTextContent("Couldn't load more properties.")
    expect(cards()).toHaveLength(20)

    const retry = screen.getByRole('button', { name: 'Retry' })
    await user.click(retry)
    await waitFor(() => expect(cards()).toHaveLength(25))
    expect(screen.getByText('End of results')).toHaveFocus()
  })

  it('says when a next batch was rate limited', async () => {
    server.use(
      signedOut(),
      http.get('*/api/v1/properties', ({ request }) =>
        new URL(request.url).searchParams.get('cursor')
          ? rateLimited()
          : page(makeProperties(20), { hasMore: true, nextCursor: 'c1', totalCount: 25 }),
      ),
    )
    renderApp('/search')
    await screen.findByText('25 properties')

    scrollSentinelIntoView()

    expect(await screen.findByRole('alert')).toHaveTextContent('Too many requests in a short time')
    expect(cards()).toHaveLength(20)
  })

  it('shows a repeated listing only once', async () => {
    recordSearches((params) =>
      params.get('cursor')
        ? page(makeProperties(2, 2), { hasMore: false })
        : page(makeProperties(2, 1), { hasMore: true, nextCursor: 'c1', totalCount: 3 }),
    )
    server.use(signedOut())
    renderApp('/search')
    await screen.findByText('3 properties')

    scrollSentinelIntoView()

    await screen.findByText('End of results')
    expect(cards()).toHaveLength(3)
  })
})
