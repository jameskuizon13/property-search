import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterAll, afterEach, beforeAll } from 'vitest'
import { MockIntersectionObserver } from './intersectionObserver'
import { server } from './server'

beforeAll(() => server.listen({ onUnhandledFrame: 'error' }))
afterEach(() => {
  server.resetHandlers()
  cleanup()
  MockIntersectionObserver.instances.clear()
})
afterAll(() => server.close())

// jsdom doesn't implement scrolling; the router's scroll restoration calls it.
window.scrollTo = () => {}
globalThis.IntersectionObserver = MockIntersectionObserver as unknown as typeof IntersectionObserver
