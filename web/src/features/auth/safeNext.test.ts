import { describe, expect, it } from 'vitest'
import { safeNext } from './safeNext'

describe('safeNext', () => {
  it('keeps same-app paths, including their query string and hash', () => {
    expect(safeNext('/watchlist')).toBe('/watchlist')
    expect(safeNext('/search?q=fitzroy&minBedrooms=2')).toBe('/search?q=fitzroy&minBedrooms=2')
    expect(safeNext('/search#results')).toBe('/search#results')
  })

  it.each([
    undefined,
    '',
    'https://evil.example',
    '//evil.example',
    '/\\evil.example',
    '/\\/evil.example',
    '/\t/evil.example',
    '/\n/evil.example',
    '/\r\n/evil.example',
    '/\u0000/evil.example',
    'javascript:alert(1)',
    ' /watchlist',
    // dot segments that normalise to a protocol-relative `//evil.example`
    '/.//evil.example',
    '/..//evil.example',
    '/%2e//evil.example',
    '/a/..//evil.example',
  ])('falls back to /search for %j', (next) => {
    expect(safeNext(next)).toBe('/search')
  })

  it('keeps percent-encoded slashes as a harmless same-app path', () => {
    expect(safeNext('/%2F%2Fevil.example')).toBe('/%2F%2Fevil.example')
  })
})
