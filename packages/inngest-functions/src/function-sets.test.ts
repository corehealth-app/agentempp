import { describe, expect, it } from 'vitest'
import { allFunctions, functionsForSet } from './index.js'

// A staging worker serves only what the app's media needs. Production keeps
// serving every function when no set is named.
describe('functionsForSet', () => {
  const ids = (fns: readonly { id: (prefix?: string) => string }[]) => fns.map((fn) => fn.id())

  it('serves every function when no set is named (production behaviour unchanged)', () => {
    expect(functionsForSet(undefined)).toBe(allFunctions)
    expect(functionsForSet('')).toBe(allFunctions)
  })

  it('media-staging serves only the media processing function', () => {
    const selected = functionsForSet('media-staging')
    expect(ids(selected)).toEqual(['media-asset-processing'])
  })

  it('media-staging has no cron, no WhatsApp and no reminder function', () => {
    const selected = functionsForSet('media-staging')
    const forbidden = [
      'process-message',
      'daily-closer',
      'media-retention-cleanup',
      'reminder-scheduler',
      'training-daily-delivery',
      'engagement-sender',
    ]
    for (const id of forbidden) {
      expect(ids(selected).some((selectedId) => selectedId.includes(id))).toBe(false)
    }
  })

  it('an unknown set name is refused, never widened to all functions', () => {
    expect(() => functionsForSet('media')).toThrow(/unknown Inngest function set/)
    expect(() => functionsForSet('all')).toThrow(/unknown Inngest function set/)
  })
})
