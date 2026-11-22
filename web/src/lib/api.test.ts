import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { server } from '@/test/server'
import { ApiError, apiFetch } from './api'

describe('apiFetch', () => {
  it('returns parsed JSON on success', async () => {
    server.use(http.get('*/api/v1/ping', () => HttpResponse.json({ ok: true })))
    await expect(apiFetch('/ping')).resolves.toEqual({ ok: true })
  })

  it('throws an ApiError built from the error envelope', async () => {
    server.use(
      http.get('*/api/v1/ping', () =>
        HttpResponse.json({ error: { code: 'unauthorized', message: 'Nope' } }, { status: 401 }),
      ),
    )
    await expect(apiFetch('/ping')).rejects.toMatchObject(
      new ApiError(401, 'unauthorized', 'Nope'),
    )
  })
})
