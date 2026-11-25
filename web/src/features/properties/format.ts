import type { PropertyStatus, PropertyUpdatedMessage } from './types'

/** 500000 → "$500k", 1250000 → "$1.25M". */
export function formatPriceStep(value: number) {
  if (value >= 1_000_000) return `$${Number((value / 1_000_000).toFixed(2))}M`
  if (value >= 1_000) return `$${Number((value / 1_000).toFixed(1))}k`
  return `$${value}`
}

export const statusLabels: Record<PropertyStatus, string> = {
  for_sale: 'For sale',
  under_offer: 'Under offer',
  sold: 'Sold',
  withdrawn: 'Withdrawn',
}

/** 85_000_000 cents → "$850k", 125_000_000 → "$1.25M" (999,999 rounds to "$1M", not "$1000k"). */
export function formatCompactPrice(cents: number) {
  const dollars = Math.round(cents / 100)
  if (dollars >= 999_500) return `$${Number((dollars / 1_000_000).toFixed(2))}M`
  if (dollars >= 1_000) return `$${Number((dollars / 1_000).toFixed(1))}k`
  return `$${dollars}`
}

const fullPrice = (cents: number) => `$${Math.round(cents / 100).toLocaleString('en-AU')}`

/**
 * "$850k → $820k"; full amounts when the short forms would read the same
 * ("$2,005,000 → $2,000,000"). A withheld new price shows the card's own text
 * ("Contact agent", "Auction"); a withheld old one, "price withheld".
 */
function describePriceChange([from, to]: [number | null, number | null], newDisplay: string) {
  let fromText = from === null ? 'price withheld' : formatCompactPrice(from)
  let toText = to === null ? newDisplay : formatCompactPrice(to)
  if (from !== null && to !== null && fromText === toText) {
    fromText = fullPrice(from)
    toText = fullPrice(to)
  }
  return `${fromText} → ${toText}`
}

/** The live-update toast: "12 Smith St: $850k → $820k", "12 Smith St: For sale → Sold", or both. */
export function describeChanges({ property, changes }: Pick<PropertyUpdatedMessage, 'property' | 'changes'>) {
  const parts: string[] = []
  if (changes.priceCents) parts.push(describePriceChange(changes.priceCents, property.priceDisplay))
  if (changes.status) {
    const [from, to] = changes.status
    parts.push(`${statusLabels[from] ?? from} → ${statusLabels[to] ?? to}`)
  }
  return parts.length ? `${property.streetAddress}: ${parts.join(', ')}` : `${property.streetAddress} was updated`
}
