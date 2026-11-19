import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  createJourneyModerationService,
  JourneyModerationError,
} from '@/lib/journey-moderation/service'

const state = vi.hoisted(() => ({
  host: 'admin.example.invalid',
  disabled: false,
  physical: 0,
  headers: 0,
}))
vi.mock('next/headers', () => ({
  headers: async () => {
    state.headers++
    return new Headers({ host: state.host })
  },
}))
vi.mock('@/lib/journey-moderation/server', () => ({
  loadJourneyModerationOperator: async () => {
    if (state.disabled) throw new JourneyModerationError('unavailable')
    return {
      identity: {
        actor: '20000000-0000-4000-8000-000000000002',
        login: '20000000-0000-4000-a000-000000000002',
      },
      service: createJourneyModerationService(
        {
          rpc: async () => {
            state.physical++
            return { data: { entries: [], next_cursor: null }, error: null }
          },
        },
        {
          actor: '20000000-0000-4000-8000-000000000002',
          login: '20000000-0000-4000-a000-000000000002',
        },
        async () => {},
      ),
    }
  },
}))

import { journeyModerationAction } from './actions'

beforeEach(() => {
  state.host = 'admin.example.invalid'
  state.disabled = false
  state.physical = 0
  state.headers = 0
})
describe('actual Next operational action composition', () => {
  it.each([
    'admin.example.invalid',
    'admin.example.invalid:443',
  ])('uses canonical origin and opaque references for %s', async (host) => {
    state.host = host
    await expect(
      journeyModerationAction({ type: 'queue', context: null, query: { limit: 20, cursor: null } }),
    ).resolves.toEqual({
      ok: true,
      type: 'queue',
      context: {
        origin: 'https://admin.example.invalid',
        owner: '116234755b6d715da027f8def7c855b0379f43f61632186d08bcbbc9ec4bee87',
        login: 'deab31b7ba61be6560f34575ad01c5d143384ee600d8b29a945be3d9112613fe',
      },
      value: { entries: [], next_cursor: null },
    })
    expect(state.physical).toBe(1)
  })
  it('uses a local namespace for the actual loopback development host', async () => {
    state.host = '127.0.0.1:43991'
    const result = await journeyModerationAction({
      type: 'queue',
      context: null,
      query: { limit: 20, cursor: null },
    })
    expect(result).toMatchObject({ ok: true, context: { origin: 'http://127.0.0.1:43991' } })
  })
  it('checks capability/Auth admission before reading a request namespace', async () => {
    state.disabled = true
    await expect(
      journeyModerationAction({ type: 'queue', context: null, query: { limit: 20, cursor: null } }),
    ).resolves.toEqual({ ok: false, code: 'unavailable' })
    expect(state.physical).toBe(0)
    expect(state.headers).toBe(0)
  })
  it.each([
    'admin.example.invalid@other.invalid',
    'admin.example.invalid/forged',
  ])('rejects malformed authority without a physical RPC: %s', async (host) => {
    state.host = host
    const result = await journeyModerationAction({
      type: 'queue',
      context: null,
      query: { limit: 20, cursor: null },
    })
    expect(result).toMatchObject({ ok: false })
    expect(state.physical).toBe(0)
  })
})
