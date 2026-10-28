import { afterEach, describe, expect, it, vi } from 'vitest'
import { assertClinicalStagingWorkerTarget } from './clinical-staging-worker-target.js'

const factory = vi.hoisted(() => vi.fn(() => ({ synthetic: true })))
vi.mock('@mpp/db', () => ({ createServiceClient: factory }))
const { createWorkerSupabase } = await import('./env.js')

describe('clinical staging privileged client target', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
    vi.clearAllMocks()
  })
  it('blocks a mismatch before constructing even a privileged client', () => {
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    vi.stubEnv('SUPABASE_URL', 'https://legacy-synthetic.example.test')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', 'synthetic-server-only')
    expect(() => createWorkerSupabase()).toThrow('Clinical staging worker target unavailable')
    expect(factory).not.toHaveBeenCalled()
  })
  it('passes through the existing factory and configuration for an allowed staging target', () => {
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    vi.stubEnv('SUPABASE_URL', undefined)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co/')
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', 'synthetic-server-only')
    createWorkerSupabase()
    expect(factory).toHaveBeenCalledTimes(1)
    expect(factory).toHaveBeenCalledWith({
      url: 'https://xitugspwfxkcluxvrdeg.supabase.co/',
      serviceRoleKey: 'synthetic-server-only',
    })
  })
  it('preserves ordinary legacy client configuration without widening cleanup access', () => {
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-staging')
    vi.stubEnv('SUPABASE_URL', 'https://legacy-synthetic.example.test')
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', 'synthetic-server-only')
    createWorkerSupabase()
    expect(factory).toHaveBeenCalledTimes(1)
    expect(factory).toHaveBeenCalledWith({
      url: 'https://legacy-synthetic.example.test',
      serviceRoleKey: 'synthetic-server-only',
    })
    expect(() => assertClinicalStagingWorkerTarget()).toThrow(
      'Clinical staging worker target unavailable',
    )
  })
})
