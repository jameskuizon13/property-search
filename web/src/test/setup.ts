import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterAll, afterEach, beforeAll, vi } from 'vitest'
import { fakeCable } from './cable'
import { MockIntersectionObserver } from './intersectionObserver'
import { server } from './server'

// No real WebSocket in jsdom: every test gets the fake consumer.
vi.mock('@/lib/cable', async () => (await import('./cable')).fakeCable.module)

beforeAll(() => server.listen({ onUnhandledFrame: 'error' }))
afterEach(() => {
  server.resetHandlers()
  cleanup()
  MockIntersectionObserver.instances.clear()
  fakeCable.reset()
})
afterAll(() => server.close())

// jsdom doesn't implement scrolling; the router's scroll restoration calls it.
window.scrollTo = () => {}
globalThis.IntersectionObserver = MockIntersectionObserver as unknown as typeof IntersectionObserver
