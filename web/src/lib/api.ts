export class ApiError extends Error {
  status: number
  code: string
  details?: Record<string, string[]>

  constructor(status: number, code: string, message: string, details?: Record<string, string[]>) {
    super(message)
    this.status = status
    this.code = code
    this.details = details
  }
}

type RequestOptions = Omit<RequestInit, 'body'> & {
  body?: unknown
  /**
   * Return the 401 to the caller instead of running the global "signed out"
   * handler. Used by GET /me (a 401 just means "nobody is signed in") and by
   * login (a 401 means "wrong password", shown as a toast).
   */
  allowUnauthorized?: boolean
}

let unauthorizedHandler: (() => void) | null = null

/** Registers what happens when any request comes back 401 (see useSessionEvents). */
export function setUnauthorizedHandler(handler: (() => void) | null) {
  unauthorizedHandler = handler
}

/**
 * The one fetch client. Auth is an HttpOnly cookie set by the API, so the app
 * never sees or stores a token: `credentials: 'include'` makes the browser
 * attach it.
 */
export async function apiFetch<T>(
  path: string,
  { body, headers, allowUnauthorized = false, ...init }: RequestOptions = {},
): Promise<T> {
  const res = await fetch(`/api/v1${path}`, {
    ...init,
    credentials: 'include',
    headers: {
      Accept: 'application/json',
      ...(body !== undefined && { 'Content-Type': 'application/json' }),
      ...headers,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })

  if (res.status === 204) return undefined as T

  const json = await res.json().catch(() => null)
  if (!res.ok) {
    if (res.status === 401 && !allowUnauthorized) unauthorizedHandler?.()
    const err = json?.error ?? {}
    throw new ApiError(res.status, err.code ?? 'unknown_error', err.message ?? res.statusText, err.details)
  }
  return json as T
}
