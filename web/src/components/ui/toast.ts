import { atom, useSetAtom } from 'jotai'
import { useCallback } from 'react'

export type ToastTone = 'success' | 'error' | 'info'
export type Toast = { id: number; message: string; tone: ToastTone }

/** At most this many toasts show at once; older ones drop off. */
const MAX_TOASTS = 3

let nextId = 1

export const toastsAtom = atom<Toast[]>([])

export const pushToastAtom = atom(null, (get, set, toast: Omit<Toast, 'id'>) => {
  set(toastsAtom, [...get(toastsAtom), { ...toast, id: nextId++ }].slice(-MAX_TOASTS))
})

export const dismissToastAtom = atom(null, (get, set, id: number) => {
  set(toastsAtom, get(toastsAtom).filter((toast) => toast.id !== id))
})

/** `toast('Signed in', 'success')`. Writing only, so callers never re-render when toasts change. */
export function useToast() {
  const push = useSetAtom(pushToastAtom)
  return useCallback((message: string, tone: ToastTone = 'info') => push({ message, tone }), [push])
}
