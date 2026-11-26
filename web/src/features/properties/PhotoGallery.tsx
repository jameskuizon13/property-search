import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent, type ReactNode } from 'react'
import { smallPhoto } from '@/components/ui/photoSources'
import { PropertyPhoto } from '@/components/ui/PropertyCard'
import type { PropertyPhotoItem } from './types'

type Props = {
  photos: PropertyPhotoItem[]
  /** Read out with each photo's caption ("Kitchen, 12 Smith St"). */
  address: string
  /** Drawn over the main photo, e.g. the status badge. */
  overlay?: ReactNode
}

const SWIPE_PX = 40

const arrowButton =
  'absolute top-1/2 flex h-10 w-10 -translate-y-1/2 items-center justify-center rounded-full bg-white/90 text-lg text-slate-900 shadow hover:bg-white focus-visible:outline-2 focus-visible:outline-indigo-600'

/**
 * The property's photos: one large photo with previous/next buttons (and the
 * arrow keys while focus is inside), a "2 / 6" counter, and a row of
 * thumbnails to jump to any photo, plus a sideways swipe on touch screens.
 * Starts on the main photo. The small copy shows behind the large one while
 * it loads (usually cached from the card), so the photo never opens blank.
 */
export function PhotoGallery({ photos, address, overlay }: Props) {
  const [index, setIndex] = useState(0)
  const count = photos.length
  // The list can shrink between loads; never point past the end.
  const current = count ? Math.min(index, count - 1) : 0
  const photo = photos[current]

  const show = (next: number) => setIndex(((next % count) + count) % count)
  // Only our own demo photos have a small copy; any other URL never goes into CSS.
  const backdrop = photo && smallPhoto(photo.url) !== photo.url ? smallPhoto(photo.url) : null

  // Keep the current thumbnail in view when the arrows or a swipe move past
  // the edge of the strip (it scrolls sideways on a phone).
  const stripRef = useRef<HTMLUListElement>(null)
  useEffect(() => {
    stripRef.current?.children[current]?.scrollIntoView?.({ block: 'nearest', inline: 'nearest' })
  }, [current])

  // A swipe: a mostly sideways touch drag of at least SWIPE_PX.
  const swipeStart = useRef<{ x: number; y: number } | null>(null)
  function onPointerDown(event: PointerEvent) {
    swipeStart.current = event.pointerType === 'touch' ? { x: event.clientX, y: event.clientY } : null
  }
  function onPointerUp(event: PointerEvent) {
    const start = swipeStart.current
    swipeStart.current = null
    if (!start || count < 2) return
    const dx = event.clientX - start.x
    if (Math.abs(dx) >= SWIPE_PX && Math.abs(dx) > Math.abs(event.clientY - start.y)) show(current + (dx < 0 ? 1 : -1))
  }

  function onKeyDown(event: KeyboardEvent) {
    if (count < 2) return
    if (event.key === 'ArrowLeft') show(current - 1)
    else if (event.key === 'ArrowRight') show(current + 1)
    else return
    event.preventDefault()
  }

  return (
    <section aria-label="Photos" onKeyDown={onKeyDown} className="space-y-2">
      <div
        onPointerDown={onPointerDown}
        onPointerUp={onPointerUp}
        onPointerCancel={() => (swipeStart.current = null)}
        style={backdrop ? { backgroundImage: `url("${backdrop}")` } : undefined}
        className="relative aspect-[3/2] max-h-[28rem] w-full touch-pan-y overflow-hidden rounded-lg bg-slate-100 bg-cover bg-center [-webkit-tap-highlight-color:transparent]"
      >
        {/* Keyed, so a new <img> mounts per photo: the browser would otherwise keep
            painting the old one until the new one loads, behind the new caption. */}
        <PropertyPhoto
          key={photo?.url}
          src={photo?.url ?? null}
          alt={photo ? `${photo.caption}, ${address}` : ''}
          sizes="(min-width: 1024px) 992px, 100vw"
          priority={current === 0}
        />
        {overlay}
        {count > 1 && (
          <>
            <button type="button" onClick={() => show(current - 1)} className={`${arrowButton} left-3`}>
              <span aria-hidden="true">‹</span>
              <span className="sr-only">Previous photo</span>
            </button>
            <button type="button" onClick={() => show(current + 1)} className={`${arrowButton} right-3`}>
              <span aria-hidden="true">›</span>
              <span className="sr-only">Next photo</span>
            </button>
            <p
              aria-live="polite"
              className="absolute right-3 bottom-3 rounded-full bg-slate-900/75 px-2.5 py-0.5 text-xs font-medium text-white"
            >
              <span className="sr-only">
                Photo {current + 1} of {count}: {photo?.caption}
              </span>
              <span aria-hidden="true">
                {current + 1} / {count}
              </span>
            </p>
          </>
        )}
      </div>

      {count > 1 && (
        <ul ref={stripRef} className="flex gap-2 overflow-x-auto pb-1">
          {photos.map((item, i) => (
            <li key={`${i}-${item.url}`} className="shrink-0">
              <button
                type="button"
                onClick={() => show(i)}
                aria-current={i === current || undefined}
                className="relative block h-14 w-20 overflow-hidden rounded-md opacity-70 ring-indigo-600 hover:opacity-100 focus-visible:outline-2 focus-visible:outline-indigo-600 aria-[current]:opacity-100 aria-[current]:ring-2 sm:h-16 sm:w-24"
              >
                <img src={smallPhoto(item.url)} alt="" loading="lazy" decoding="async" className="h-full w-full object-cover" />
                <span className="sr-only">
                  Show photo {i + 1}: {item.caption}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
