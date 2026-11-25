import { act } from '@testing-library/react'

/**
 * jsdom has no IntersectionObserver. This one records what is observed, and
 * `scrollSentinelIntoView()` reports every observed element as visible, the
 * way the browser does when the user scrolls near the end of the list.
 */
export class MockIntersectionObserver {
  static instances = new Set<MockIntersectionObserver>()

  readonly root = null
  readonly rootMargin: string
  readonly thresholds: number[] = []
  readonly elements = new Set<Element>()
  private readonly callback: IntersectionObserverCallback

  constructor(callback: IntersectionObserverCallback, options?: IntersectionObserverInit) {
    this.callback = callback
    this.rootMargin = options?.rootMargin ?? ''
    MockIntersectionObserver.instances.add(this)
  }

  observe(element: Element) {
    this.elements.add(element)
  }

  unobserve(element: Element) {
    this.elements.delete(element)
  }

  disconnect() {
    this.elements.clear()
    MockIntersectionObserver.instances.delete(this)
  }

  takeRecords(): IntersectionObserverEntry[] {
    return []
  }

  intersect() {
    const entries = [...this.elements].map(
      (target) => ({ target, isIntersecting: true, intersectionRatio: 1 }) as IntersectionObserverEntry,
    )
    if (entries.length > 0) this.callback(entries, this as unknown as IntersectionObserver)
  }
}

export function scrollSentinelIntoView() {
  act(() => {
    for (const observer of [...MockIntersectionObserver.instances]) observer.intersect()
  })
}
