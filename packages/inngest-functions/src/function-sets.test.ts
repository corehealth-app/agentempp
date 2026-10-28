import { afterEach, describe, expect, it, vi } from 'vitest'
import { allFunctions, functionsForSet } from './index.js'

// A staging worker serves only what the app's media needs. Production keeps
// serving every function when no set is named.
describe('functionsForSet', () => {
  afterEach(() => vi.unstubAllEnvs())
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
  it('the clinical staging set explicitly adds only recurring cleanup without widening current sets', () => {
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    vi.stubEnv('SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    expect(ids(functionsForSet('media-clinical-staging'))).toEqual([
      'media-asset-processing',
      'reevaluation-photo-disposition-cleanup',
    ])
    expect(ids(functionsForSet('media-staging'))).toEqual(['media-asset-processing'])
    expect(ids(allFunctions)).not.toContain('reevaluation-photo-disposition-cleanup')
  })

  it.each([
    undefined,
    '',
    'http://xitugspwfxkcluxvrdeg.supabase.co',
    'https://xuxehkhdvjivitduarvb.supabase.co',
    'https://xitugspwfxkcluxvrdeg.supabase.co.evil.test',
    'https://xitugspwfxkcluxvrdeg.supabase.co:444',
    'https://xitugspwfxkcluxvrdeg.supabase.co/path',
    'https://user@xitugspwfxkcluxvrdeg.supabase.co',
    'https://xitugspwfxkcluxvrdeg.supabase.co?redirect=other',
    'https://xitugspwfxkcluxvrdeg.supabase.co#other',
  ])('refuses clinical registration for a mismatched effective target (%s)', (url) => {
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    vi.stubEnv('SUPABASE_URL', url)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', undefined)
    expect(() => functionsForSet('media-clinical-staging')).toThrow(
      'Clinical staging worker target unavailable',
    )
  })

  it('uses the same SUPABASE_URL precedence as the real worker client', () => {
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    vi.stubEnv('SUPABASE_URL', 'https://xuxehkhdvjivitduarvb.supabase.co')
    expect(() => functionsForSet('media-clinical-staging')).toThrow(
      'Clinical staging worker target unavailable',
    )
    vi.stubEnv('SUPABASE_URL', undefined)
    expect(ids(functionsForSet('media-clinical-staging'))).toHaveLength(2)
  })

  it('does not impose the new target guard on previously served sets', () => {
    vi.stubEnv('SUPABASE_URL', 'https://legacy-synthetic.example.test')
    expect(functionsForSet(undefined)).toBe(allFunctions)
    expect(ids(functionsForSet('media-staging'))).toEqual(['media-asset-processing'])
  })
})
