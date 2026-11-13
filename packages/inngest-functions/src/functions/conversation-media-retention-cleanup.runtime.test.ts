import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const ports = vi.hoisted(() => ({ client: vi.fn(), dependencies: vi.fn(), cleanup: vi.fn() }))
vi.mock('../lib/env.js', () => ({ createWorkerSupabase: ports.client }))
vi.mock('./media-retention-cleanup.js', async (original) => ({
  ...(await original<typeof import('./media-retention-cleanup.js')>()),
  createRetentionDependencies: ports.dependencies,
  cleanupExpiredMedia: ports.cleanup,
}))
const { conversationMediaRetentionCleanupFn } = await import(
  './conversation-media-retention-cleanup.js'
)
const logger = { info: vi.fn(), warn: vi.fn() }
const run = () =>
  (
    conversationMediaRetentionCleanupFn as unknown as {
      fn: (ctx: unknown) => Promise<unknown>
    }
  ).fn({ step: { run: (_id: string, action: () => unknown) => action() }, logger })

describe('registered conversational staging media retention boundary', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-conversation-staging')
    vi.stubEnv('SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    ports.client.mockReturnValue({ synthetic: 'client' })
    ports.dependencies.mockReturnValue({ synthetic: 'dependencies' })
    ports.cleanup.mockResolvedValue({ deleted: 2 })
  })
  afterEach(() => vi.unstubAllEnvs())
  it('uses the bounded existing algorithm with the explicit ordinary-media scope', async () => {
    expect(conversationMediaRetentionCleanupFn.id()).toBe('conversation-media-retention-cleanup')
    expect(await run()).toEqual({ swept: 2, issuanceDrain: 'not_qualified' })
    expect(ports.client).toHaveBeenCalledTimes(1)
    expect(ports.dependencies).toHaveBeenCalledWith(
      { synthetic: 'client' },
      { scope: 'conversation' },
    )
    expect(ports.cleanup).toHaveBeenCalledOnce()
    expect(logger.info).toHaveBeenCalledWith('conversation media sweep completed', {
      swept: 2,
      issuanceDrain: 'not_qualified',
    })
  })
  it.each([
    undefined,
    '',
    'media-staging',
    'media-clinical-staging',
    'all',
  ])('refuses a stale/direct callback outside its own set (%s)', async (set) => {
    vi.stubEnv('INNGEST_FUNCTION_SET', set)
    await expect(run()).rejects.toThrow('Clinical staging worker target unavailable')
    expect(ports.client).not.toHaveBeenCalled()
    expect(ports.dependencies).not.toHaveBeenCalled()
    expect(ports.cleanup).not.toHaveBeenCalled()
  })
  it.each([
    '',
    'https://xuxehkhdvjivitduarvb.supabase.co',
    'https://xitugspwfxkcluxvrdeg.supabase.co/foreign',
  ])('refuses a foreign effective database before constructing a client (%s)', async (url) => {
    vi.stubEnv('SUPABASE_URL', url)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    await expect(run()).rejects.toThrow('Clinical staging worker target unavailable')
    expect(ports.client).not.toHaveBeenCalled()
  })
  it('accepts the same exact fallback URL semantics as the real privileged client', async () => {
    vi.stubEnv('SUPABASE_URL', undefined)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co/')
    expect(await run()).toEqual({ swept: 2, issuanceDrain: 'not_qualified' })
  })
  it('returns a safe bounded error without private provider text or false success', async () => {
    ports.cleanup.mockRejectedValue(Error('private customer object/path or provider response'))
    await expect(run()).rejects.toThrow(/^Conversation media retention unavailable$/)
    expect(logger.info).not.toHaveBeenCalled()
    expect(logger.warn).not.toHaveBeenCalled()
  })
})
