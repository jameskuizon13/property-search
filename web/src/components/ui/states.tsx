import type { ReactNode } from 'react'
import { ApiError } from '@/lib/api'

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="rounded-lg border border-dashed border-slate-300 bg-white px-6 py-12 text-center">
      <h2 className="text-lg font-semibold">{title}</h2>
      {children && <div className="mt-2 space-y-4 text-slate-600">{children}</div>}
    </div>
  )
}

/** For failures that leave the page with nothing to show, so it stays put (not a toast) with a Retry. */
function errorHint(error: Error | null) {
  if (!(error instanceof ApiError)) return 'Check your connection and try again.'
  if (error.status === 429) return 'Too many requests in a short time. Wait a moment, then retry.'
  if (error.status >= 500) return 'Something went wrong on our side. Please try again in a moment.'
  return 'Something about this request was not accepted. Try again, or start a new search.'
}

export function ErrorState({ title, error, onRetry }: { title: string; error: Error | null; onRetry: () => void }) {
  return (
    <div role="alert" className="rounded-lg border border-red-200 bg-red-50 px-6 py-12 text-center">
      <h2 className="text-lg font-semibold text-red-900">{title}</h2>
      <p className="mt-2 text-red-800">{errorHint(error)}</p>
      <button
        type="button"
        onClick={onRetry}
        className="mt-4 rounded-md bg-red-700 px-4 py-2 text-sm font-medium text-white hover:bg-red-600"
      >
        Retry
      </button>
    </div>
  )
}
