import { describe, expect, it } from 'vitest'
import { makeProperty } from '@/test/propertyHandlers'
import { featureParts, formatOpenHome } from './format'

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

describe('formatOpenHome', () => {
  const perthSaturday = { startsAt: '2026-11-28T02:00:00Z', endsAt: '2026-11-28T02:30:00Z' }

  it('shows the time where the property is, without a zone for a viewer in the same place', () => {
    expect(formatOpenHome(perthSaturday, 'Australia/Perth', 'Australia/Perth')).toEqual({
      day: 'Sat 28 Nov',
      time: '10:00 am – 10:30 am',
    })
  })

  it('adds the zone for a viewer somewhere else, so Perth time never reads as Sydney time', () => {
    expect(formatOpenHome(perthSaturday, 'Australia/Perth', 'Australia/Sydney').time).toBe(
      '10:00 am – 10:30 am AWST (1:00 pm your time)',
    )
  })

  it('adds the zone but not "your time" when the clock reads the same', () => {
    // Brisbane (AEST) and Sydney (AEST outside daylight saving) in June.
    const winter = { startsAt: '2026-06-13T00:00:00Z', endsAt: '2026-06-13T00:30:00Z' }
    expect(formatOpenHome(winter, 'Australia/Brisbane', 'Australia/Sydney').time).toBe('10:00 am – 10:30 am AEST')
  })

  it('names the viewer’s day when it is a different date there', () => {
    // Sat 10:00 am in Sydney is Fri 3:00 pm in Los Angeles.
    const sydneySaturday = { startsAt: '2026-12-04T23:00:00Z', endsAt: '2026-12-04T23:30:00Z' }
    expect(formatOpenHome(sydneySaturday, 'Australia/Sydney', 'America/Los_Angeles')).toEqual({
      day: 'Sat 5 Dec',
      time: '10:00 am – 10:30 am AEDT (Fri 3:00 pm your time)',
    })
  })
})
