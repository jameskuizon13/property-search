import { http, HttpResponse } from 'msw'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { server } from '@/test/server'
import { ApiError, apiFetch, setUnauthorizedHandler } from './api'

describe('apiFetch', () => {
  afterEach(() => {
    setUnauthorizedHandler(null)
    vi.restoreAllMocks()
  })

  it('returns parsed JSON on success', async () => {
    server.use(http.get('*/api/v1/ping', () => HttpResponse.json({ ok: true })))
    await expect(apiFetch('/ping')).resolves.toEqual({ ok: true })
  })

  it('throws an ApiError built from the error envelope', async () => {
    server.use(
      http.get('*/api/v1/ping', () =>
        HttpResponse.json({ error: { code: 'not_found', message: 'Nope' } }, { status: 404 }),
      ),
    )
    await expect(apiFetch('/ping')).rejects.toMatchObject(new ApiError(404, 'not_found', 'Nope'))
  })

  it('sends the auth cookie and never an Authorization header', async () => {
    server.use(http.post('*/api/v1/ping', () => HttpResponse.json({ ok: true })))
    const fetchSpy = vi.spyOn(globalThis, 'fetch')

    await apiFetch('/ping', { method: 'POST', body: { a: 1 } })

    const init = fetchSpy.mock.calls[0][1]!
    expect(init.credentials).toBe('include')
    expect(init.headers).not.toHaveProperty('Authorization')
    expect(init.headers).toMatchObject({ 'Content-Type': 'application/json' })
  })

  it('runs the unauthorized handler on a 401', async () => {
    server.use(
      http.get('*/api/v1/watchlist', () =>
        HttpResponse.json({ error: { code: 'unauthorized', message: 'You need to sign in' } }, { status: 401 }),
      ),
    )
    const onUnauthorized = vi.fn()
    setUnauthorizedHandler(onUnauthorized)

    await expect(apiFetch('/watchlist')).rejects.toMatchObject({ status: 401, code: 'unauthorized' })
    expect(onUnauthorized).toHaveBeenCalledOnce()
  })

  it('leaves the 401 to the caller when allowUnauthorized is set', async () => {
    server.use(http.get('*/api/v1/me', () => HttpResponse.json({ error: { code: 'unauthorized' } }, { status: 401 })))
    const onUnauthorized = vi.fn()
    setUnauthorizedHandler(onUnauthorized)

    await expect(apiFetch('/me', { allowUnauthorized: true })).rejects.toBeInstanceOf(ApiError)
    expect(onUnauthorized).not.toHaveBeenCalled()
  })
})
