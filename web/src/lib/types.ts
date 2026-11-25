/** Paged list responses: `{ data, meta }` from the API's success envelope. */
export type PageMeta = {
  limit: number
  hasMore: boolean
  nextCursor?: string
  /** Sent with the first batch only. */
  totalCount?: number
}

export type Page<T> = { data: T[]; meta: PageMeta }

/** `getNextPageParam` for every paged list: the cursor, or undefined at the end. */
export const nextCursor = (last: Page<unknown>) => (last.meta.hasMore ? last.meta.nextCursor : undefined)
