import { useCallback } from 'react'
import type { CardSource } from '@/components/ui/PropertyCard'
import { fallbackLabel, usePropertyTypeLabels } from './hooks'
import { PropertyResultCard } from './PropertyResultCard'
import type { Property } from './types'

/** `renderItem` for InfiniteResults, shared by search and the watchlist. */
export function useRenderProperty(from: CardSource) {
  const labels = usePropertyTypeLabels()
  return useCallback(
    (property: Property) => (
      <PropertyResultCard
        property={property}
        typeLabel={labels?.[property.propertyType] ?? fallbackLabel(property.propertyType)}
        from={from}
      />
    ),
    [labels, from],
  )
}
