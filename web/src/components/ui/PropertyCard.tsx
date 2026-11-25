import type { ReactNode } from 'react'
import { statusLabels } from '@/features/properties/format'
import type { Property, PropertyStatus } from '@/features/properties/types'

const statusBadgeClasses: Record<PropertyStatus, string> = {
  for_sale: 'bg-emerald-100 text-emerald-800',
  under_offer: 'bg-amber-100 text-amber-800',
  sold: 'bg-slate-800 text-white',
  withdrawn: 'bg-slate-200 text-slate-700',
}

function plural(count: number, word: string) {
  return `${count} ${word}${count === 1 ? '' : 's'}`
}

type Props = {
  property: Property
  typeLabel: string
  /** Rendered in the card's footer, e.g. the watch toggle. */
  action?: ReactNode
}

export function PropertyCard({ property, typeLabel, action }: Props) {
  const badge = { label: statusLabels[property.status], className: statusBadgeClasses[property.status] }
  const headingId = `property-${property.id}-address`
  const features = [
    plural(property.bedrooms, 'bed'),
    plural(property.bathrooms, 'bath'),
    plural(property.carSpaces, 'car'),
    property.landSizeSqm != null && `${property.landSizeSqm.toLocaleString('en-AU')} m²`,
  ].filter(Boolean)

  return (
    <article
      aria-labelledby={headingId}
      className="flex h-full flex-col overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm"
    >
      <div className="relative aspect-[3/2] bg-slate-100">
        {property.imageUrl ? (
          <img src={property.imageUrl} alt="" loading="lazy" className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full items-center justify-center text-sm text-slate-400">No photo</div>
        )}
        <span className={`absolute top-3 left-3 rounded-full px-2.5 py-0.5 text-xs font-semibold ${badge.className}`}>
          {badge.label}
        </span>
      </div>
      <div className="flex flex-1 flex-col gap-1 p-4">
        <p className="text-lg font-semibold">{property.priceDisplay}</p>
        <h3 id={headingId} className="font-medium text-slate-900">
          {property.streetAddress}
        </h3>
        <p className="text-sm text-slate-600">
          {property.suburb} {property.state} {property.postcode}
        </p>
        <p className="mt-2 text-sm text-slate-700">{features.join(' · ')}</p>
        <div className="mt-auto flex items-center justify-between gap-2 pt-3">
          <span className="text-xs font-medium tracking-wide text-slate-500 uppercase">{typeLabel}</span>
          {action}
        </div>
      </div>
    </article>
  )
}
