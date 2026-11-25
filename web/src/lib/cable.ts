import { createConsumer, type Consumer } from '@rails/actioncable'

let consumer: Consumer | null = null

/**
 * The WebSocket handshake carries the same HttpOnly auth cookie as REST calls,
 * so the URL holds no token.
 */
export function getConsumer(): Consumer {
  consumer ??= createConsumer('/cable')
  return consumer
}

export function disconnectConsumer() {
  consumer?.disconnect()
  consumer = null
}
