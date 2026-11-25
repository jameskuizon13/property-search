/** 500000 → "$500k", 1250000 → "$1.25M". */
export function formatPriceStep(value: number) {
  if (value >= 1_000_000) return `$${Number((value / 1_000_000).toFixed(2))}M`
  if (value >= 1_000) return `$${Number((value / 1_000).toFixed(1))}k`
  return `$${value}`
}
