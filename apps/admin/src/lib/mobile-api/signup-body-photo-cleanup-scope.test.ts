import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { readSignupBodyPhotoCleanupScope } from './signup-body-photo-cleanup-scope'

const owner = '00000000-0000-4000-8000-000000000951'
const g = '2026-10-12T12:34:56.123456+03:00'
function client(data: unknown, error: unknown = null) {
  const rpc = vi.fn((_name: string, _params: Record<string, unknown>) => {
    const result = Object.assign(Promise.resolve({ data, error }), { abortSignal: vi.fn() })
    result.abortSignal.mockReturnValue(result)
    return result
  })
  return { rpc, service: { rpc } as unknown as ServiceClient }
}
afterEach(() => vi.useRealTimers())
describe('signup cleanup scope reader', () => {
  it.each([
    'not_required',
    'pending',
    'unknown',
  ] as const)('returns verified %s without private identifiers, preserving literal G', async (state) => {
    const api = client({ version: 1, user_id: owner, generation: g, state })
    expect(await readSignupBodyPhotoCleanupScope(api.service, owner, g)).toEqual({
      generation: g,
      state,
    })
    expect(api.rpc).toHaveBeenCalledWith('get_mobile_signup_body_photo_cleanup_scope', {
      p_user_id: owner,
      p_generation: g,
    })
  })
  it.each([
    {
      version: 1,
      user_id: '00000000-0000-4000-8000-000000000999',
      generation: g,
      state: 'not_required',
    },
    {
      version: 1,
      user_id: owner,
      generation: '2026-10-12T09:34:56.123456Z',
      state: 'not_required',
    },
    { version: 1, user_id: owner, generation: g, state: 'empty' },
    { version: 2, user_id: owner, generation: g, state: 'pending' },
    { version: 1, user_id: owner, generation: g, state: 'not_required', ids: [] },
    null,
  ])('does not interpret an invalid proof as no photos: %j', async (data) => {
    const api = client(data)
    expect(await readSignupBodyPhotoCleanupScope(api.service, owner, g)).toEqual({
      generation: g,
      state: 'unknown',
    })
  })
  it('RPC missing and thrown reads preserve uncertainty', async () => {
    expect(
      await readSignupBodyPhotoCleanupScope(client(null, { code: 'PGRST202' }).service, owner, g),
    ).toEqual({ generation: g, state: 'unknown' })
    const service = {
      rpc: () => {
        throw new Error('redacted')
      },
    } as unknown as ServiceClient
    expect(await readSignupBodyPhotoCleanupScope(service, owner, g)).toEqual({
      generation: g,
      state: 'unknown',
    })
  })
  it('bounds a noncooperative read and aborts without publishing its late proof', async () => {
    vi.useFakeTimers()
    let finish!: (value: { data: unknown; error: null }) => void
    let signal!: AbortSignal
    const query = Object.assign(
      new Promise<{ data: unknown; error: null }>((resolve) => {
        finish = resolve
      }),
      {
        abortSignal: (s: AbortSignal) => {
          signal = s
          return query
        },
      },
    )
    const service = { rpc: () => query } as unknown as ServiceClient
    const pending = readSignupBodyPhotoCleanupScope(service, owner, g)
    await vi.advanceTimersByTimeAsync(3000)
    expect(await pending).toEqual({ generation: g, state: 'unknown' })
    expect(signal.aborted).toBe(true)
    finish({
      data: { version: 1, user_id: owner, generation: g, state: 'not_required' },
      error: null,
    })
    await vi.runAllTimersAsync()
    expect(vi.getTimerCount()).toBe(0)
  })
})
