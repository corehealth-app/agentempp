import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// Real roster, callback, account-purge adapter and decoder; only the external
// privileged client is replaced so refusal cannot affect a real account.
const ports = vi.hoisted(() => ({ client: vi.fn() }))
vi.mock('../lib/env.js', () => ({ createWorkerSupabase: ports.client }))
const { allFunctions, functionsForSet } = await import('../index.js')

const logger = { info: vi.fn() }
const run = (callback: unknown, step?: { run: (id: string, action: () => unknown) => unknown }) =>
  (callback as { fn: (context: unknown) => Promise<unknown> }).fn({
    step: step ?? { run: (_id: string, action: () => unknown) => action() },
    logger,
  })
const select = () =>
  functionsForSet('media-conversation-staging').find((fn) => fn.id() === 'user-deletion-purger')

describe('conversational account purge rechecks its execution boundary', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-conversation-staging')
    vi.stubEnv('SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', undefined)
    ports.client.mockReturnValue({
      rpc: () => ({
        abortSignal: async () => ({ data: { version: 1, users: [] }, error: null }),
      }),
    })
  })
  afterEach(() => vi.unstubAllEnvs())

  it('runs the real bounded purger when the effective staging target still matches', async () => {
    expect(await run(select())).toEqual({ purged: 0, mediaRemoved: 0 })
    expect(ports.client).toHaveBeenCalledOnce()
  })

  it.each([
    undefined,
    '',
    'media-staging',
    'media-clinical-staging',
    'all',
  ])('refuses a callback selected earlier when its set changes to %s', async (set) => {
    const callback = select()
    vi.stubEnv('INNGEST_FUNCTION_SET', set)
    await expect(run(callback)).rejects.toThrow('Clinical staging worker target unavailable')
    expect(ports.client).not.toHaveBeenCalled()
  })

  it.each([
    '',
    'https://xuxehkhdvjivitduarvb.supabase.co',
    'https://xitugspwfxkcluxvrdeg.supabase.co/foreign',
  ])('refuses a changed effective database before constructing a client (%s)', async (url) => {
    const callback = select()
    vi.stubEnv('SUPABASE_URL', url)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    await expect(run(callback)).rejects.toThrow('Clinical staging worker target unavailable')
    expect(ports.client).not.toHaveBeenCalled()
  })

  it('rechecks inside the durable step, after a callback has already started', async () => {
    let action: (() => unknown) | undefined
    await run(select(), {
      run: (_id, selectedAction) => {
        action = selectedAction
      },
    })
    vi.stubEnv('SUPABASE_URL', 'https://xuxehkhdvjivitduarvb.supabase.co')
    await expect(action?.()).rejects.toThrow('Clinical staging worker target unavailable')
    expect(ports.client).not.toHaveBeenCalled()
  })

  it('accepts the exact fallback origin supported by the privileged client', async () => {
    const callback = select()
    vi.stubEnv('SUPABASE_URL', undefined)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co/')
    expect(await run(callback)).toEqual({ purged: 0, mediaRemoved: 0 })
  })

  it('does not leak provider details or log success when the purge fails', async () => {
    ports.client.mockImplementation(() => {
      throw Error('private credential and customer path')
    })
    await expect(run(select())).rejects.toThrow(/^Conversation account purge unavailable$/)
    expect(logger.info).not.toHaveBeenCalled()
  })

  it('leaves the original production callback available without imposing staging policy', async () => {
    const callback = allFunctions.find((fn) => fn.id() === 'user-deletion-purger')
    vi.stubEnv('INNGEST_FUNCTION_SET', undefined)
    vi.stubEnv('SUPABASE_URL', 'https://legacy-synthetic.example.test')
    expect(await run(callback)).toEqual({ purged: 0, mediaRemoved: 0 })
  })
})
