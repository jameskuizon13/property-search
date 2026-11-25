import { useAtomValue, useSetAtom } from 'jotai'
import { useEffect, useState } from 'react'
import { dismissToastAtom, toastsAtom, type Toast } from './toast'

export const TOAST_DURATION_MS = 5000
/** Errors may need acting on (e.g. a wrong password), so they stay longer. */
export const ERROR_TOAST_DURATION_MS = 10_000

const toneClasses: Record<Toast['tone'], string> = {
  success: 'border-emerald-200 bg-emerald-50 text-emerald-900',
  error: 'border-red-200 bg-red-50 text-red-900',
  info: 'border-slate-200 bg-white text-slate-900',
}

function ToastItem({ toast }: { toast: Toast }) {
  const dismiss = useSetAtom(dismissToastAtom)
  // Hovering or focusing a toast pauses it (WCAG 2.2.1); leaving restarts the
  // full time. Tracked apart, so the pointer leaving doesn't close a focused toast.
  const [hovered, setHovered] = useState(false)
  const [focused, setFocused] = useState(false)
  const paused = hovered || focused
  const duration = toast.tone === 'error' ? ERROR_TOAST_DURATION_MS : TOAST_DURATION_MS

  useEffect(() => {
    if (paused) return
    const timer = setTimeout(() => dismiss(toast.id), duration)
    return () => clearTimeout(timer)
  }, [toast.id, dismiss, duration, paused])

  return (
    <li
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onFocus={() => setFocused(true)}
      onBlur={() => setFocused(false)}
      className={`pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-lg border px-4 py-3 text-sm shadow-lg ${toneClasses[toast.tone]}`}
    >
      <p className="flex-1">{toast.message}</p>
      <button
        type="button"
        onClick={() => dismiss(toast.id)}
        aria-label="Dismiss notification"
        className="-m-1 rounded p-1 leading-none opacity-60 hover:opacity-100"
      >
        ×
      </button>
    </li>
  )
}

/**
 * The live region is always in the DOM, so screen readers announce toasts
 * added to it (a region inserted together with its text is often missed).
 */
export function Toaster() {
  const toasts = useAtomValue(toastsAtom)
  return (
    <ol
      aria-label="Notifications"
      aria-live="polite"
      className="pointer-events-none fixed inset-x-4 top-16 z-50 flex flex-col items-center gap-2 sm:left-auto sm:items-end"
    >
      {toasts.map((toast) => (
        <ToastItem key={toast.id} toast={toast} />
      ))}
    </ol>
  )
}
