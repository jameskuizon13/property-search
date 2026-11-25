import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { apiFetch } from '@/lib/api'
import { demoUser, signedIn, signedOut } from '@/test/authHandlers'
import { renderApp } from '@/test/renderApp'
import { server } from '@/test/server'
import { makeProperty, page } from '@/test/propertyHandlers'
import { fakeCable } from '@/test/cable'
import { toasts } from '@/test/utils'

const { disconnectConsumer } = fakeCable.module

describe('protected routes', () => {
  it('redirects a signed-out user from /watchlist to /login with a return target', async () => {
    server.use(signedOut())
    const { router } = renderApp('/watchlist')

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/login')
    expect(router.state.location.search).toEqual({ next: '/watchlist' })
  })

  it('shows the protected page to a signed-in user', async () => {
    server.use(signedIn())
    renderApp('/watchlist')

    expect(await screen.findByRole('heading', { name: 'Your watchlist' })).toBeInTheDocument()
    expect(screen.getByText('Demo User')).toBeInTheDocument()
  })

  it('leaves public pages public', async () => {
    server.use(signedOut())
    const { router } = renderApp('/search')

    expect(await screen.findByRole('heading', { name: 'Search properties' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/search')
  })

  it('sends the user to /login when a later request returns 401', async () => {
    server.use(
      signedIn(),
      http.get('*/api/v1/watchlist', () =>
        HttpResponse.json({ error: { code: 'unauthorized', message: 'expired' } }, { status: 401 }),
      ),
    )
    const { router, queryClient } = renderApp('/watchlist')
    await screen.findByRole('heading', { name: 'Your watchlist' })

    await apiFetch('/watchlist').catch(() => {})

    await waitFor(() => expect(router.state.location.pathname).toBe('/login'))
    expect(router.state.location.search).toEqual({ next: '/watchlist' })
    expect(queryClient.getQueryData(['me'])).toBeNull()
    expect(toasts().getByText("You've been signed out")).toBeInTheDocument()
  })

  it('keeps a public page in place on a 401, in its signed-out view', async () => {
    server.use(signedIn())
    const { router } = renderApp('/search')
    await screen.findByRole('button', { name: 'Log out' })

    server.use(
      http.get('*/api/v1/ping', () =>
        HttpResponse.json({ error: { code: 'unauthorized', message: 'expired' } }, { status: 401 }),
      ),
    )
    await apiFetch('/ping').catch(() => {})

    expect(await screen.findByRole('link', { name: 'Sign in' })).toBeInTheDocument()
    expect(toasts().getByText("You've been signed out")).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/search')
  })
})

describe('login', () => {
  it('signs in and returns to the page the user came from', async () => {
    let body: unknown
    server.use(
      signedOut(),
      http.post('*/api/v1/auth/login', async ({ request }) => {
        body = await request.json()
        return HttpResponse.json({ data: demoUser })
      }),
    )
    const user = userEvent.setup()
    const { router } = renderApp('/login?next=%2Fwatchlist')

    await user.type(await screen.findByLabelText('Email'), 'demo@example.com')
    await user.type(screen.getByLabelText('Password'), 'correct horse battery')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await screen.findByRole('heading', { name: 'Your watchlist' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/watchlist')
    expect(body).toEqual({ email: 'demo@example.com', password: 'correct horse battery' })
    expect(toasts().getByText('Signed in')).toBeInTheDocument()
  })

  it.each(['%2F%2Fevil.example', '%2F%09%2Fevil.example', '%2F%5Cevil.example'])(
    'does not crash when a signed-in user opens /login?next=%s',
    async (next) => {
      server.use(signedIn())
      const { router } = renderApp(`/login?next=${next}`)

      expect(await screen.findByRole('heading', { name: 'Search properties' })).toBeInTheDocument()
      expect(router.state.location.pathname).toBe('/search')
    },
  )

  it('ignores an off-site next target', async () => {
    server.use(
      signedOut(),
      http.post('*/api/v1/auth/login', () => HttpResponse.json({ data: demoUser })),
    )
    const user = userEvent.setup()
    const { router } = renderApp('/login?next=%2F%2Fevil.example')

    await user.type(await screen.findByLabelText('Email'), 'demo@example.com')
    await user.type(screen.getByLabelText('Password'), 'correct horse battery')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/search'))
  })

  it('shows a generic error toast on bad credentials, not the signed-out one', async () => {
    server.use(
      signedOut(),
      http.post('*/api/v1/auth/login', () =>
        HttpResponse.json({ error: { code: 'invalid_credentials', message: 'Invalid email or password' } }, { status: 401 }),
      ),
    )
    const user = userEvent.setup()
    const { router } = renderApp('/login')

    await user.type(await screen.findByLabelText('Email'), 'demo@example.com')
    await user.type(screen.getByLabelText('Password'), 'wrong password!')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await toasts().findByText('Invalid email or password')).toBeInTheDocument()
    expect(toasts().queryByText("You've been signed out")).not.toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/login')
  })

  it.each([
    [429, 'Too many attempts. Please wait a minute and try again.'],
    [500, 'Something went wrong. Please try again.'],
  ])('shows a toast when login fails with %i', async (status, message) => {
    server.use(
      signedOut(),
      http.post('*/api/v1/auth/login', () => HttpResponse.json({ error: { code: 'x', message: 'x' } }, { status })),
    )
    const user = userEvent.setup()
    renderApp('/login')

    await user.type(await screen.findByLabelText('Email'), 'demo@example.com')
    await user.type(screen.getByLabelText('Password'), 'correct horse battery')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await toasts().findByText(message)).toBeInTheDocument()
  })

  it('redirects a signed-in user away from /login', async () => {
    server.use(signedIn())
    const { router } = renderApp('/login?next=%2Fwatchlist')

    expect(await screen.findByRole('heading', { name: 'Your watchlist' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/watchlist')
  })
})

describe('signup', () => {
  it('shows field errors from a 422 next to the right inputs', async () => {
    server.use(
      signedOut(),
      http.post('*/api/v1/auth/signup', () =>
        HttpResponse.json(
          {
            error: {
              code: 'validation_failed',
              message: 'Validation failed',
              details: { email: ['has already been taken'], password: ['is too short (minimum is 12 characters)'] },
            },
          },
          { status: 422 },
        ),
      ),
    )
    const user = userEvent.setup()
    renderApp('/signup')

    await user.type(await screen.findByLabelText('Name'), 'Demo')
    await user.type(screen.getByLabelText('Email'), 'demo@example.com')
    await user.type(screen.getByLabelText('Password'), 'short')
    await user.click(screen.getByRole('button', { name: 'Create account' }))

    expect(await screen.findByLabelText('Email')).toHaveAccessibleDescription('has already been taken')
    expect(screen.getByLabelText('Password')).toHaveAccessibleDescription('is too short (minimum is 12 characters)')
    expect(screen.getByLabelText('Name')).not.toHaveAttribute('aria-invalid')
    expect(toasts().queryAllByRole('listitem')).toHaveLength(0)
  })

  it('creates the account and signs the user in', async () => {
    server.use(
      signedOut(),
      http.post('*/api/v1/auth/signup', () => HttpResponse.json({ data: demoUser }, { status: 201 })),
    )
    const user = userEvent.setup()
    renderApp('/signup')

    await user.type(await screen.findByLabelText('Name'), 'Demo User')
    await user.type(screen.getByLabelText('Email'), 'demo@example.com')
    await user.type(screen.getByLabelText('Password'), 'correct horse battery')
    await user.click(screen.getByRole('button', { name: 'Create account' }))

    expect(await screen.findByRole('heading', { name: 'Search properties' })).toBeInTheDocument()
    expect(screen.getByText('Demo User')).toBeInTheDocument()
    expect(toasts().getByText('Account created')).toBeInTheDocument()
  })
})

describe('logout', () => {
  it('clears the user, cached data and the socket, and shows the signed-out nav', async () => {
    let loggedOut = false
    server.use(
      http.get('*/api/v1/me', () =>
        loggedOut
          ? HttpResponse.json({ error: { code: 'unauthorized' } }, { status: 401 })
          : HttpResponse.json({ data: demoUser }),
      ),
      http.delete('*/api/v1/auth/logout', () => {
        loggedOut = true
        return new HttpResponse(null, { status: 204 })
      }),
    )
    const user = userEvent.setup()
    const { queryClient } = renderApp('/search')
    await screen.findByRole('button', { name: 'Log out' })
    queryClient.setQueryData(['watchlist'], { data: [{ id: 42 }] })
    disconnectConsumer.mockClear()

    await user.click(screen.getByRole('button', { name: 'Log out' }))

    expect(await screen.findByRole('link', { name: 'Sign in' })).toBeInTheDocument()
    expect(screen.queryByText('Demo User')).not.toBeInTheDocument()
    expect(loggedOut).toBe(true)
    expect(disconnectConsumer).toHaveBeenCalled()
    expect(queryClient.getQueryData(['watchlist'])).toBeUndefined()
    expect(queryClient.getQueryData(['me'])).toBeNull()
    expect(toasts().getByText('Signed out')).toBeInTheDocument()
  })

  it('stays on a public page, filters and all', async () => {
    server.use(signedIn(), http.delete('*/api/v1/auth/logout', () => new HttpResponse(null, { status: 204 })))
    const user = userEvent.setup()
    const { router } = renderApp('/search?minBedrooms=3')

    await user.click(await screen.findByRole('button', { name: 'Log out' }))

    expect(await screen.findByRole('link', { name: 'Sign in' })).toBeInTheDocument()
    expect(router.state.location.searchStr).toBe('?minBedrooms=3')
  })

  it('leaves the watchlist for search', async () => {
    server.use(signedIn(), http.delete('*/api/v1/auth/logout', () => new HttpResponse(null, { status: 204 })))
    const user = userEvent.setup()
    const { router } = renderApp('/watchlist')

    await user.click(await screen.findByRole('button', { name: 'Log out' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/search'))
  })

  it('reports a failed logout and keeps the user signed in', async () => {
    server.use(
      signedIn(),
      http.delete('*/api/v1/auth/logout', () =>
        HttpResponse.json({ error: { code: 'internal_error', message: 'x' } }, { status: 500 }),
      ),
    )
    const user = userEvent.setup()
    renderApp('/search')

    await user.click(await screen.findByRole('button', { name: 'Log out' }))

    expect(await toasts().findByText("Couldn't sign out. Please try again.")).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Log out' })).toBeInTheDocument()
  })

  it('tells the other tabs', async () => {
    server.use(signedIn(), http.delete('*/api/v1/auth/logout', () => new HttpResponse(null, { status: 204 })))
    const otherTab = new BroadcastChannel('auth')
    const received: unknown[] = []
    otherTab.onmessage = (event) => received.push(event.data)
    const user = userEvent.setup()
    renderApp('/search')

    await user.click(await screen.findByRole('button', { name: 'Log out' }))

    await waitFor(() => expect(received).toEqual(['signed-out']))
    otherTab.close()
  })
})

describe('signed out in another tab', () => {
  function signOutInAnotherTab() {
    const otherTab = new BroadcastChannel('auth')
    act(() => otherTab.postMessage('signed-out'))
    otherTab.close()
  }

  it('sends a protected page to /login with a toast', async () => {
    server.use(signedIn())
    const { router, queryClient } = renderApp('/watchlist')
    await screen.findByRole('heading', { name: 'Your watchlist' })
    disconnectConsumer.mockClear()

    signOutInAnotherTab()

    await waitFor(() => expect(router.state.location.pathname).toBe('/login'))
    expect(router.state.location.search).toEqual({ next: '/watchlist' })
    expect(toasts().getByText('You were signed out in another tab')).toBeInTheDocument()
    expect(queryClient.getQueryData(['me'])).toBeNull()
    expect(disconnectConsumer).toHaveBeenCalled()
  })

  it('keeps a public page where it is, in its signed-out view, without the user’s watched flags', async () => {
    let signedInNow = true
    server.use(
      signedIn(),
      http.get('*/api/v1/properties', () =>
        page([makeProperty({ id: 7, streetAddress: '7 Main St', watched: signedInNow })], { totalCount: 1 }),
      ),
    )
    const { router } = renderApp('/search')
    const button = await screen.findByRole('button', { name: /^Watch(ing)? 7 Main St$/ })
    expect(button).toHaveAttribute('aria-pressed', 'true')

    signedInNow = false
    signOutInAnotherTab()

    expect(await screen.findByRole('link', { name: 'Sign in' })).toBeInTheDocument()
    expect(toasts().getByText('You were signed out in another tab')).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/search')
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Watch 7 Main St' })).toHaveAttribute('aria-pressed', 'false'),
    )
  })

  it('says nothing in a tab that was already signed out', async () => {
    server.use(signedOut())
    renderApp('/search')
    await screen.findByRole('link', { name: 'Sign in' })

    signOutInAnotherTab()

    await new Promise((resolve) => setTimeout(resolve, 50))
    expect(toasts().queryAllByRole('listitem')).toHaveLength(0)
  })
})
