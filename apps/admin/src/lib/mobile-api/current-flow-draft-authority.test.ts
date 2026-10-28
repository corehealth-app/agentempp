import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  createSupabaseCurrentFlowDraftAuthority,
  readCurrentFlowDraftContext,
} from './current-flow-draft-authority'
import { currentOnboardingWire } from './testing/current-onboarding-fixture'
import { consentAuth, uid } from './testing/reevaluation-photo-consent-fixture'

function context() {
  return {
    version: 1,
    state: currentOnboardingWire(),
    day: {
      snapshot_id: uid(6900),
      date: '2026-10-27',
      calories_target: 1800,
      protein_target: 140,
      current_protocol: 'recomposicao',
      target_revision: '0',
      calorie_origin: null,
    },
    allowed: { training: true, nutrition: true },
  }
}
function setup() {
  const wire = context(),
    rpc = vi.fn(async (_name: string, _args: Record<string, unknown>) => ({
      data: structuredClone(wire) as unknown,
      error: null as unknown,
    }))
  const maybeSingle = vi.fn(async () => ({ data: { id: uid(6901) }, error: null }))
  const query = { select: vi.fn(() => query), eq: vi.fn(() => query), maybeSingle }
  const from = vi.fn(() => query),
    client = { rpc, from } as unknown as ServiceClient
  const authority = createSupabaseCurrentFlowDraftAuthority(client, consentAuth.userId)
  return { wire, rpc, query, from, client, authority }
}
describe('current Flow draft SQL authority adapter', () => {
  it('decodes and detaches a closed private context, rejecting foreign owners, unsafe numbers and policy contradictions', () => {
    const raw = context(),
      captured = readCurrentFlowDraftContext(raw, consentAuth.userId)
    raw.state.profile_hash = 'c'.repeat(64)
    expect(captured.state.profile_hash).toBe('a'.repeat(64))
    expect(Object.isFrozen(captured.day)).toBe(true)
    expect(() => readCurrentFlowDraftContext(context(), uid(6999))).toThrow()
    const invalid = context()
    invalid.day.protein_target = Number.NaN
    expect(() => readCurrentFlowDraftContext(invalid, consentAuth.userId)).toThrow()
    const contradiction = context()
    contradiction.allowed.nutrition = false
    expect(() => readCurrentFlowDraftContext(contradiction, consentAuth.userId)).toThrow()
  })
  it('fixes RPC/from receiver and owner; no input can select owner or clock', async () => {
    const s = setup()
    Object.assign(s.client, {
      rpc: () => {
        throw new Error('replaced')
      },
      from: () => {
        throw new Error('replaced')
      },
    })
    await s.authority.capture()
    const id = await s.authority.findTurn({
      domain: 'nutrition',
      requestKey: 'turn-original:propoe_plano_dieta',
    })
    expect(id).toBe(uid(6901))
    expect(s.rpc).toHaveBeenCalledWith('get_mobile_flow_plan_context', {
      p_user_id: consentAuth.userId,
    })
    expect(s.query.eq).toHaveBeenCalledWith('user_id', consentAuth.userId)
    expect(s.query.eq).toHaveBeenCalledWith('provider_message_id', 'turn-original')
    expect(s.query.eq).toHaveBeenCalledWith('provider', 'mobile_flow')
    expect(s.query.eq).toHaveBeenCalledWith('direction', 'in')
    expect(s.query.eq).toHaveBeenCalledWith('role', 'user')
  })
  it('uses only guarded lookup/create RPCs and returns actual persisted payload without private authority', async () => {
    const s = setup(),
      expected = readCurrentFlowDraftContext(s.wire, consentAuth.userId)
    const key = {
      domain: 'nutrition' as const,
      requestKey: 'turn-original:propoe_plano_dieta',
      sourceMessageId: uid(6901),
      expected,
    }
    s.rpc.mockResolvedValueOnce({
      data: {
        id: uid(6902),
        status: 'needs_completion',
        payload: { notes: 'patient edited' },
        binding: expected,
      },
      error: null,
    })
    expect(await s.authority.lookup(key)).toEqual({
      id: uid(6902),
      status: 'needs_completion',
      payload: { notes: 'patient edited' },
    })
    s.rpc.mockResolvedValueOnce({
      data: {
        id: uid(6902),
        status: 'needs_completion',
        inserted: false,
        payload: { notes: 'patient edited' },
        binding: expected,
      },
      error: null,
    })
    const result = await s.authority.create({
      ...key,
      status: 'needs_completion',
      payload: { meta_kcal: 1800, meta_protein_g: 140 },
      uncertainFields: [],
      originDetail: { identity: 'flow' },
    })
    expect(result).toEqual({
      id: uid(6902),
      status: 'needs_completion',
      inserted: false,
      payload: { notes: 'patient edited' },
    })
    expect(s.rpc.mock.calls.map(([name]) => name)).toEqual([
      'lookup_mobile_flow_plan_draft',
      'create_mobile_flow_plan_draft',
    ])
    expect(s.rpc).toHaveBeenLastCalledWith(
      'create_mobile_flow_plan_draft',
      expect.objectContaining({
        p_user_id: consentAuth.userId,
        p_source_message_id: uid(6901),
        p_expected: expected,
      }),
    )
  })
  it.each([
    '40001',
    '55P03',
    'P0002',
    '23514',
    '42501',
  ])('maps SQL %s without provider text or legacy retries', async (code) => {
    const s = setup()
    s.rpc.mockResolvedValueOnce({ data: null, error: { code, message: 'PRIVATE PROVIDER DETAIL' } })
    const promise = s.authority.capture()
    await expect(promise).rejects.not.toThrow('PRIVATE PROVIDER DETAIL')
    expect(s.rpc).toHaveBeenCalledTimes(1)
  })
})
