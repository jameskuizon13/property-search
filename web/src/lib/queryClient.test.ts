import { describe, expect, it } from 'vitest'
import { ApiError } from './api'
import { shouldRetry } from './queryClient'

describe('shouldRetry', () => {
  it('retries a network error or a 5xx once', () => {
    expect(shouldRetry(0, new TypeError('Failed to fetch'))).toBe(true)
    expect(shouldRetry(0, new ApiError(503, 'unavailable', 'x'))).toBe(true)
    expect(shouldRetry(1, new ApiError(503, 'unavailable', 'x'))).toBe(false)
  })

  it('never retries a 4xx, which would fail the same way', () => {
    expect(shouldRetry(0, new ApiError(422, 'validation_failed', 'x'))).toBe(false)
    expect(shouldRetry(0, new ApiError(404, 'not_found', 'x'))).toBe(false)
  })
})
