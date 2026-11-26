import { useEffect, useId, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'

type Props = {
  /** The button's accessible name, as a question: "What does under offer mean?" */
  label: string
  /** One short line of explanation. */
  children: ReactNode
}

const BUBBLE_WIDTH = 256
/** Space kept between the bubble and the screen's edge. */
const EDGE = 16

/**
 * A small ⓘ button that shows a short explanation on click or tap (a
 * "toggletip"), and hides it again on a second press, Escape, a click
 * elsewhere, focus moving away (tapping the bubble's own text counts), a
 * scroll or a resize. Not a hover tooltip: phones and keyboards can't hover.
 * The text goes into a live region when it opens, so screen readers read it
 * out without moving focus off the button.
 *
 * The bubble is `position: fixed`, placed under the button and kept inside
 * the screen, so it never widens the page on a phone.
 */
export function Toggletip({ label, children }: Props) {
  const [open, setOpen] = useState(false)
  const [position, setPosition] = useState<CSSProperties>()
  const id = useId()
  const rootRef = useRef<HTMLSpanElement>(null)
  const buttonRef = useRef<HTMLButtonElement>(null)

  useLayoutEffect(() => {
    if (!open || !buttonRef.current) return
    const rect = buttonRef.current.getBoundingClientRect()
    const width = Math.min(BUBBLE_WIDTH, window.innerWidth - 2 * EDGE)
    const left = Math.min(Math.max(rect.left, EDGE), window.innerWidth - EDGE - width)
    setPosition({ top: rect.bottom + 4, left, width })
  }, [open])

  useEffect(() => {
    if (!open) return
    const close = () => setOpen(false)
    const closeOutside = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) close()
    }
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close()
    }
    document.addEventListener('pointerdown', closeOutside)
    document.addEventListener('keydown', closeOnEscape)
    // A fixed bubble would drift away from its button on scroll, or be left
    // off-screen after a resize or rotation.
    window.addEventListener('scroll', close, { passive: true })
    window.addEventListener('resize', close)
    return () => {
      document.removeEventListener('pointerdown', closeOutside)
      document.removeEventListener('keydown', closeOnEscape)
      window.removeEventListener('scroll', close)
      window.removeEventListener('resize', close)
    }
  }, [open])

  return (
    <span
      ref={rootRef}
      onBlur={(event) => {
        if (!rootRef.current?.contains(event.relatedTarget as Node | null)) setOpen(false)
      }}
      className="relative inline-flex align-middle"
    >
      <button
        ref={buttonRef}
        type="button"
        aria-label={label}
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen((wasOpen) => !wasOpen)}
        className="inline-flex h-6 w-6 items-center justify-center rounded-full text-base leading-none text-slate-500 hover:text-indigo-700 focus-visible:outline-2 focus-visible:outline-indigo-600 aria-expanded:text-indigo-700"
      >
        <span aria-hidden="true">ⓘ</span>
      </button>
      <span id={id} role="status">
        {open && (
          <span
            style={position}
            className="fixed z-50 block rounded-md bg-slate-900 px-3 py-2 text-left text-xs leading-snug font-normal text-white shadow-lg"
          >
            {children}
          </span>
        )}
      </span>
    </span>
  )
}
