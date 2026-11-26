import { Link, useRouter } from '@tanstack/react-router'
import type { ReactNode } from 'react'
import { rememberReturnFocus } from './returnFocus'
import { featureParts, statusLabels } from '@/features/properties/format'
import type { Property, PropertyStatus } from '@/features/properties/types'

const statusBadgeClasses: Record<PropertyStatus, string> = {
  for_sale: 'bg-emerald-100 text-emerald-800',
  under_offer: 'bg-amber-100 text-amber-800',
  sold: 'bg-slate-800 text-white',
  withdrawn: 'bg-slate-200 text-slate-700',
}

type BadgeProps = {
  status: PropertyStatus
  /** Positioning only; the size comes from `size` (two font-size classes would fight). */
  className?: string
  size?: 'sm' | 'md'
}

export function StatusBadge({ status, className = '', size = 'sm' }: BadgeProps) {
  const sizeClasses = size === 'md' ? 'px-3 py-1 text-sm' : 'px-2.5 py-0.5 text-xs'
  return (
    <span className={`rounded-full font-semibold ${sizeClasses} ${statusBadgeClasses[status]} ${className}`}>
      {statusLabels[status]}
    </span>
  )
}

/** The bundled demo photos come in two widths: `house-01.webp` (960 px) and `house-01-480.webp`. */
const DEMO_PHOTO = /^(\/images\/properties\/[a-z]+-\d+)\.webp$/

function srcSetFor(src: string) {
  const base = DEMO_PHOTO.exec(src)?.[1]
  return base && `${base}-480.webp 480w, ${src} 960w`
}

type PhotoProps = {
  src: string | null
  alt: string
  /** How wide the photo shows, so the browser picks the smaller file when it can. */
  sizes: string
  /** The property page's main photo: load it first, not lazily. */
  priority?: boolean
}

/** The photo, or a plain panel when a listing has none. */
export function PropertyPhoto({ src, alt, sizes, priority = false }: PhotoProps) {
  return src ? (
    <img
      src={src}
      srcSet={srcSetFor(src)}
      sizes={sizes}
      alt={alt}
      loading={priority ? 'eager' : 'lazy'}
      fetchPriority={priority ? 'high' : 'auto'}
      decoding="async"
      className="h-full w-full object-cover"
    />
  ) : (
    <div className="flex h-full items-center justify-center text-sm text-slate-400">No photo</div>
  )
}

/** Which list a card was opened from; the property page's back link says so. */
export type CardSource = 'search' | 'watchlist'

type Props = {
  property: Property
  typeLabel: string
  from: CardSource
  /** Rendered in the card's footer, e.g. the watch toggle. */
  action?: ReactNode
}

/**
 * The whole card opens the property page: the address is the link, and its
 * ::after covers the card (a "stretched link"), so there is one link per card
 * for screen readers and keyboards, named by the address. The action sits
 * above it (relative z-10), so Watch still toggles instead of navigating.
 */
export function PropertyCard({ property, typeLabel, from, action }: Props) {
  const headingId = `property-${property.id}-address`
  const router = useRouter()

  return (
    <article
      aria-labelledby={headingId}
      className="group relative flex h-full flex-col overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm transition-[box-shadow,border-color] duration-200 hover:border-slate-300 hover:shadow-lg has-[a:focus-visible]:ring-2 has-[a:focus-visible]:ring-indigo-500"
    >
      <div className="relative aspect-[3/2] overflow-hidden bg-slate-100">
        {/* The whole card reacts to hover, never the address alone: an underlined address reads as a map link. */}
        <div className="h-full transition-transform duration-300 ease-out motion-safe:group-hover:scale-[1.03]">
          {/* One, two or three columns (see InfiniteResults); max-w-6xl caps a column near 370 px. */}
          <PropertyPhoto
            src={property.imageUrl}
            alt=""
            sizes="(min-width: 1024px) 370px, (min-width: 640px) 50vw, 100vw"
          />
        </div>
        <StatusBadge status={property.status} className="absolute top-3 left-3" />
      </div>
      <div className="flex flex-1 flex-col gap-1 p-4">
        <p className="text-lg font-semibold">{property.priceDisplay}</p>
        <h3 id={headingId} className="font-medium text-slate-900">
          <Link
            to="/properties/$propertyId"
            params={{ propertyId: String(property.id) }}
            state={{ from }}
            onClick={(event) => {
              // A modified click opens a new tab; this tab stays on the list.
              if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return
              rememberReturnFocus(`/properties/${property.id}`, router.state.location.state.__TSR_key)
            }}
            className="after:absolute after:inset-0 after:content-[''] focus:outline-none"
          >
            {property.streetAddress}
          </Link>
        </h3>
        <p className="text-sm text-slate-600">
          {property.suburb} {property.state} {property.postcode}
        </p>
        <p className="mt-2 text-sm text-slate-700">{featureParts(property).join(' · ')}</p>
        <div className="mt-auto flex items-center justify-between gap-2 pt-3">
          <span className="text-xs font-medium tracking-wide text-slate-500 uppercase">{typeLabel}</span>
          {action && <div className="relative z-10">{action}</div>}
        </div>
      </div>
    </article>
  )
}
