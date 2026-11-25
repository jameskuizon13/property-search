import { Link, useCanGoBack, useLocation, useParams, useRouter } from '@tanstack/react-router'
import { useEffect } from 'react'
import { PropertyPhoto, StatusBadge } from '@/components/ui/PropertyCard'
import { EmptyState, ErrorState } from '@/components/ui/states'
import { WatchButton } from '@/features/watchlist/WatchButton'
import { ApiError } from '@/lib/api'
import { featureParts, formatDate, fullPrice, isLandOnly, statusLabels } from './format'
import { fallbackLabel, useProperty, usePropertyTypeLabels } from './hooks'
import type { PropertyDetail, PropertyEvent } from './types'

/** Ids the API can hold and JavaScript can count exactly. Anything else is "not found" without a request. */
const PROPERTY_ID = /^[1-9]\d{0,14}$/

/** index.html's <title>, put back when the page closes. */
const APP_NAME = 'Property Search'

/** "Price dropped from $850,000 to $820,000", "Now under offer (was for sale)". */
function describeEvent(event: PropertyEvent) {
  if (event.kind === 'status_changed') {
    return `${statusLabels[event.to] ?? event.to} (was ${(statusLabels[event.from] ?? event.from).toLowerCase()})`
  }
  const { from, to } = event
  // Both null: the amounts are hidden while the price is withheld.
  if (from === null && to === null) return 'Price updated'
  if (to === null) return `Price withheld (was ${fullPrice(from!)})`
  if (from === null) return `Price set at ${fullPrice(to)}`
  if (to < from) return `Price dropped from ${fullPrice(from)} to ${fullPrice(to)}`
  return `Price raised from ${fullPrice(from)} to ${fullPrice(to)}`
}

function mapsUrl({ latitude, longitude, streetAddress, suburb, state, postcode }: PropertyDetail) {
  const query =
    latitude != null && longitude != null ? `${latitude},${longitude}` : `${streetAddress}, ${suburb} ${state} ${postcode}`
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`
}

const BACK_LABELS = { search: 'Back to results', watchlist: 'Back to watchlist' } as const

/**
 * Back to the list the card was opened from, as browser history so the
 * filters and scroll come back; a link to search otherwise (arrived from a
 * shared link, or via the login page). Decided by the card link's history
 * state, not by whether there is history to go back to: after a login round
 * trip, "back" would only reach the login page.
 */
function BackLink() {
  const router = useRouter()
  const canGoBack = useCanGoBack()
  const from = useLocation({ select: (location) => location.state.from })
  const className = 'inline-flex items-center gap-1 text-sm font-medium text-indigo-700 hover:underline'
  if (from && canGoBack) {
    return (
      <button type="button" onClick={() => router.history.back()} className={className}>
        <span aria-hidden="true">←</span> {BACK_LABELS[from]}
      </button>
    )
  }
  return (
    <Link to="/search" className={className}>
      <span aria-hidden="true">←</span> Search properties
    </Link>
  )
}

function Loading() {
  return (
    <div aria-hidden="true" className="animate-pulse space-y-4">
      <div className="aspect-[3/2] max-h-[28rem] w-full rounded-lg bg-slate-200" />
      <div className="h-8 w-1/3 rounded bg-slate-200" />
      <div className="h-5 w-1/2 rounded bg-slate-200" />
    </div>
  )
}

function NotFound() {
  useEffect(() => {
    document.title = `Property not found | ${APP_NAME}`
    return () => {
      document.title = APP_NAME
    }
  }, [])
  return (
    <EmptyState title="We couldn't find this property" headingLevel={1}>
      <p>It may have been removed, or the link may be wrong.</p>
      <Link to="/search" className="inline-block font-medium text-indigo-700 hover:underline">
        Search properties
      </Link>
    </EmptyState>
  )
}

function History({ property, loading }: { property: PropertyDetail; loading: boolean }) {
  if (loading) return <p className="text-sm text-slate-500">Loading history…</p>
  return (
    <ol className="space-y-3">
      {property.history.map((event) => (
        <li key={event.id} className="flex flex-wrap justify-between gap-x-4 text-sm">
          <span className="text-slate-800">{describeEvent(event)}</span>
          <time dateTime={event.createdAt} className="text-slate-500">
            {formatDate(event.createdAt)}
          </time>
        </li>
      ))}
      <li className="flex flex-wrap justify-between gap-x-4 text-sm">
        <span className="text-slate-800">Listed for sale</span>
        <time dateTime={property.listedAt} className="text-slate-500">
          {formatDate(property.listedAt)}
        </time>
      </li>
      {!property.historyComplete && <li className="text-sm text-slate-500">Earlier changes aren't shown.</li>}
    </ol>
  )
}

function Details({ property, loading }: { property: PropertyDetail; loading: boolean }) {
  const labels = usePropertyTypeLabels()
  const typeLabel = labels?.[property.propertyType] ?? fallbackLabel(property.propertyType)
  const location = `${property.suburb} ${property.state} ${property.postcode}`
  // Land has no rooms to list, so no "Bedrooms 0".
  const rooms = isLandOnly(property)
    ? []
    : [
        { label: 'Bedrooms', value: property.bedrooms },
        { label: 'Bathrooms', value: property.bathrooms },
        { label: 'Car spaces', value: property.carSpaces },
      ]
  const facts = [
    ...rooms,
    property.landSizeSqm != null && { label: 'Land size', value: `${property.landSizeSqm.toLocaleString('en-AU')} m²` },
    { label: 'Property type', value: typeLabel },
  ].filter((fact) => !!fact)

  // Start screen readers at the address when the details first show (on
  // arrival, and again after a Retry), not when a refetch updates them.
  useEffect(() => {
    document.getElementById('property-address')?.focus({ preventScroll: true })
  }, [])

  return (
    <article aria-labelledby="property-address" className="space-y-8">
      <div className="relative aspect-[3/2] max-h-[28rem] w-full overflow-hidden rounded-lg bg-slate-100">
        <PropertyPhoto
          src={property.imageUrl}
          alt={`Photo of ${property.streetAddress}`}
          sizes="(min-width: 1024px) 992px, 100vw"
          priority
        />
        <StatusBadge status={property.status} size="md" className="absolute top-4 left-4" />
      </div>

      <header className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0 space-y-1 break-words">
          <p className="text-3xl font-semibold">{property.priceDisplay}</p>
          {/* The page's one h1, focused when the details show (see above). */}
          <h1 id="property-address" tabIndex={-1} className="text-xl font-medium text-slate-900 focus:outline-none">
            {property.streetAddress}
          </h1>
          <p className="text-slate-600">{location}</p>
          <p className="pt-1 text-slate-700">{featureParts(property).join(' · ')}</p>
        </div>
        <div className="shrink-0">
          <WatchButton property={property} />
        </div>
      </header>

      <div className="grid gap-8 lg:grid-cols-[2fr_1fr]">
        {/* min-w-0 and break-words: a long URL pasted into a description wraps instead of widening the page. */}
        <div className="min-w-0 space-y-8 break-words">
          <section aria-labelledby="about-heading" className="space-y-3">
            <h2 id="about-heading" className="text-lg font-semibold">
              About this property
            </h2>
            {loading ? (
              <p className="text-sm text-slate-500">Loading description…</p>
            ) : property.description ? (
              <p className="whitespace-pre-line text-slate-700">{property.description}</p>
            ) : (
              <p className="text-slate-500">The agent hasn't added a description yet.</p>
            )}
          </section>

          <section aria-labelledby="history-heading" className="space-y-3">
            <h2 id="history-heading" className="text-lg font-semibold">
              Price and status history
            </h2>
            <History property={property} loading={loading} />
          </section>
        </div>

        <aside className="min-w-0 space-y-6 break-words">
          <section aria-labelledby="facts-heading" className="rounded-lg border border-slate-200 bg-white p-4">
            <h2 id="facts-heading" className="mb-3 font-semibold">
              Property details
            </h2>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              {facts.map(({ label, value }) => (
                <div key={label} className="contents">
                  <dt className="text-slate-500">{label}</dt>
                  <dd className="text-right font-medium text-slate-900">{value}</dd>
                </div>
              ))}
              <dt className="text-slate-500">Listed</dt>
              <dd className="text-right font-medium text-slate-900">{formatDate(property.listedAt)}</dd>
            </dl>
          </section>

          <section aria-labelledby="location-heading" className="rounded-lg border border-slate-200 bg-white p-4">
            <h2 id="location-heading" className="mb-2 font-semibold">
              Location
            </h2>
            <p className="text-sm text-slate-700">
              {property.streetAddress}, {location}
            </p>
            <a
              href={mapsUrl(property)}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-2 inline-block text-sm font-medium text-indigo-700 hover:underline"
            >
              Open in Google Maps<span className="sr-only"> (opens in a new tab)</span>
            </a>
          </section>
        </aside>
      </div>
    </article>
  )
}

export function PropertyPage() {
  const { propertyId } = useParams({ from: '/properties/$propertyId' })
  const validId = PROPERTY_ID.test(propertyId)
  const id = validId ? Number(propertyId) : 0
  const query = useProperty(id, { enabled: validId })
  const property = query.data
  const notFound = !validId || (query.error instanceof ApiError && query.error.status === 404)

  // Name the tab after the property.
  const title = property && `${property.streetAddress}, ${property.suburb} | ${APP_NAME}`
  useEffect(() => {
    if (!title) return
    document.title = title
    return () => {
      document.title = APP_NAME
    }
  }, [title])

  return (
    <main className="mx-auto max-w-5xl space-y-6 px-4 py-8">
      {/* "Not found" has its own way back. */}
      {!notFound && <BackLink />}
      {notFound ? (
        <NotFound />
      ) : property ? (
        <Details property={property} loading={query.isPlaceholderData} />
      ) : query.isError ? (
        <ErrorState title="We couldn't load this property" error={query.error} onRetry={() => void query.refetch()} />
      ) : (
        <>
          <p role="status" className="sr-only">
            Loading property
          </p>
          <Loading />
        </>
      )}
    </main>
  )
}
