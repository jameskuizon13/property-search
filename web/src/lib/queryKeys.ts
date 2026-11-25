/**
 * Every query key in one place, so hooks, cache patches (watch toggles, and
 * live updates in Milestone 6) and tests can never drift apart.
 */
export const propertyKeys = {
  all: ['properties'] as const,
  lists: () => [...propertyKeys.all, 'list'] as const,
  /** `filters` is the normalised API filter object, so equivalent URLs share one cache entry. */
  list: (filters: object) => [...propertyKeys.lists(), filters] as const,
  types: ['propertyTypes'] as const,
}

export const watchlistKeys = {
  all: ['watchlist'] as const,
  list: () => [...watchlistKeys.all, 'list'] as const,
}
