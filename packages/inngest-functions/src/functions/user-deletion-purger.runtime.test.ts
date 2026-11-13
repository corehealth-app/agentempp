import { afterEach, describe, expect, it, vi } from 'vitest'

const ports = vi.hoisted(() => ({ client: vi.fn() }))
vi.mock('../lib/env.js', () => ({ createWorkerSupabase: ports.client }))
const { userDeletionPurgerFn } = await import('./user-deletion-purger.js')
const owner = 'b3b01000-0000-4000-8000-000000000101'
const run = () =>
  (userDeletionPurgerFn as unknown as { fn: (ctx: unknown) => Promise<unknown> }).fn({
    step: { run: (_id: string, action: () => unknown) => action() },
    logger: { info: vi.fn() },
  })

describe('registered account purger ordinary-media boundary', () => {
  afterEach(() => {
    vi.clearAllMocks()
    vi.unstubAllEnvs()
  })
  it('the real conversational callback selects preflight before any catalogue or Storage access', async () => {
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-conversation-staging')
    const rpc = vi.fn((name: string) => ({
      abortSignal: async () => ({
        data:
          name === 'list_mobile_deleted_users_for_photo_purge'
            ? { version: 1, users: [{ id: owner }] }
            : false,
        error: null,
      }),
    }))
    const from = vi.fn(() => {
      throw new Error('must not access catalogue before revocation')
    })
    const storage = {
      from: vi.fn(() => {
        throw new Error('must not remove an empty barrier')
      }),
    }
    ports.client.mockReturnValue({ rpc, from, storage })
    expect(await run()).toEqual({ purged: 0, mediaRemoved: 0 })
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'list_mobile_deleted_users_for_photo_purge',
      'prepare_conversation_media_account_purge',
    ])
    expect(from).not.toHaveBeenCalled()
    expect(storage.from).not.toHaveBeenCalled()
  })
  it('the existing production callback does not depend on the new staging RPC', async () => {
    vi.stubEnv('INNGEST_FUNCTION_SET', undefined)
    const rpc = vi.fn((_name: string) => ({
      abortSignal: async () => ({ data: { version: 1, users: [] }, error: null }),
    }))
    ports.client.mockReturnValue({ rpc })
    expect(await run()).toEqual({ purged: 0, mediaRemoved: 0 })
    expect(rpc).toHaveBeenCalledOnce()
    expect(rpc.mock.calls[0]?.[0]).toBe('list_mobile_deleted_users_for_photo_purge')
  })
})
