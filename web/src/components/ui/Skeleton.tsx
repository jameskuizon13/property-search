export function PropertyCardSkeleton() {
  return (
    <div aria-hidden="true" className="animate-pulse overflow-hidden rounded-lg border border-slate-200 bg-white">
      <div className="aspect-[3/2] bg-slate-200" />
      <div className="space-y-3 p-4">
        <div className="h-5 w-1/3 rounded bg-slate-200" />
        <div className="h-4 w-2/3 rounded bg-slate-200" />
        <div className="h-4 w-1/2 rounded bg-slate-200" />
      </div>
    </div>
  )
}

export function PropertyCardSkeletons({ count }: { count: number }) {
  return Array.from({ length: count }, (_, i) => <PropertyCardSkeleton key={i} />)
}
