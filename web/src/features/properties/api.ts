import { apiFetch } from '@/lib/api'
import type { Page } from '@/lib/types'
import type { PropertyTypeValue, SearchFilters } from './searchSchema'
import type { Property } from './types'

export function searchParams(filters: SearchFilters, cursor: string | null) {
  const params = new URLSearchParams()
  if (filters.q) params.set('q', filters.q)
  if (filters.minPrice != null) params.set('minPrice', String(filters.minPrice))
  if (filters.maxPrice != null) params.set('maxPrice', String(filters.maxPrice))
  if (filters.minBedrooms != null) params.set('minBedrooms', String(filters.minBedrooms))
  if (filters.propertyTypes?.length) params.set('propertyTypes', filters.propertyTypes.join(','))
  if (filters.excludeUnderOffer) params.set('excludeUnderOffer', 'true')
  if (filters.excludePriceWithheld) params.set('excludePriceWithheld', 'true')
  if (filters.sort) params.set('sort', filters.sort)
  if (cursor) params.set('cursor', cursor)
  return params
}

export function fetchProperties(filters: SearchFilters, cursor: string | null, signal?: AbortSignal) {
  const query = searchParams(filters, cursor).toString()
  return apiFetch<Page<Property>>(`/properties${query ? `?${query}` : ''}`, { signal })
}

export type PropertyTypeOption = { value: PropertyTypeValue; label: string }

export async function fetchPropertyTypes() {
  const { data } = await apiFetch<{ data: PropertyTypeOption[] }>('/property_types')
  return data
}
