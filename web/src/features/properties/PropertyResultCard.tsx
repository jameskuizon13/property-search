import { memo } from 'react'
import { PropertyCard, type CardSource } from '@/components/ui/PropertyCard'
import { WatchButton } from '@/features/watchlist/WatchButton'
import type { Property } from './types'

/**
 * A card with its watch toggle. Memoised: a toggle or live update replaces
 * only that property's object in the cache, so only that card re-renders.
 */
export const PropertyResultCard = memo(function PropertyResultCard({
  property,
  typeLabel,
  from,
}: {
  property: Property
  typeLabel: string
  from: CardSource
}) {
  return (
    <PropertyCard property={property} typeLabel={typeLabel} from={from} action={<WatchButton property={property} />} />
  )
})
