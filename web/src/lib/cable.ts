import { createConsumer, type Consumer } from '@rails/actioncable'

let consumer: Consumer | null = null

export function getConsumer(token: string): Consumer {
  consumer?.disconnect()
  consumer = createConsumer(`/cable?token=${encodeURIComponent(token)}`)
  return consumer
}

export function disconnectConsumer() {
  consumer?.disconnect()
  consumer = null
}
