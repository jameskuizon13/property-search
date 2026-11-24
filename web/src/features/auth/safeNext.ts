// Control characters and backslashes are rejected outright: URL parsers strip
// tabs/newlines and treat `\` as `/`, so `/\t/evil.example` or `/\evil.example`
// would otherwise resolve to another host.
// oxlint-disable-next-line no-control-regex
const UNSAFE_CHARS = /[\u0000-\u001f\u007f\\]/

/**
 * Only same-app paths are allowed as a post-login target, so `?next=` can't
 * be used as an open redirect (`//evil.example`, `https://…`, `javascript:`).
 * Returns the normalised path, query and hash.
 */
export function safeNext(next: string | undefined, fallback = '/search'): string {
  if (!next || !next.startsWith('/') || UNSAFE_CHARS.test(next)) return fallback
  try {
    const url = new URL(next, window.location.origin)
    if (url.origin !== window.location.origin) return fallback
    return `${url.pathname}${url.search}${url.hash}`
  } catch {
    return fallback
  }
}
