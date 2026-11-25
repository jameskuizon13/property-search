import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { formatPriceStep } from './format'
import { usePropertyTypes } from './hooks'
import { BEDROOM_OPTIONS, PRICE_STEPS, type FilterPatch, type SearchFilters, type Sort } from './searchSchema'

export const TEXT_DEBOUNCE_MS = 300

type Props = {
  filters: SearchFilters
  /** Writes the patch to the URL. `replace` keeps typing from adding a history entry per word. */
  onChange: (patch: FilterPatch, options?: { replace?: boolean }) => void
}

const fieldClass =
  'block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 focus:outline-none'
const labelClass = 'mb-1 block text-sm font-medium text-slate-700'

const SORT_LABELS: Record<Sort, string> = {
  newest: 'Newest',
  price_asc: 'Price (low to high)',
  price_desc: 'Price (high to low)',
}

/** The fixed steps, plus a value from a hand-edited URL so the select can show it. */
function priceOptions(current: number | undefined) {
  return current == null || PRICE_STEPS.includes(current)
    ? PRICE_STEPS
    : [...PRICE_STEPS, current].sort((a, b) => a - b)
}

const toNumber = (value: string) => (value === '' ? undefined : Number(value))

function SearchText({ value, onChange }: { value: string | undefined; onChange: Props['onChange'] }) {
  const [text, setText] = useState(value ?? '')
  // The last value written to (or read from) the URL, so the URL changing
  // under us (back button, "Clear filters") updates the box, and our own
  // writes don't echo back over what the user is still typing.
  const committed = useRef(value ?? '')

  useEffect(() => {
    const fromUrl = value ?? ''
    if (fromUrl === committed.current) return
    committed.current = fromUrl
    setText(fromUrl)
  }, [value])

  useEffect(() => {
    const timer = setTimeout(() => {
      const next = text.trim()
      if (next === committed.current) return
      committed.current = next
      onChange({ q: next || undefined }, { replace: true })
    }, TEXT_DEBOUNCE_MS)
    return () => clearTimeout(timer)
  }, [text, onChange])

  function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const next = text.trim()
    if (next === committed.current) return
    committed.current = next
    onChange({ q: next || undefined })
  }

  return (
    <form role="search" onSubmit={handleSubmit}>
      <label htmlFor="search-q" className={labelClass}>
        Suburb, street or postcode
      </label>
      <input
        id="search-q"
        type="search"
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="e.g. Fitzroy, Smith St or 3065"
        maxLength={100}
        autoComplete="off"
        className={fieldClass}
      />
    </form>
  )
}

export function FilterBar({ filters, onChange }: Props) {
  const id = useId()
  const { data: propertyTypes } = usePropertyTypes()
  const selectedTypes = filters.propertyTypes ?? []
  const hasFilters = Object.entries(filters).some(([key, value]) => key !== 'sort' && value !== undefined)

  function toggleType(value: (typeof selectedTypes)[number], checked: boolean) {
    onChange({ propertyTypes: checked ? [...selectedTypes, value] : selectedTypes.filter((t) => t !== value) })
  }

  return (
    <div className="space-y-4 rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
      <SearchText value={filters.q} onChange={onChange} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <label htmlFor={`${id}-min`} className={labelClass}>
            Min price
          </label>
          <select
            id={`${id}-min`}
            value={filters.minPrice ?? ''}
            onChange={(e) => onChange({ minPrice: toNumber(e.target.value) })}
            className={fieldClass}
          >
            <option value="">Any</option>
            {priceOptions(filters.minPrice).map((step) => (
              <option key={step} value={step} disabled={filters.maxPrice != null && step > filters.maxPrice}>
                {formatPriceStep(step)}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={`${id}-max`} className={labelClass}>
            Max price
          </label>
          <select
            id={`${id}-max`}
            value={filters.maxPrice ?? ''}
            onChange={(e) => onChange({ maxPrice: toNumber(e.target.value) })}
            className={fieldClass}
          >
            <option value="">Any</option>
            {priceOptions(filters.maxPrice).map((step) => (
              <option key={step} value={step} disabled={filters.minPrice != null && step < filters.minPrice}>
                {formatPriceStep(step)}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={`${id}-beds`} className={labelClass}>
            Bedrooms
          </label>
          <select
            id={`${id}-beds`}
            value={filters.minBedrooms ?? ''}
            onChange={(e) => onChange({ minBedrooms: toNumber(e.target.value) })}
            className={fieldClass}
          >
            <option value="">Any</option>
            {BEDROOM_OPTIONS.map((beds) => (
              <option key={beds} value={beds}>
                {beds}+
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={`${id}-sort`} className={labelClass}>
            Sort by
          </label>
          <select
            id={`${id}-sort`}
            value={filters.sort ?? 'newest'}
            onChange={(e) => onChange({ sort: e.target.value as Sort })}
            className={fieldClass}
          >
            {Object.entries(SORT_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {propertyTypes && (
        <fieldset>
          <legend className={labelClass}>Property type</legend>
          <div className="flex flex-wrap gap-2">
            {propertyTypes.map(({ value, label }) => {
              const checked = selectedTypes.includes(value)
              return (
                <label key={value} className="cursor-pointer">
                  <input
                    type="checkbox"
                    className="peer sr-only"
                    checked={checked}
                    onChange={(e) => toggleType(value, e.target.checked)}
                  />
                  <span className="inline-block rounded-full border border-slate-300 px-3 py-1 text-sm text-slate-700 peer-checked:border-indigo-600 peer-checked:bg-indigo-50 peer-checked:text-indigo-800 peer-focus-visible:ring-2 peer-focus-visible:ring-indigo-500 hover:border-indigo-400">
                    {/* Not colour alone (WCAG 1.4.1): a tick marks the selected types. */}
                    {checked && <span aria-hidden="true">✓ </span>}
                    {label}
                  </span>
                </label>
              )
            })}
          </div>
        </fieldset>
      )}

      <div className="flex flex-wrap items-center gap-x-6 gap-y-2">
        <label className="inline-flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            checked={!!filters.excludeUnderOffer}
            onChange={(e) => onChange({ excludeUnderOffer: e.target.checked })}
            className="h-4 w-4 rounded border-slate-300 text-indigo-600"
          />
          Exclude under offer
        </label>
        <label className="inline-flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            checked={!!filters.excludePriceWithheld}
            onChange={(e) => onChange({ excludePriceWithheld: e.target.checked })}
            className="h-4 w-4 rounded border-slate-300 text-indigo-600"
          />
          Exclude price withheld
        </label>
        {hasFilters && (
          <button
            type="button"
            onClick={() =>
              onChange({
                q: undefined,
                minPrice: undefined,
                maxPrice: undefined,
                minBedrooms: undefined,
                propertyTypes: undefined,
                excludeUnderOffer: undefined,
                excludePriceWithheld: undefined,
              })
            }
            className="ml-auto text-sm font-medium text-indigo-600 hover:underline"
          >
            Clear filters
          </button>
        )}
      </div>
    </div>
  )
}
