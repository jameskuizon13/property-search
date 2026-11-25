import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { describe, expect, it, vi } from 'vitest'
import { apiFetch } from '@/lib/api'
import { demoUser, signedIn, signedOut } from '@/test/authHandlers'
import { renderApp } from '@/test/renderApp'
import { server } from '@/test/server'

const { disconnectConsumer } = vi.hoisted(() => ({ disconnectConsumer: vi.fn() }))
vi.mock('@/lib/cable', () => ({ disconnectConsumer, getConsumer: vi.fn() }))

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

  it('shows a generic error on bad credentials and stays on the page', async () => {
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

    expect(await screen.findByRole('alert')).toHaveTextContent('Invalid email or password')
    expect(router.state.location.pathname).toBe('/login')
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
  })
})
