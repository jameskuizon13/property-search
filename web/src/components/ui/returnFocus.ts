/**
 * Keyboard users who open a card and come back should land on that card, not
 * at the top of the page. The card's link remembers its href and the history
 * entry of the list it was on; when that same entry shows again (Back, from
 * the page's link or the browser), the list focuses the link. A fresh visit
 * to a list is a new history entry, so it never matches: opening a card and
 * then clicking "Watchlist" in the header doesn't move focus anywhere.
 * Session storage, because the list unmounts while the property page shows.
 */
const KEY = 'property-search:return-focus'
/** Only app paths like /properties/42 go into the selector below. */
const SAFE_HREF = /^\/[\w/-]+$/

type Stored = { href: string; entry: string }

export function rememberReturnFocus(href: string, entry: string | undefined) {
  if (!entry) return
  try {
    sessionStorage.setItem(KEY, JSON.stringify({ href, entry } satisfies Stored))
  } catch {
    // Storage blocked (private mode, sandbox): focus just isn't restored.
  }
}

/** On the list's history entry `entry`, focuses the remembered link if `container` holds it. */
export function restoreReturnFocus(container: HTMLElement | null, entry: string | undefined) {
  let stored: Partial<Stored> | null = null
  try {
    stored = JSON.parse(sessionStorage.getItem(KEY) ?? 'null') as Partial<Stored> | null
    if (!entry || stored?.entry !== entry) return
    sessionStorage.removeItem(KEY)
  } catch {
    return
  }
  const href = stored.href
  if (!href || !SAFE_HREF.test(href)) return
  container?.querySelector<HTMLAnchorElement>(`a[href="${href}"]`)?.focus({ preventScroll: true })
}
