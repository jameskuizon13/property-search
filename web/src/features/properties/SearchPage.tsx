import { useNavigate, useSearch } from '@tanstack/react-router'
import { useCallback, useMemo, useRef } from 'react'
import { InfiniteResults } from '@/components/ui/InfiniteResults'
import { EmptyState } from '@/components/ui/states'
import { FilterBar } from './FilterBar'
import { useSearchProperties } from './hooks'
import { cleanFilters, isPriceSort, toApiFilters, type FilterPatch, type SearchFilters } from './searchSchema'
import { useRenderProperty } from './useRenderProperty'

/** Which filters to loosen, for the empty state. Takes the filters actually sent. */
function loosenHints(filters: SearchFilters) {
  const hints: string[] = []
  if (filters.q) hints.push('a different suburb, street or postcode')
  if (filters.minPrice != null || filters.maxPrice != null) hints.push('a wider price range')
  if (filters.minBedrooms) hints.push('fewer bedrooms')
  if (filters.propertyTypes) hints.push('more property types')
  if (filters.excludeUnderOffer) hints.push('including properties under offer')
  if (filters.excludePriceWithheld) hints.push('including listings without a price')
  else if (isPriceSort(filters)) hints.push('sorting by newest, which includes listings without a price')
  return hints
}

export function SearchPage() {
  // cleanFilters keeps only known filters: the router also passes through
  // unknown URL keys (e.g. utm_source), which must not count as a filter or
  // split the cache.
  const search = useSearch({ from: '/search' })
  const filters = useMemo(() => cleanFilters(search), [search])
  const navigate = useNavigate({ from: '/search' })
  const headingRef = useRef<HTMLHeadingElement>(null)
  const apiFilters = useMemo(() => toApiFilters(filters), [filters])
  const query = useSearchProperties(apiFilters)
  const renderItem = useRenderProperty()

  const updateFilters = useCallback(
    (patch: FilterPatch, { replace = false } = {}) =>
      void navigate({ search: (prev) => cleanFilters({ ...prev, ...patch }), replace }),
    [navigate],
  )

  const hints = loosenHints(apiFilters)

  return (
    <main className="mx-auto max-w-6xl space-y-6 px-4 py-8">
      <h1 ref={headingRef} tabIndex={-1} className="text-2xl font-semibold focus:outline-none">
        Search properties
      </h1>
      <FilterBar filters={filters} onChange={updateFilters} />
      {isPriceSort(filters) && (
        <p className="text-sm text-slate-600">Price sorts leave out listings without a price (“Contact agent”).</p>
      )}
      <InfiniteResults
        query={query}
        renderItem={renderItem}
        label="Search results"
        topRef={headingRef}
        errorTitle="We couldn't load properties"
        empty={
          <EmptyState title="No properties match your search">
            {hints.length > 0 ? (
              <p>Try {hints.join(', or ')}.</p>
            ) : (
              <p>There are no active listings right now. Check back soon.</p>
            )}
          </EmptyState>
        }
      />
    </main>
  )
}
