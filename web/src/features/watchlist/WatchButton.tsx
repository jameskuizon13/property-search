import { useRouter } from '@tanstack/react-router'
import { useMe } from '@/features/auth/useMe'
import type { Property } from '@/features/properties/types'
import { useToggleWatch } from './useToggleWatch'

type Props = { property: Pick<Property, 'id' | 'streetAddress' | 'watched'> }

/** No toast on success: the button changing is the feedback. */
export function WatchButton({ property }: Props) {
  const { data: user } = useMe()
  const router = useRouter()
  const { mutate } = useToggleWatch(property.id)
  const { watched } = property

  function handleClick() {
    // undefined: /me hasn't answered yet, so we don't know. Ignore the click
    // rather than send a signed-in user to the login page.
    if (user === undefined) return
    if (user === null) {
      void router.navigate({ to: '/login', search: { next: router.state.location.href } })
      return
    }
    mutate(!watched)
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      aria-pressed={watched}
      className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-sm font-medium transition-colors ${
        watched
          ? 'border-indigo-600 bg-indigo-600 text-white hover:bg-indigo-500'
          : 'border-slate-300 bg-white text-slate-700 hover:border-indigo-400 hover:text-indigo-700'
      }`}
    >
      <span aria-hidden="true">{watched ? '★' : '☆'}</span>
      {/* The accessible name starts with the visible text (WCAG 2.5.3), and
          the address says which card when read out of context. */}
      {watched ? 'Watching' : 'Watch'} <span className="sr-only">{property.streetAddress}</span>
    </button>
  )
}
