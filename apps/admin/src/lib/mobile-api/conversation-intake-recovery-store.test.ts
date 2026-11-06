import { describe, expect, it, vi } from 'vitest'
import {
  bindConversationIntake,
  type ConversationIntakeBinding,
  type ConversationIntakeRoutingDecision,
} from './conversation-intake-contracts'
import {
  type ConversationIntakeRecoveryRPCPort,
  createConversationIntakeRecoveryStore,
} from './conversation-intake-recovery-store'
import {
  type ConversationIntakeScopePort,
  ConversationIntakeScopeRefusal,
} from './conversation-intake-store'
import { workoutDigest } from './conversation-workout-contracts'

interface ProofFixture {
  action: 'available'
  intake: ConversationIntakeBinding
  source_hash: string
  claim_id: string
  lease_anchor_at: string
  lease_clock_origin: 'claim' | 'migration_backfill'
  result: null | {
    schema: 'conversation.intake-routing-result.v1'
    decision_hash: string
    decision: ConversationIntakeRoutingDecision
    recorded_at: string
    origin: 'router' | 'interrupted' | 'sealed_selection_backfill'
  }
}
// Actual SQL snapshots; private synthetic proofs, not public DTOs or current Auth.
// Read source SHA ba81a8f4458f9c5c2f0dd19ed1e4b750308e0cb3cf078f513f588e5c8cb2a58b.
// Original input is the literal pg_temp.t41_input/arena inp source, never inferred
// from typed IDs or guessed variants; its canonical hash is asserted below.
const actualReads: readonly { label: string; proof: ProofFixture }[] = [
  {
    label: 'day_closed',
    proof: {
      action: 'available',
      intake: {
        epoch: 'd1bf074b-9ef8-412b-bffa-2fa654c65e63',
        owner_id: 'c1410000-0000-4000-8000-000000000004',
        intake_id: 'ce299cac-671c-45c2-bd17-3386d9c039c9',
        input_hash: 'a1c813cf4f7fd3a64f1c3f829bb3d93f16721bc1a4cf00256479efabdc8837ca',
        admitted_at: '2026-11-05T16:40:50.933040Z',
      },
      result: {
        origin: 'router',
        schema: 'conversation.intake-routing-result.v1',
        decision: {
          kind: 'workout.report',
          reason: 'performed_activity',
          schema: 'conversation.intake-routing.v1',
        },
        recorded_at: '2026-11-05T16:40:51.069393Z',
        decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
      },
      claim_id: 'bd46eb29-6075-41c3-9376-f38c6ea5fc2e',
      source_hash: '05da677d50e943546ebef5fc66739079fc20b494d0b34efe3b77c7c4b54419c5',
      lease_anchor_at: '2026-11-05T16:40:51.066640Z',
      lease_clock_origin: 'claim',
    },
  },
  {
    label: 'interrupt',
    proof: {
      action: 'available',
      intake: {
        epoch: '58e8d4a0-44c8-4e7f-946c-abf1c347b236',
        owner_id: 'c1410000-0000-4000-8000-000000000006',
        intake_id: 'ab1031f4-de55-4afe-b885-5e3acf7032b9',
        input_hash: 'e845c6ea815366664b36c3b3b536039d42c8297911fa60462a4e0019a35de78f',
        admitted_at: '2026-11-05T16:40:51.289092Z',
      },
      result: {
        origin: 'interrupted',
        schema: 'conversation.intake-routing-result.v1',
        decision: {
          kind: 'clarification_required',
          reason: 'routing_interrupted',
          schema: 'conversation.intake-routing.v1',
          question: {
            text: 'Não foi possível concluir o processamento. Pode confirmar o que deseja registrar?',
            field: 'description',
          },
        },
        recorded_at: '2026-11-05T16:41:52.590987Z',
        decision_hash: 'cc1724c75b94e60d9d1dc0f61422b6e8794215d42f945f12c5a027cbe2611d1b',
      },
      claim_id: 'f7bc5a40-55b2-445a-b1d9-e63277ec1fc9',
      source_hash: '6e5626b301f3c241828749c1983cfea0d7a7d638ac90d3acaffdfebebbf9b0c9',
      lease_anchor_at: '2026-11-05T16:40:51.409617Z',
      lease_clock_origin: 'claim',
    },
  },
  {
    label: 'interrupt_closed_changed',
    proof: {
      action: 'available',
      intake: {
        epoch: 'bfe45f62-7203-4887-abb9-ac8f94f6af8f',
        owner_id: 'c1410000-0000-4000-8000-000000000007',
        intake_id: '4f352865-3ef6-4064-99ec-c7e821a81bea',
        input_hash: '538d3426f926b66c083f63c068581f42e7a553b8c257623c5d64c34a7161d558',
        admitted_at: '2026-11-05T16:40:51.412649Z',
      },
      result: {
        origin: 'interrupted',
        schema: 'conversation.intake-routing-result.v1',
        decision: {
          kind: 'clarification_required',
          reason: 'routing_interrupted',
          schema: 'conversation.intake-routing.v1',
          question: {
            text: 'Não foi possível concluir o processamento. Pode confirmar o que deseja registrar?',
            field: 'description',
          },
        },
        recorded_at: '2026-11-05T16:41:52.596238Z',
        decision_hash: 'cc1724c75b94e60d9d1dc0f61422b6e8794215d42f945f12c5a027cbe2611d1b',
      },
      claim_id: '139eade5-9b42-4f2d-9e8b-ab9e1d4460d7',
      source_hash: '8a953bbeb77d9707e915d8418ca37d952d106b547633a2ae94363ab022d5654a',
      lease_anchor_at: '2026-11-05T16:40:51.538539Z',
      lease_clock_origin: 'claim',
    },
  },
  {
    label: 'old_pending',
    proof: {
      action: 'available',
      intake: {
        epoch: '016d425b-f7c4-4bd2-96af-2aa139a39a90',
        owner_id: 'c1410000-0000-4000-8000-000000000002',
        intake_id: '272eebe1-fd29-4353-a26c-6d3e58c499b3',
        input_hash: '96c8034cb727db7f43fe2fbc534959221fbb80871810c4fd659cfc0e8cfc2376',
        admitted_at: '2026-11-05T16:40:50.451643Z',
      },
      result: {
        origin: 'interrupted',
        schema: 'conversation.intake-routing-result.v1',
        decision: {
          kind: 'clarification_required',
          reason: 'routing_interrupted',
          schema: 'conversation.intake-routing.v1',
          question: {
            text: 'Não foi possível concluir o processamento. Pode confirmar o que deseja registrar?',
            field: 'description',
          },
        },
        recorded_at: '2026-11-05T16:41:52.577352Z',
        decision_hash: 'cc1724c75b94e60d9d1dc0f61422b6e8794215d42f945f12c5a027cbe2611d1b',
      },
      claim_id: 'df434c8f-be03-42d3-857f-0c964a866185',
      source_hash: 'e89ffa9b09e1c51f2588ecfc8b00915b6ff3604b920f57f7b3a556b54088d80e',
      lease_anchor_at: '2026-11-05T16:40:50.647642Z',
      lease_clock_origin: 'migration_backfill',
    },
  },
  {
    label: 'old_sealed',
    proof: {
      action: 'available',
      intake: {
        epoch: 'd5b5b740-79fc-4bca-85da-411cecc30b40',
        owner_id: 'c1410000-0000-4000-8000-000000000001',
        intake_id: '7fb0e4d1-7361-4e13-a759-6714ceaf24a7',
        input_hash: '6826529aa9e4fc1e70a5b7b6daba2e139a5e8ef41d9bfceeb8c63ba5bdb47f99',
        admitted_at: '2026-11-05T16:40:49.999218Z',
      },
      result: {
        origin: 'sealed_selection_backfill',
        schema: 'conversation.intake-routing-result.v1',
        decision: {
          kind: 'workout.report',
          reason: 'performed_activity',
          schema: 'conversation.intake-routing.v1',
        },
        recorded_at: '2026-11-05T16:40:50.446567Z',
        decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
      },
      claim_id: 'f78faaf3-bf12-4111-b7f4-0d87d96b1d87',
      source_hash: '7f2759836aebe3b706db8c0c773b75d39c28d913a7174d58e332b9272c89f13d',
      lease_anchor_at: '2026-11-05T16:40:50.647642Z',
      lease_clock_origin: 'migration_backfill',
    },
  },
  {
    label: 'quota',
    proof: {
      action: 'available',
      intake: {
        epoch: 'f4880c4c-7e92-457c-ae9d-93095259ff3a',
        owner_id: 'c1410000-0000-4000-8000-000000000003',
        intake_id: '44ff5f89-81ea-402c-9b3b-23ae84605025',
        input_hash: 'ebced68ae308836834e41eeb796a0b5d341a1484d3a8820488dbbb8ddb44fb79',
        admitted_at: '2026-11-05T16:40:50.674482Z',
      },
      result: {
        origin: 'router',
        schema: 'conversation.intake-routing-result.v1',
        decision: {
          kind: 'workout.report',
          reason: 'performed_activity',
          schema: 'conversation.intake-routing.v1',
        },
        recorded_at: '2026-11-05T16:40:50.845067Z',
        decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
      },
      claim_id: '77abce2b-e8d5-4b8f-a9d6-abebe73d667d',
      source_hash: 'a682a83180a8850ab317d3ba789e02b3313271c4afdc373a394485a39bdfd1bf',
      lease_anchor_at: '2026-11-05T16:40:50.826366Z',
      lease_clock_origin: 'claim',
    },
  },
]

const actualReconciles: readonly {
  label: string
  response: { action: 'reconciled' | 'replay'; result: ProofFixture }
}[] = [
  {
    label: 'interrupted',
    response: {
      action: 'reconciled',
      result: {
        action: 'available',
        intake: {
          epoch: 'c141c000-0000-4000-8000-000000001003',
          owner_id: 'c141c000-0000-4000-8000-000000000003',
          intake_id: 'c141c000-0000-4000-8000-000000002003',
          input_hash: 'be9b4d5c017e3b8a95451aac4d199e84634eabf3c979adc5d1eee470d7a3febf',
          admitted_at: '2026-11-05T16:45:18.120202Z',
        },
        result: {
          origin: 'interrupted',
          schema: 'conversation.intake-routing-result.v1',
          decision: {
            kind: 'clarification_required',
            reason: 'routing_interrupted',
            schema: 'conversation.intake-routing.v1',
            question: {
              text: 'Não foi possível concluir o processamento. Pode confirmar o que deseja registrar?',
              field: 'description',
            },
          },
          recorded_at: '2026-11-05T16:46:27.994698Z',
          decision_hash: 'cc1724c75b94e60d9d1dc0f61422b6e8794215d42f945f12c5a027cbe2611d1b',
        },
        claim_id: '4109f9db-8f8c-4017-91ee-7319aa782371',
        source_hash: '7371fffe1bac40a0acdf7808b2edcf9983ddf71fcdb1f0f987b107200c850f82',
        lease_anchor_at: '2026-11-05T16:45:18.899885Z',
        lease_clock_origin: 'claim',
      },
    },
  },
  {
    label: 'known_router_replay',
    response: {
      action: 'replay',
      result: {
        action: 'available',
        intake: {
          epoch: 'c141c000-0000-4000-8000-000000001001',
          owner_id: 'c141c000-0000-4000-8000-000000000001',
          intake_id: 'c141c000-0000-4000-8000-000000002001',
          input_hash: '6ba1affda9de2a87bd50ca51fe76d166b7b17f402613c094561a466b6adedff7',
          admitted_at: '2026-11-05T16:45:15.391039Z',
        },
        result: {
          origin: 'router',
          schema: 'conversation.intake-routing-result.v1',
          decision: {
            kind: 'workout.report',
            reason: 'performed_activity',
            schema: 'conversation.intake-routing.v1',
          },
          recorded_at: '2026-11-05T16:45:37.322950Z',
          decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
        },
        claim_id: '95a3b7fb-741f-4579-92d8-130434040e69',
        source_hash: 'b7f878b5588329030cf2d67648fc0bfb747d6e4f0c1c521b4cad243abfa35899',
        lease_anchor_at: '2026-11-05T16:45:16.395801Z',
        lease_clock_origin: 'claim',
      },
    },
  },
]

function required<T>(value: T | null | undefined): T {
  if (value == null) throw new Error('Missing actual qualified SQL fixture')
  return value
}
function frame(proof: ProofFixture) {
  const input = {
      intake_protocol: 'conversation.intake.v1',
      intake_id: proof.intake.intake_id,
      source: { channel: 'text', text: 'Fiz 30 minutos de caminhada.' },
    },
    bound = bindConversationIntake(
      proof.intake.owner_id,
      `cintake1:${proof.intake.intake_id}`,
      input,
    )
  if (bound.inputHash !== proof.intake.input_hash)
    throw new Error('Original SQL source/input hash mismatch')
  return { bound, parent: structuredClone(proof.intake), sourceHash: proof.source_hash }
}
function setup(label = 'old_sealed') {
  const proof = structuredClone(required(actualReads.find((x) => x.label === label)).proof),
    original = frame(proof),
    rpc = vi.fn<ConversationIntakeRecoveryRPCPort['rpc']>(async () => ({
      data: proof,
      error: null,
    })),
    checkCurrentScope = vi.fn<ConversationIntakeScopePort['checkCurrentScope']>(async () => true),
    api = createConversationIntakeRecoveryStore({ rpc }, { checkCurrentScope })
  return { ...original, proof, rpc, checkCurrentScope, api }
}

describe('private durable intake recovery store', () => {
  it('reads the actual sealed backfill proof with its original clock before the migration anchor', async () => {
    const h = setup()
    expect(await h.api.read(h.bound, h.parent, h.sourceHash)).toEqual(h.proof)
    expect(h.rpc).toHaveBeenCalledWith('read_conversation_intake_routing_result', {
      p_user_id: h.parent.owner_id,
      p_intake_id: h.parent.intake_id,
      p_input_hash: h.parent.input_hash,
      p_expected_epoch: h.parent.epoch,
      p_source_hash: h.sourceHash,
    })
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
  })
  it.each(
    actualReads.map((x) => [x.label] as const),
  )('round-trips complete actual SQL read case %s without repair', async (label) => {
    const h = setup(label)
    expect(await h.api.read(h.bound, h.parent, h.sourceHash)).toEqual(h.proof)
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake_routing_result',
    ])
    expect(h.checkCurrentScope.mock.calls).toEqual([
      [
        {
          ownerId: h.parent.owner_id,
          intakeId: h.parent.intake_id,
          inputHash: h.parent.input_hash,
          epoch: h.parent.epoch,
        },
      ],
      [
        {
          ownerId: h.parent.owner_id,
          intakeId: h.parent.intake_id,
          inputHash: h.parent.input_hash,
          epoch: h.parent.epoch,
        },
      ],
    ])
  })

  it.each(
    actualReconciles.map((x) => [x.label] as const),
  )('decodes the complete actual SQL POST case %s without retrying seal or classification', async (label) => {
    const response = structuredClone(
        required(actualReconciles.find((x) => x.label === label)).response,
      ),
      h = frame(response.result),
      rpc = vi.fn<ConversationIntakeRecoveryRPCPort['rpc']>(async () => ({
        data: response,
        error: null,
      })),
      observe = vi.fn<ConversationIntakeScopePort['checkCurrentScope']>(async () => true),
      api = createConversationIntakeRecoveryStore({ rpc }, { checkCurrentScope: observe })
    expect(await api.reconcile(h.bound, h.parent, h.sourceHash, response.result.claim_id)).toEqual(
      response,
    )
    expect(rpc.mock.calls).toEqual([
      [
        'reconcile_conversation_intake_routing',
        {
          p_user_id: h.parent.owner_id,
          p_intake_id: h.parent.intake_id,
          p_input_hash: h.parent.input_hash,
          p_expected_epoch: h.parent.epoch,
          p_source_hash: h.sourceHash,
          p_claim_id: response.result.claim_id,
        },
      ],
    ])
    expect(observe).toHaveBeenCalledTimes(2)
  })

  it('returns a private unsealed null result without repairing or using a client expiry clock', async () => {
    const h = setup('old_pending'),
      raw = { ...h.proof, result: null }
    h.rpc.mockResolvedValue({ data: raw, error: null })
    expect(await h.api.read(h.bound, h.parent, h.sourceHash)).toEqual(raw)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc.mock.calls[0]?.[0]).toBe('read_conversation_intake_routing_result')
  })

  it.each([
    'absent',
    'stale_epoch',
    'input_conflict',
    'source_conflict',
  ] as const)('preserves action-only read refusal %s', async (action) => {
    const h = setup()
    h.rpc.mockResolvedValue({ data: { action }, error: null })
    expect(await h.api.read(h.bound, h.parent, h.sourceHash)).toEqual({ action })
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'absent',
    'stale_epoch',
    'input_conflict',
    'source_conflict',
    'claim_conflict',
    'in_flight',
  ] as const)('preserves action-only reconcile refusal %s', async (action) => {
    const h = setup()
    h.rpc.mockResolvedValue({ data: { action }, error: null })
    expect(await h.api.reconcile(h.bound, h.parent, h.sourceHash, h.proof.claim_id)).toEqual({
      action,
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'reconcile_conversation_intake_routing',
    ])
  })

  it.each([
    [
      'owner',
      (p: ProofFixture) => ({
        ...p,
        intake: { ...p.intake, owner_id: 'c1410000-0000-4000-8000-000000000099' },
      }),
    ],
    [
      'intake',
      (p: ProofFixture) => ({
        ...p,
        intake: { ...p.intake, intake_id: 'c1410000-0000-4000-8000-000000000099' },
      }),
    ],
    [
      'input hash',
      (p: ProofFixture) => ({ ...p, intake: { ...p.intake, input_hash: '0'.repeat(64) } }),
    ],
    [
      'epoch',
      (p: ProofFixture) => ({
        ...p,
        intake: { ...p.intake, epoch: 'c1410000-0000-4000-8000-000000000099' },
      }),
    ],
    [
      'admission clock',
      (p: ProofFixture) => ({ ...p, intake: { ...p.intake, admitted_at: '2026-11-01T00:00:00Z' } }),
    ],
    ['source hash', (p: ProofFixture) => ({ ...p, source_hash: '0'.repeat(64) })],
    ['claim UUID', (p: ProofFixture) => ({ ...p, claim_id: 'not-a-claim' })],
    [
      'lease origin',
      (p: ProofFixture) => ({ ...p, lease_clock_origin: 'actual_historical_claim' }),
    ],
    ['nonfinite lease', (p: ProofFixture) => ({ ...p, lease_anchor_at: 'infinity' })],
    [
      'lease before original',
      (p: ProofFixture) => ({ ...p, lease_anchor_at: '2020-01-01T00:00:00Z' }),
    ],
    ['backfill claiming real lease', (p: ProofFixture) => ({ ...p, lease_clock_origin: 'claim' })],
    ['private extra source', (p: ProofFixture) => ({ ...p, context: { source: 'must-not-leak' } })],
    [
      'binding extra',
      (p: ProofFixture) => ({ ...p, intake: { ...p.intake, kind: 'meal.report' } }),
    ],
    [
      'result schema',
      (p: ProofFixture) => ({
        ...p,
        result: { ...required(p.result), schema: 'conversation.workout-effect.v1' },
      }),
    ],
    [
      'result origin',
      (p: ProofFixture) => ({ ...p, result: { ...required(p.result), origin: 'ui-v1' } }),
    ],
    [
      'decision hash',
      (p: ProofFixture) => ({
        ...p,
        result: { ...required(p.result), decision_hash: '0'.repeat(64) },
      }),
    ],
    [
      'decision mismatch',
      (p: ProofFixture) => ({
        ...p,
        result: {
          ...required(p.result),
          decision: { ...required(p.result).decision, reason: 'changed' },
        },
      }),
    ],
    [
      'nonfinite result',
      (p: ProofFixture) => ({ ...p, result: { ...required(p.result), recorded_at: 'infinity' } }),
    ],
    [
      'result before admission',
      (p: ProofFixture) => ({
        ...p,
        result: { ...required(p.result), recorded_at: '2020-01-01T00:00:00Z' },
      }),
    ],
    [
      'result extra',
      (p: ProofFixture) => ({
        ...p,
        result: { ...required(p.result), receipt: { status: 'saved' } },
      }),
    ],
  ] as const)('refuses closed proof violation: %s', async (_label, change) => {
    const h = setup()
    h.rpc.mockResolvedValue({ data: change(h.proof), error: null })
    let caught: unknown
    try {
      await h.api.read(h.bound, h.parent, h.sourceHash)
    } catch (error) {
      caught = error
    }
    expect(caught).toMatchObject({ status: 503, code: 'conversation_intake_unavailable' })
    expect(caught).not.toBeInstanceOf(ConversationIntakeScopeRefusal)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
  })

  it('does not normalize or invent the sealed selected_at before the migration anchor', async () => {
    const h = setup(),
      original = required(h.proof.result).recorded_at
    expect(original < h.proof.lease_anchor_at).toBe(true)
    const result = await h.api.read(h.bound, h.parent, h.sourceHash)
    expect(result).toEqual(h.proof)
    if (result.action !== 'available' || !result.result) throw new Error('Missing actual result')
    expect(result.result.recorded_at).toBe(original)
    expect(result.lease_clock_origin).toBe('migration_backfill')
  })
  it('router clocks cannot precede their actual lease anchor', async () => {
    const h = setup('quota')
    h.rpc.mockResolvedValue({
      data: {
        ...h.proof,
        result: { ...required(h.proof.result), recorded_at: h.parent.admitted_at },
      },
      error: null,
    })
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
  })
  it('an interruption requires the real >=60s result clock and exact technical decision', async () => {
    const h = setup('interrupt'),
      original = required(h.proof.result),
      changed = { ...original.decision, reason: 'routing_complete' }
    for (const result of [
      { ...original, recorded_at: h.proof.lease_anchor_at },
      { ...original, decision: changed, decision_hash: workoutDigest(changed) },
      {
        ...original,
        decision: {
          schema: 'conversation.intake-routing.v1',
          kind: 'workout.report',
          reason: 'routing_interrupted',
        },
        decision_hash: workoutDigest({
          schema: 'conversation.intake-routing.v1',
          kind: 'workout.report',
          reason: 'routing_interrupted',
        }),
      },
    ]) {
      const f = setup('interrupt')
      f.rpc.mockResolvedValue({ data: { ...f.proof, result }, error: null })
      await expect(f.api.read(f.bound, f.parent, f.sourceHash)).rejects.toMatchObject({
        code: 'conversation_intake_unavailable',
      })
    }
  })

  it('POST success cannot claim a missing result, another claim or a router-origin interruption', async () => {
    const response = structuredClone(actualReconciles[0]?.response)
    if (!response) throw new Error('Missing reconcile fixture')
    const h = frame(response.result)
    for (const raw of [
      { ...response, result: { ...response.result, result: null } },
      {
        ...response,
        result: { ...response.result, claim_id: 'c1410000-0000-4000-8000-000000000099' },
      },
      {
        ...response,
        result: {
          ...response.result,
          result: { ...required(response.result.result), origin: 'router' },
        },
      },
      { ...response, decision: required(response.result.result).decision },
    ]) {
      const rpc = vi.fn<ConversationIntakeRecoveryRPCPort['rpc']>(async () => ({
          data: raw,
          error: null,
        })),
        api = createConversationIntakeRecoveryStore(
          { rpc },
          { checkCurrentScope: async () => true },
        )
      await expect(
        api.reconcile(h.bound, h.parent, h.sourceHash, response.result.claim_id),
      ).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
      expect(rpc).toHaveBeenCalledTimes(1)
    }
  })

  it.each([
    'false',
    'throw',
  ] as const)('mandatory pre-observation %s prevents RPC and permanently refuses that request store', async (mode) => {
    const h = setup()
    if (mode === 'false') h.checkCurrentScope.mockResolvedValueOnce(false)
    else h.checkCurrentScope.mockRejectedValueOnce(new Error('Auth lookup failed'))
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toBeInstanceOf(
      ConversationIntakeScopeRefusal,
    )
    h.checkCurrentScope.mockResolvedValue(true)
    await expect(
      h.api.reconcile(h.bound, h.parent, h.sourceHash, h.proof.claim_id),
    ).rejects.toBeInstanceOf(ConversationIntakeScopeRefusal)
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it.each([
    'false',
    'throw',
  ] as const)('mandatory post-observation %s is not an uncertain SDK error or a reason to retry', async (mode) => {
    const h = setup()
    h.checkCurrentScope.mockResolvedValueOnce(true)
    if (mode === 'false') h.checkCurrentScope.mockResolvedValueOnce(false)
    else h.checkCurrentScope.mockRejectedValueOnce(new Error('Admin/mapping/epoch changed'))
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toBeInstanceOf(
      ConversationIntakeScopeRefusal,
    )
    h.checkCurrentScope.mockResolvedValue(true)
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toBeInstanceOf(
      ConversationIntakeScopeRefusal,
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it('an SDK throw still performs the post-check and never calls a recovery writer', async () => {
    const h = setup()
    h.rpc.mockRejectedValue(new Error('Network outcome unknown'))
    await expect(
      h.api.reconcile(h.bound, h.parent, h.sourceHash, h.proof.claim_id),
    ).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'reconcile_conversation_intake_routing',
    ])
  })
  it('a scope denial after an SDK throw retains the internal mandatory refusal class', async () => {
    const h = setup()
    h.rpc.mockRejectedValue(new Error('SDK failed'))
    h.checkCurrentScope.mockResolvedValueOnce(true).mockResolvedValueOnce(false)
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toBeInstanceOf(
      ConversationIntakeScopeRefusal,
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })

  it('clones the SDK proof before the post-observer can poison its source alias', async () => {
    const h = setup(),
      expected = structuredClone(h.proof)
    let pending = false
    h.rpc.mockImplementation(async () => {
      pending = true
      return { data: h.proof, error: null }
    })
    h.checkCurrentScope.mockImplementation(async () => {
      if (pending) {
        pending = false
        h.proof.source_hash = '0'.repeat(64)
      }
      return true
    })
    expect(await h.api.read(h.bound, h.parent, h.sourceHash)).toEqual(expected)
    expect(h.proof.source_hash).not.toBe(expected.source_hash)
  })
  it('does not invoke untrusted SDK getters and still fences the thrown snapshot path', async () => {
    const h = setup()
    let invoked = false
    const envelope = Object.defineProperty({ error: null }, 'data', {
      enumerable: true,
      get() {
        invoked = true
        throw new Error('Getter must not run')
      },
    })
    h.rpc.mockResolvedValue(envelope)
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(invoked).toBe(false)
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it('pins original caller binding/args and immutable scope identity before asynchronous work', async () => {
    const h = setup(),
      originalEpoch = h.parent.epoch
    h.checkCurrentScope.mockImplementation(async (identity) => {
      expect(Object.isFrozen(identity)).toBe(true)
      h.parent = { ...h.parent, epoch: 'c1410000-0000-4000-8000-000000000099' }
      return true
    })
    const rpc = h.rpc.getMockImplementation()
    if (!rpc) throw new Error('Missing RPC')
    h.rpc.mockImplementation(async (name, args) => {
      expect(Object.isFrozen(args)).toBe(true)
      return rpc(name, args)
    })
    expect(await h.api.read(h.bound, h.parent, h.sourceHash)).toEqual(h.proof)
    expect(h.rpc.mock.calls[0]?.[1].p_expected_epoch).toBe(originalEpoch)
  })
  it('pins callback functions with their original receivers', async () => {
    const h = setup(),
      rpcPort = {
        calls: 0,
        async rpc() {
          this.calls++
          return { data: h.proof, error: null }
        },
      },
      scope = {
        calls: 0,
        allowed: true,
        async checkCurrentScope() {
          this.calls++
          return this.allowed
        },
      },
      api = createConversationIntakeRecoveryStore(rpcPort, scope)
    rpcPort.rpc = async () => {
      throw new Error('Replacement callback must not run')
    }
    scope.checkCurrentScope = async () => true
    expect(await api.read(h.bound, h.parent, h.sourceHash)).toEqual(h.proof)
    scope.allowed = false
    await expect(api.read(h.bound, h.parent, h.sourceHash)).rejects.toBeInstanceOf(
      ConversationIntakeScopeRefusal,
    )
    expect(rpcPort.calls).toBe(1)
    expect(scope.calls).toBe(3)
  })

  it.each([
    null,
    { error: null },
    { data: null, error: null },
    { data: { action: 'absent' } },
    { data: { action: 'absent' }, error: undefined },
    { data: { action: 'absent' }, error: { code: '40001' } },
    { data: { action: 'absent', private: 'extra' }, error: null },
  ])('rejects malformed/error SDK envelope without retry %#', async (envelope) => {
    const h = setup()
    h.rpc.mockResolvedValue(envelope)
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
  })
  it('rejects inconsistent original arguments before any RPC or asserted authority', async () => {
    const h = setup()
    await expect(
      h.api.read(
        h.bound,
        { ...h.parent, owner_id: 'c1410000-0000-4000-8000-000000000099' },
        h.sourceHash,
      ),
    ).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    await expect(h.api.read(h.bound, h.parent, 'not-source')).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    await expect(
      h.api.reconcile(h.bound, h.parent, h.sourceHash, 'not-claim'),
    ).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.checkCurrentScope).not.toHaveBeenCalled()
  })

  it('never masks a latched mandatory refusal with later malformed recovery arguments', async () => {
    const h = setup()
    h.checkCurrentScope.mockResolvedValueOnce(false)
    await expect(h.api.read(h.bound, h.parent, h.sourceHash)).rejects.toBeInstanceOf(
      ConversationIntakeScopeRefusal,
    )
    h.checkCurrentScope.mockResolvedValue(true)
    await expect(
      h.api.reconcile(h.bound, h.parent, h.sourceHash, 'unknown-claim'),
    ).rejects.toBeInstanceOf(ConversationIntakeScopeRefusal)
    await expect(
      h.api.read(h.bound, { ...h.parent, owner_id: 'bad-owner' }, h.sourceHash),
    ).rejects.toBeInstanceOf(ConversationIntakeScopeRefusal)
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(1)
  })
})
