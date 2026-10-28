import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const ports = vi.hoisted(() => ({
  createClient: vi.fn(),
  createDependencies: vi.fn(),
  cleanup: vi.fn(),
}))
vi.mock('../lib/env.js', () => ({ createWorkerSupabase: ports.createClient }))
vi.mock('../lib/supabase-reevaluation-photo-cleanup.js', () => ({
  createReevaluationPhotoCleanupDependencies: ports.createDependencies,
}))
vi.mock('../lib/reevaluation-photo-cleanup.js', () => ({
  cleanupReevaluationPhotos: ports.cleanup,
}))
const { reevaluationPhotoDispositionCleanupFn } = await import(
  './reevaluation-photo-disposition-cleanup.js'
)
const run = () =>
  (
    reevaluationPhotoDispositionCleanupFn as unknown as {
      fn: (context: unknown) => Promise<unknown>
    }
  ).fn({
    step: { run: (_id: string, action: () => unknown) => action() },
    logger: { info: vi.fn(), warn: vi.fn() },
  })

describe('recurring photo worker target at the actual handler boundary', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    ports.createClient.mockReturnValue({ synthetic: 'client' })
    ports.createDependencies.mockReturnValue({ synthetic: 'dependencies' })
    ports.cleanup.mockResolvedValue({ incomplete: 0, newlyDeleted: 0, stopped: 'batch_end' })
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    vi.stubEnv('SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
  })
  afterEach(() => vi.unstubAllEnvs())

  it.each([
    'all',
    'media-staging',
    undefined,
  ])('refuses a direct cleanup call outside its explicit set (%s)', async (set) => {
    vi.stubEnv('INNGEST_FUNCTION_SET', set)
    await expect(run()).rejects.toThrow('Clinical staging worker target unavailable')
    expect(ports.createClient).not.toHaveBeenCalled()
    expect(ports.createDependencies).not.toHaveBeenCalled()
    expect(ports.cleanup).not.toHaveBeenCalled()
  })

  it('refuses a stale invocation targeting another DB before any client, RPC or Storage capability exists', async () => {
    vi.stubEnv('SUPABASE_URL', 'https://xuxehkhdvjivitduarvb.supabase.co')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    await expect(run()).rejects.toThrow('Clinical staging worker target unavailable')
    expect(ports.createClient).not.toHaveBeenCalled()
    expect(ports.createDependencies).not.toHaveBeenCalled()
    expect(ports.cleanup).not.toHaveBeenCalled()
  })

  it('uses the established cleanup exactly once for the explicit valid staging set', async () => {
    expect(await run()).toEqual({ incomplete: 0, newlyDeleted: 0, stopped: 'batch_end' })
    expect(ports.createClient).toHaveBeenCalledTimes(1)
    expect(ports.createDependencies).toHaveBeenCalledWith({ synthetic: 'client' })
    expect(ports.cleanup).toHaveBeenCalledTimes(1)
    expect(ports.cleanup).toHaveBeenCalledWith({ synthetic: 'dependencies' })
  })
})
