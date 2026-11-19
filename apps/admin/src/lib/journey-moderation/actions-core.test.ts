import { describe, expect, it } from 'vitest'
import { runJourneyModerationAction } from './actions-core'
import { createJourneyModerationService } from './service'

const context = {
  origin: 'https://admin.example.invalid',
  owner: 'a'.repeat(64),
  login: 'b'.repeat(64),
}
const member = '20000000-0000-4000-9000-000000000001'
const command = {
  operation_id: '20000000-0000-4000-b000-000000000001',
  member_id: member,
  expected_revision: 1,
  action: 'suspend' as const,
}
function fixture() {
  const calls: Array<Record<string, unknown>> = []
  const service = createJourneyModerationService(
    {
      rpc: async (_name, args) => {
        calls.push(args)
        return { data: { entries: [], next_cursor: null }, error: null }
      },
    },
    {
      actor: '20000000-0000-4000-8000-000000000002',
      login: '20000000-0000-4000-a000-000000000002',
    },
    async () => {},
  )
  const deps = { load: async () => ({ context, service }) }
  return { calls, deps }
}
describe('operational action admission', () => {
  it('boots by reading only after authenticated server composition', async () => {
    const f = fixture()
    await expect(
      runJourneyModerationAction(
        { type: 'queue', context: null, query: { limit: 20, cursor: null } },
        f.deps,
      ),
    ).resolves.toEqual({
      ok: true,
      context,
      type: 'queue',
      value: { entries: [], next_cursor: null },
    })
    expect(f.calls).toHaveLength(1)
  })
  it.each([
    { ...context, owner: 'c'.repeat(64) },
    { ...context, login: 'c'.repeat(64) },
    { ...context, origin: 'https://other.example.invalid' },
  ])('does not transfer an old writer to another context: %j', async (c) => {
    const f = fixture()
    await expect(
      runJourneyModerationAction({ type: 'moderate', context: c, command }, f.deps),
    ).resolves.toEqual({ ok: false, code: 'unauthorized' })
    expect(f.calls).toEqual([])
  })
  it('refuses browser-supplied operator authority before a physical operation', async () => {
    const f = fixture()
    await expect(
      runJourneyModerationAction(
        { type: 'moderate', context, command, actor_id: 'forged' },
        f.deps,
      ),
    ).resolves.toEqual({ ok: false, code: 'invalid' })
    expect(f.calls).toEqual([])
  })
  it('refuses recovery of another operator pending command', async () => {
    const f = fixture()
    await expect(
      runJourneyModerationAction(
        {
          type: 'recover',
          context,
          pending_owner: 'c'.repeat(64),
          request: { kind: 'profile', command },
        },
        f.deps,
      ),
    ).resolves.toEqual({ ok: false, code: 'unauthorized' })
    expect(f.calls).toEqual([])
  })
  it('does not disclose a provider exception', async () => {
    await expect(
      runJourneyModerationAction(
        { type: 'queue', context: null, query: { limit: 20, cursor: null } },
        {
          load: async () => {
            throw Error('private provider secret')
          },
        },
      ),
    ).resolves.toEqual({ ok: false, code: 'unavailable' })
  })
})
