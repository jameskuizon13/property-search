import { describe, expect, it } from 'vitest'
import { makeProperty } from '@/test/propertyHandlers'
import { featureParts } from './format'

describe('featureParts', () => {
  it('lists beds, baths, cars and land size', () => {
    expect(featureParts(makeProperty())).toEqual(['3 beds', '2 baths', '1 car', '320 m²'])
  })

  it('calls a home with no bedroom a studio and leaves out zero counts', () => {
    const studio = makeProperty({ propertyType: 'apartment_unit', bedrooms: 0, bathrooms: 1, carSpaces: 0, landSizeSqm: null })
    expect(featureParts(studio)).toEqual(['Studio', '1 bath'])
  })

  it('shows only the size for land', () => {
    const land = makeProperty({ propertyType: 'land', bedrooms: 0, bathrooms: 0, carSpaces: 0, landSizeSqm: 1200 })
    expect(featureParts(land)).toEqual(['1,200 m²'])
  })
})
