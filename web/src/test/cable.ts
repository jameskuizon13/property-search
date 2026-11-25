import { vi } from 'vitest'

/** The callbacks a component passed to `subscriptions.create`. */
export type CableMixin = {
  connected?: (data: { reconnected: boolean }) => void
  disconnected?: (data: { willAttemptReconnect: boolean }) => void
  rejected?: () => void
  received?: (message: unknown) => void | Promise<void>
}

type FakeSubscription = { channel: unknown; mixin: CableMixin; unsubscribe: ReturnType<typeof vi.fn> }

/**
 * A stand-in for the ActionCable consumer. Tests drive the callbacks directly
 * (`fakeCable.active()[0].mixin.received(...)` inside `act`). `test/setup.ts`
 * mocks `@/lib/cable` with the shared instance below for every test.
 */
export function createFakeCable() {
  const subscriptions: FakeSubscription[] = []
  const consumer = {
    subscriptions: {
      create: vi.fn((channel: unknown, mixin: CableMixin) => {
        const subscription: FakeSubscription = { channel, mixin, unsubscribe: vi.fn() }
        subscriptions.push(subscription)
        return subscription
      }),
    },
  }
  return {
    subscriptions,
    /** Every subscription that hasn't been unsubscribed, oldest first. */
    active: () => subscriptions.filter((s) => s.unsubscribe.mock.calls.length === 0),
    module: { getConsumer: vi.fn(() => consumer), disconnectConsumer: vi.fn() },
    reset() {
      subscriptions.length = 0
      consumer.subscriptions.create.mockClear()
      this.module.getConsumer.mockClear()
      this.module.disconnectConsumer.mockClear()
    },
  }
}

/** Shared by every test: `test/setup.ts` mocks `@/lib/cable` with it. */
export const fakeCable = createFakeCable()
