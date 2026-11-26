import type { Property, PropertyStatus, PropertyUpdatedMessage } from './types'

export function plural(count: number, word: string) {
  return `${count} ${word}${count === 1 ? '' : 's'}`
}

/** Types where no bedroom means no home on it (vacant land), not a studio. */
const LAND_TYPES = new Set(['land', 'acreage', 'rural'])

/** Land, or an acreage or rural listing with no rooms at all: there's no home to describe. */
export function isLandOnly(property: Pick<Property, 'propertyType' | 'bedrooms' | 'bathrooms'>) {
  return (
    property.propertyType === 'land' ||
    (LAND_TYPES.has(property.propertyType) && property.bedrooms === 0 && property.bathrooms === 0)
  )
}

/**
 * ["3 beds", "2 baths", "1 car", "450 m²"], the way listing sites write it: a
 * zero count is left out rather than shown ("0 baths"), a home with no
 * bedroom is a "Studio", and land (see isLandOnly) shows only its size.
 */
export function featureParts(
  property: Pick<Property, 'propertyType' | 'bedrooms' | 'bathrooms' | 'carSpaces' | 'landSizeSqm'>,
) {
  const isLand = isLandOnly(property)
  return [
    property.bedrooms > 0 ? plural(property.bedrooms, 'bed') : !isLand && 'Studio',
    property.bathrooms > 0 && plural(property.bathrooms, 'bath'),
    property.carSpaces > 0 && plural(property.carSpaces, 'car'),
    property.landSizeSqm != null && `${property.landSizeSqm.toLocaleString('en-AU')} m²`,
  ].filter((part): part is string => !!part)
}

/** The viewer's own time zone, e.g. "Australia/Sydney". */
const viewerTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone

/**
 * An open home in the listing's local time: { day: "Sat 29 Nov", time:
 * "10:00 am – 10:30 am" }. When the viewer is in another zone it adds the
 * zone and the start in the viewer's own time ("10:00 am – 10:30 am AWST
 * (1:00 pm your time)"), so a Perth open home never reads as Sydney time and
 * nobody has to know what AWST means.
 */
export function formatOpenHome(
  { startsAt, endsAt }: { startsAt: string; endsAt: string },
  timeZone: string,
  viewerZone = viewerTimeZone(),
) {
  const start = new Date(startsAt)
  const day = new Intl.DateTimeFormat('en-AU', { weekday: 'short', day: 'numeric', month: 'short', timeZone })
    .format(start)
    .replace(',', '')
  const clock = new Intl.DateTimeFormat('en-AU', { hour: 'numeric', minute: '2-digit', timeZone })
  let time = `${clock.format(start)} – ${clock.format(new Date(endsAt))}`
  if (viewerZone !== timeZone) {
    const zone = new Intl.DateTimeFormat('en-AU', { timeZone, timeZoneName: 'short' })
      .formatToParts(start)
      .find((part) => part.type === 'timeZoneName')?.value
    if (zone) time += ` ${zone}`
    // The viewer's day too when it isn't the same date there (an overseas buyer).
    const viewerDay = new Intl.DateTimeFormat('en-AU', { weekday: 'short', day: 'numeric', month: 'short', timeZone: viewerZone })
      .format(start)
      .replace(',', '')
    const yourClock = new Intl.DateTimeFormat('en-AU', { hour: 'numeric', minute: '2-digit', timeZone: viewerZone }).format(
      start,
    )
    const yours = viewerDay === day ? yourClock : `${viewerDay.split(' ')[0]} ${yourClock}`
    if (yours !== clock.format(start)) time += ` (${yours} your time)`
  }
  return { day, time }
}

/** "12 Nov 2026". */
export function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' })
}

/** 500000 → "$500k", 1250000 → "$1.25M". */
export function formatPriceStep(value: number) {
  if (value >= 1_000_000) return `$${Number((value / 1_000_000).toFixed(2))}M`
  if (value >= 1_000) return `$${Number((value / 1_000).toFixed(1))}k`
  return `$${value}`
}

/** What "Under offer" means, for the ⓘ next to it on the property page and the search filters. */
export const UNDER_OFFER_EXPLAINED =
  "The seller has accepted an offer, but the sale isn't final yet. It may come back on the market if the deal falls through."

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

/** 85_000_000 cents → "$850,000". */
export const fullPrice = (cents: number) => `$${Math.round(cents / 100).toLocaleString('en-AU')}`

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
