import { setupServer } from 'msw/node'
import { defaultPropertyHandlers } from './propertyHandlers'

// Default handlers live here; individual tests override with server.use(...)
export const server = setupServer(...defaultPropertyHandlers)
