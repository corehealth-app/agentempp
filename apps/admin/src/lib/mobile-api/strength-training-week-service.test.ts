import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import {
  createStrengthWeekRepository,
  type StrengthWeekFreezeInput,
  type StrengthWeekRepository,
  type StrengthWeekRpc,
  type StrengthWeekRpcResponse,
  type StrengthWeekSourceProof,
  type StrengthWeekTarget,
} from './strength-training-week-service'

// Test-first source only. The future service is imported directly; no parser/core is mocked.
// RPC fixtures assert repository contracts, never real SQL locks/calendar/durability.
const owner = 'a1000000-0000-4000-8000-000000000001'
const otherOwner = 'a1000000-0000-4000-8000-000000000002'
const generation = 'b2000000-0000-4000-8000-000000000001'
const otherGeneration = 'b2000000-0000-4000-8000-000000000002'
const planID = 'c3000000-0000-4000-8000-000000000001'
const frequencyID = 'c3000000-0000-4000-8000-000000000002'
const staleID = 'c3000000-0000-4000-8000-000000000003'
const entityID = 'd4000000-0000-4000-8000-000000000001'
const targetID = 'e5000000-0000-4000-8000-000000000001'
const week = '2026-10-12'
const timezone = 'America/Sao_Paulo'
const observed = '2026-10-14T18:20:30.123456Z'
const frozen = '2026-10-14T18:20:30.123457Z'
const planOrder = '9007199254740993'
const frequencyOrder = '9007199254740994'

function proof(): StrengthWeekSourceProof {
  return {
    plan: { coverage: 'covered', source_version_id: planID, source_order: planOrder },
    frequency: { coverage: 'unknown' },
  }
}
function bothProof(): StrengthWeekSourceProof {
  return {
    plan: { coverage: 'covered', source_version_id: planID, source_order: planOrder },
    frequency: {
      coverage: 'covered',
      source_version_id: frequencyID,
      source_order: frequencyOrder,
    },
  }
}
function input(): StrengthWeekFreezeInput {
  return {
    userId: owner,
    expectedGeneration: generation,
    expectedTimezone: timezone,
    expectedWeekStart: week,
    sourceProof: proof(),
    proposal: { source: 'accepted_plan', planned_days: 3, source_key: planID },
  }
}
function target(): StrengthWeekTarget {
  return {
    target_id: targetID,
    user_id: owner,
    generation,
    week_start: week,
    timezone_at_freeze: timezone,
    frozen_at: frozen,
    source: 'accepted_plan',
    planned_days: 3,
    source_key: planID,
    source_proof: proof(),
  }
}
function receiptBase(id: string, order: string) {
  return {
    source_version_id: id,
    user_id: owner,
    generation,
    source_order: order,
    observed_at: '2026-10-05T12:00:00.000001Z',
    observed_timezone: timezone,
    effective_week_start: week,
  }
}
function planReceipt() {
  return {
    ...receiptBase(planID, planOrder),
    source_kind: 'accepted_plan' as const,
    fact: 'value' as const,
    planned_days: 3,
    source_entity_id: entityID,
    source_valid_until: null,
  }
}
function frequencyReceipt() {
  return {
    ...receiptBase(frequencyID, frequencyOrder),
    source_kind: 'informed_frequency' as const,
    fact: 'value' as const,
    planned_days: 0,
    source_entity_id: null,
    source_valid_until: null,
  }
}
function planAbsent() {
  return { ...planReceipt(), fact: 'absent' as const, planned_days: null, source_entity_id: null }
}
function contextBase() {
  return { user_id: owner, generation, timezone, week_start: week, observed_at: observed }
}
function readyPlan() {
  return {
    status: 'ready',
    context: {
      ...contextBase(),
      kind: 'source_facts',
      plan: { coverage: 'covered', receipt: planReceipt() },
      frequency: { coverage: 'unknown' },
      source_proof: proof(),
    },
  }
}
function readyFrequency() {
  return {
    status: 'ready',
    context: {
      ...contextBase(),
      kind: 'source_facts',
      plan: { coverage: 'covered', receipt: planAbsent() },
      frequency: { coverage: 'covered', receipt: frequencyReceipt() },
      source_proof: bothProof(),
    },
  }
}
function readyAbsent() {
  const data = readyFrequency()
  return {
    ...data,
    context: {
      ...data.context,
      frequency: {
        coverage: 'covered',
        receipt: { ...frequencyReceipt(), fact: 'absent', planned_days: null },
      },
    },
  }
}
function readyExisting() {
  return {
    status: 'ready',
    context: { ...contextBase(), kind: 'existing_target', target: target() },
  }
}
function frequencyInput(): StrengthWeekFreezeInput {
  return {
    ...input(),
    sourceProof: bothProof(),
    proposal: { source: 'informed_frequency', planned_days: 0, source_key: frequencyID },
  }
}
function absentInput(): StrengthWeekFreezeInput {
  return {
    ...input(),
    sourceProof: bothProof(),
    proposal: { source: 'absent', planned_days: null, source_key: null },
  }
}
function targetFor(value: StrengthWeekFreezeInput): StrengthWeekTarget {
  return { ...target(), ...value.proposal, source_proof: structuredClone(value.sourceProof) }
}

type RpcCall = { name: string; parameters: unknown }
type RpcOutcome = StrengthWeekRpcResponse | { rejection: unknown }
function rpcBoundary(outcome: RpcOutcome) {
  const calls: RpcCall[] = []
  const rpc = vi.fn(function (this: unknown, name: string, parameters: unknown) {
    expect(this).toBe(surface)
    calls.push({ name, parameters: structuredClone(parameters) })
    if (calls.length > 1) throw new Error('Unexpected second RPC; no implicit retry is allowed')
    if ('rejection' in outcome) return Promise.reject(outcome.rejection)
    return Promise.resolve(structuredClone(outcome))
  })
  const surface = { rpc: rpc satisfies StrengthWeekRpc }
  // Sole SDK adaptation: only the typed external RPC response is faked.
  return { client: surface as unknown as ServiceClient, rpc, calls }
}
function success(data: unknown) {
  return rpcBoundary({ data, error: null })
}
function enabled(client: ServiceClient): StrengthWeekRepository {
  return createStrengthWeekRepository(client, { enabled: true })
}
function expectedFreezeCall(value: StrengthWeekFreezeInput) {
  return {
    name: 'freeze_mobile_strength_week_target',
    parameters: {
      p_user_id: value.userId,
      p_expected_generation: value.expectedGeneration,
      p_expected_timezone: value.expectedTimezone,
      p_expected_week_start: value.expectedWeekStart,
      p_source_proof: value.sourceProof,
      p_proposal: value.proposal,
    },
  }
}
async function apiError(pending: Promise<unknown>, status: number, code: string, message: string) {
  let failure: unknown
  try {
    await pending
  } catch (error) {
    failure = error
  }
  expect(failure).toBeInstanceOf(MobileApiError)
  if (!(failure instanceof MobileApiError)) throw new Error('Expected MobileApiError rejection')
  expect({ status: failure.status, code: failure.code, message: failure.message }).toEqual({
    status,
    code,
    message,
  })
  expect(failure.details).toBeUndefined()
}
function invalidInput(pending: Promise<unknown>) {
  return apiError(pending, 422, 'strength_week_invalid_input', 'Invalid strength week input')
}
function invalidResponse(pending: Promise<unknown>) {
  return apiError(pending, 500, 'strength_week_invalid_response', 'Invalid strength week response')
}
// Invalid-wire fixture edits only; production parsing is always real.
function edit(source: unknown, path: string, value: unknown, remove = false): unknown {
  const copy: unknown = structuredClone(source)
  const keys = path.split('.')
  const last = keys.pop()
  let cursor = copy
  for (const key of keys) {
    if (typeof cursor !== 'object' || cursor === null || Array.isArray(cursor)) {
      throw new Error('Invalid fixture path: ' + path)
    }
    cursor = (cursor as Record<string, unknown>)[key]
  }
  if (
    last === undefined ||
    typeof cursor !== 'object' ||
    cursor === null ||
    Array.isArray(cursor)
  ) {
    throw new Error('Invalid fixture leaf: ' + path)
  }
  if (remove) delete (cursor as Record<string, unknown>)[last]
  else (cursor as Record<string, unknown>)[last] = value
  return copy
}
type WireMutation = {
  name: string
  base: () => unknown
  path: string
  value?: unknown
  remove?: boolean
}

const malformedReads: readonly WireMutation[] = [
  { name: 'top-level extra', base: readyPlan, path: 'debug', value: true },
  { name: 'context extra', base: readyPlan, path: 'context.profile', value: {} },
  {
    name: 'context required field missing',
    base: readyPlan,
    path: 'context.observed_at',
    remove: true,
  },
  { name: 'context array', base: readyPlan, path: 'context', value: [] },
  { name: 'unknown context kind', base: readyPlan, path: 'context.kind', value: 'current' },
  { name: 'foreign context owner', base: readyPlan, path: 'context.user_id', value: otherOwner },
  {
    name: 'uppercase UUID',
    base: readyPlan,
    path: 'context.generation',
    value: generation.toUpperCase(),
  },
  { name: 'invalid UUID', base: readyPlan, path: 'context.generation', value: 'generation' },
  {
    name: 'non-Monday context date',
    base: readyPlan,
    path: 'context.week_start',
    value: '2026-10-13',
  },
  {
    name: 'invalid civil context date',
    base: readyPlan,
    path: 'context.week_start',
    value: '2026-02-30',
  },
  { name: 'empty timezone', base: readyPlan, path: 'context.timezone', value: '' },
  {
    name: 'milliseconds lose wire precision',
    base: readyPlan,
    path: 'context.observed_at',
    value: '2026-10-14T18:20:30.123Z',
  },
  {
    name: 'invalid timestamp date',
    base: readyPlan,
    path: 'context.observed_at',
    value: '2026-02-30T18:20:30.123456Z',
  },
  {
    name: 'invalid timestamp hour',
    base: readyPlan,
    path: 'context.observed_at',
    value: '2026-10-14T24:20:30.123456Z',
  },
  {
    name: 'invalid timestamp minute',
    base: readyPlan,
    path: 'context.observed_at',
    value: '2026-10-14T18:60:30.123456Z',
  },
  {
    name: 'invalid timestamp second',
    base: readyPlan,
    path: 'context.observed_at',
    value: '2026-10-14T18:20:60.123456Z',
  },
  {
    name: 'offset timestamp is not wire UTC',
    base: readyPlan,
    path: 'context.observed_at',
    value: '2026-10-14T18:20:30.123456+00:00',
  },
  { name: 'unknown coverage', base: readyPlan, path: 'context.plan.coverage', value: 'known' },
  {
    name: 'unknown coverage with receipt',
    base: readyPlan,
    path: 'context.frequency.receipt',
    value: frequencyReceipt(),
  },
  {
    name: 'covered fact without receipt',
    base: readyPlan,
    path: 'context.plan.receipt',
    remove: true,
  },
  { name: 'source fact extra', base: readyPlan, path: 'context.plan.extra', value: true },
  {
    name: 'receipt extra',
    base: readyPlan,
    path: 'context.plan.receipt.photo_url',
    value: 'synthetic-private',
  },
  {
    name: 'receipt foreign owner',
    base: readyPlan,
    path: 'context.plan.receipt.user_id',
    value: otherOwner,
  },
  {
    name: 'receipt foreign generation',
    base: readyPlan,
    path: 'context.plan.receipt.generation',
    value: otherGeneration,
  },
  {
    name: 'receipt wrong source category',
    base: readyPlan,
    path: 'context.plan.receipt.source_kind',
    value: 'informed_frequency',
  },
  {
    name: 'receipt unknown category',
    base: readyPlan,
    path: 'context.plan.receipt.source_kind',
    value: 'photos',
  },
  {
    name: 'receipt unknown fact',
    base: readyPlan,
    path: 'context.plan.receipt.fact',
    value: 'unknown',
  },
  {
    name: 'plan coerced number',
    base: readyPlan,
    path: 'context.plan.receipt.planned_days',
    value: '3',
  },
  {
    name: 'plan zero invalid producer',
    base: readyPlan,
    path: 'context.plan.receipt.planned_days',
    value: 0,
  },
  { name: 'plan fraction', base: readyPlan, path: 'context.plan.receipt.planned_days', value: 3.5 },
  {
    name: 'plan over producer range',
    base: readyPlan,
    path: 'context.plan.receipt.planned_days',
    value: 8,
  },
  {
    name: 'plan numeric null',
    base: readyPlan,
    path: 'context.plan.receipt.planned_days',
    value: null,
  },
  {
    name: 'plan value missing entity',
    base: readyPlan,
    path: 'context.plan.receipt.source_entity_id',
    value: null,
  },
  {
    name: 'plan absent retains entity',
    base: readyFrequency,
    path: 'context.plan.receipt.source_entity_id',
    value: entityID,
  },
  {
    name: 'plan absent retains number',
    base: readyFrequency,
    path: 'context.plan.receipt.planned_days',
    value: 3,
  },
  {
    name: 'frequency wrong source category',
    base: readyFrequency,
    path: 'context.frequency.receipt.source_kind',
    value: 'accepted_plan',
  },
  {
    name: 'frequency foreign owner',
    base: readyFrequency,
    path: 'context.frequency.receipt.user_id',
    value: otherOwner,
  },
  {
    name: 'frequency foreign generation',
    base: readyFrequency,
    path: 'context.frequency.receipt.generation',
    value: otherGeneration,
  },
  {
    name: 'frequency negative',
    base: readyFrequency,
    path: 'context.frequency.receipt.planned_days',
    value: -1,
  },
  {
    name: 'frequency over producer range',
    base: readyFrequency,
    path: 'context.frequency.receipt.planned_days',
    value: 8,
  },
  {
    name: 'frequency coerced zero',
    base: readyFrequency,
    path: 'context.frequency.receipt.planned_days',
    value: '0',
  },
  {
    name: 'frequency value has plan entity',
    base: readyFrequency,
    path: 'context.frequency.receipt.source_entity_id',
    value: entityID,
  },
  {
    name: 'frequency value has plan validity',
    base: readyFrequency,
    path: 'context.frequency.receipt.source_valid_until',
    value: observed,
  },
  {
    name: 'receipt future effective Monday',
    base: readyPlan,
    path: 'context.plan.receipt.effective_week_start',
    value: '2026-10-19',
  },
  {
    name: 'receipt non-Monday',
    base: readyPlan,
    path: 'context.plan.receipt.effective_week_start',
    value: '2026-10-11',
  },
  {
    name: 'required plan foreign zone',
    base: readyPlan,
    path: 'context.plan.receipt.observed_timezone',
    value: 'Asia/Tokyo',
  },
  {
    name: 'required frequency foreign zone',
    base: readyFrequency,
    path: 'context.frequency.receipt.observed_timezone',
    value: 'Asia/Tokyo',
  },
  {
    name: 'required selected plan finite validity',
    base: readyPlan,
    path: 'context.plan.receipt.source_valid_until',
    value: observed,
  },
  { name: 'proof extra', base: readyPlan, path: 'context.source_proof.actor', value: owner },
  {
    name: 'proof entry extra',
    base: readyPlan,
    path: 'context.source_proof.plan.extra',
    value: true,
  },
  {
    name: 'unknown proof with ID',
    base: readyPlan,
    path: 'context.source_proof.frequency.source_version_id',
    value: frequencyID,
  },
  {
    name: 'proof receipt ID mismatch',
    base: readyPlan,
    path: 'context.source_proof.plan.source_version_id',
    value: frequencyID,
  },
  {
    name: 'proof receipt order mismatch above safe integer',
    base: readyPlan,
    path: 'context.source_proof.plan.source_order',
    value: '9007199254740992',
  },
  {
    name: 'proof covered with absent receipt fact',
    base: readyPlan,
    path: 'context.source_proof.frequency',
    value: { coverage: 'covered', source_version_id: frequencyID, source_order: frequencyOrder },
  },
  {
    name: 'proof unknown with covered receipt',
    base: readyPlan,
    path: 'context.source_proof.plan',
    value: { coverage: 'unknown' },
  },
  {
    name: 'existing target foreign owner',
    base: readyExisting,
    path: 'context.target.user_id',
    value: otherOwner,
  },
  {
    name: 'existing target foreign generation',
    base: readyExisting,
    path: 'context.target.generation',
    value: otherGeneration,
  },
  {
    name: 'existing target different Monday',
    base: readyExisting,
    path: 'context.target.week_start',
    value: '2026-10-19',
  },
  {
    name: 'existing target extra',
    base: readyExisting,
    path: 'context.target.internal',
    value: {},
  },
  {
    name: 'existing target source key not its proof',
    base: readyExisting,
    path: 'context.target.source_key',
    value: staleID,
  },
  {
    name: 'existing target accepted plan without proof',
    base: readyExisting,
    path: 'context.target.source_proof.plan',
    value: { coverage: 'unknown' },
  },
  {
    name: 'ready higher source coverage unknown',
    base: readyPlan,
    path: 'context.plan',
    value: { coverage: 'unknown' },
  },
  {
    name: 'ready required lower source coverage unknown',
    base: readyFrequency,
    path: 'context.frequency',
    value: { coverage: 'unknown' },
  },
]

const malformedTargets: readonly {
  name: string
  path: string
  value?: unknown
  remove?: boolean
}[] = [
  { name: 'target missing', path: 'target', remove: true },
  { name: 'target array', path: 'target', value: [] },
  { name: 'result extra', path: 'metadata', value: {} },
  { name: 'target extra', path: 'target.profile', value: {} },
  { name: 'owner mismatch', path: 'target.user_id', value: otherOwner },
  { name: 'generation mismatch', path: 'target.generation', value: otherGeneration },
  { name: 'week mismatch', path: 'target.week_start', value: '2026-10-19' },
  { name: 'week invalid Monday', path: 'target.week_start', value: '2026-10-13' },
  { name: 'target malformed ID', path: 'target.target_id', value: 'target' },
  { name: 'target uppercase ID', path: 'target.target_id', value: targetID.toUpperCase() },
  {
    name: 'target invalid frozen calendar date',
    path: 'target.frozen_at',
    value: '2026-02-29T18:20:30.123456Z',
  },
  {
    name: 'target timestamp loses micros',
    path: 'target.frozen_at',
    value: '2026-10-14T18:20:30.123Z',
  },
  { name: 'target empty timezone', path: 'target.timezone_at_freeze', value: '' },
  { name: 'unknown source', path: 'target.source', value: 'profile' },
  { name: 'coerced days', path: 'target.planned_days', value: '3' },
  { name: 'fractional days', path: 'target.planned_days', value: 3.5 },
  { name: 'invalid plan zero', path: 'target.planned_days', value: 0 },
  { name: 'invalid plan above producer range', path: 'target.planned_days', value: 8 },
  { name: 'source key not selected proof', path: 'target.source_key', value: staleID },
  { name: 'source key null for numeric', path: 'target.source_key', value: null },
  {
    name: 'selected proof unknown',
    path: 'target.source_proof.plan',
    value: { coverage: 'unknown' },
  },
  { name: 'proof extra key', path: 'target.source_proof.extra', value: true },
  { name: 'proof covered entry extra', path: 'target.source_proof.plan.extra', value: true },
  { name: 'proof unknown entry extra', path: 'target.source_proof.frequency.extra', value: true },
]

const invalidFreezeInputs: readonly {
  name: string
  path: string
  value?: unknown
  remove?: boolean
}[] = [
  { name: 'missing expected generation', path: 'expectedGeneration', remove: true },
  { name: 'null expected generation', path: 'expectedGeneration', value: null },
  {
    name: 'uppercase expected generation',
    path: 'expectedGeneration',
    value: generation.toUpperCase(),
  },
  { name: 'invalid owner', path: 'userId', value: '' },
  { name: 'input extra clock override', path: 'observedAt', value: observed },
  { name: 'empty expected timezone', path: 'expectedTimezone', value: '' },
  { name: 'invalid expected date', path: 'expectedWeekStart', value: '2026-02-30' },
  { name: 'non-Monday expected date', path: 'expectedWeekStart', value: '2026-10-13' },
  { name: 'proposal extra', path: 'proposal.extra', value: true },
  { name: 'proposal unknown source', path: 'proposal.source', value: 'manual' },
  { name: 'proposal plan zero', path: 'proposal.planned_days', value: 0 },
  { name: 'proposal plan negative', path: 'proposal.planned_days', value: -1 },
  { name: 'proposal plan over range', path: 'proposal.planned_days', value: 8 },
  { name: 'proposal coerced days', path: 'proposal.planned_days', value: '3' },
  { name: 'proposal fraction', path: 'proposal.planned_days', value: 1.5 },
  { name: 'proposal plan null key', path: 'proposal.source_key', value: null },
  { name: 'source proof array', path: 'sourceProof', value: [] },
  { name: 'source proof extra', path: 'sourceProof.profile', value: {} },
  { name: 'proof unknown with order', path: 'sourceProof.frequency.source_order', value: '1' },
  { name: 'proof covered missing ID', path: 'sourceProof.plan.source_version_id', remove: true },
  { name: 'proof covered extra', path: 'sourceProof.plan.extra', value: true },
]

const invalidOrders = [
  0,
  1,
  9007199254740992,
  '',
  '0',
  '-1',
  '+1',
  '01',
  '1.0',
  '1e3',
  ' 1',
  '9223372036854775808',
] as const
const invalidReadIDs = [
  '',
  'not-a-uuid',
  owner.toUpperCase(),
  owner.replaceAll('-', ''),
  null,
  undefined,
  1,
] as const
const unavailableReasons = ['missing_scope', 'history_incomplete', 'calendar_unsupported'] as const
const conflictReasons = [
  'generation_changed',
  'timezone_changed',
  'week_changed',
  'source_proof_changed',
  'proposal_mismatch',
] as const
const operations = ['read', 'freeze'] as const

function invoke(repository: StrengthWeekRepository, operation: (typeof operations)[number]) {
  return operation === 'read' ? repository.readContext(owner) : repository.compareAndFreeze(input())
}
function expectOneCall(
  boundary: ReturnType<typeof rpcBoundary>,
  operation: (typeof operations)[number],
) {
  expect(boundary.calls).toEqual(
    operation === 'read'
      ? [{ name: 'get_mobile_strength_week_context', parameters: { p_user_id: owner } }]
      : [expectedFreezeCall(input())],
  )
}

describe('dormant strength-week repository', () => {
  it.each([
    undefined,
    {},
    { enabled: false },
  ] as const)('OFF is lazy at construction and both methods: %j', async (options) => {
    let rpcReads = 0
    let inputReads = 0
    const client = Object.defineProperty({}, 'rpc', {
      get() {
        rpcReads++
        throw new Error('OFF touched RPC')
      },
    })
    const poison = Object.defineProperty({}, 'userId', {
      get() {
        inputReads++
        throw new Error('OFF touched input')
      },
    })
    const repository: StrengthWeekRepository = createStrengthWeekRepository(
      client as ServiceClient,
      options,
    )
    expect(rpcReads).toBe(0)
    await expect(repository.readContext(undefined as unknown as string)).resolves.toEqual({
      status: 'disabled',
    })
    await expect(repository.compareAndFreeze(poison as StrengthWeekFreezeInput)).resolves.toEqual({
      status: 'disabled',
    })
    await expect(
      repository.compareAndFreeze(null as unknown as StrengthWeekFreezeInput),
    ).resolves.toEqual({ status: 'disabled' })
    expect({ rpcReads, inputReads }).toEqual({ rpcReads: 0, inputReads: 0 })
  })

  it('factory ON is lazy; read uses only its public one-argument RPC and preserves all opaque strings', async () => {
    const wire = readyPlan()
    const boundary = success(wire)
    const repository = enabled(boundary.client)
    expect(boundary.calls).toEqual([])
    await expect(repository.readContext(owner)).resolves.toEqual(wire)
    expectOneCall(boundary, 'read')
  })

  it.each(invalidReadIDs)('ON rejects malformed read owner %j before any RPC', async (id) => {
    const boundary = success(readyPlan())
    await invalidInput(enabled(boundary.client).readContext(id as string))
    expect(boundary.calls).toEqual([])
  })
  it.each([
    '\u0000',
    '\u001f',
    '\u007f',
  ])('rejects embedded control character %# in input and returned timezone', async (control) => {
    const zone = 'America/' + control + 'Sao_Paulo'
    const inputBoundary = success({ status: 'frozen', target: target() })
    await invalidInput(
      enabled(inputBoundary.client).compareAndFreeze({ ...input(), expectedTimezone: zone }),
    )
    expect(inputBoundary.calls).toEqual([])
    const outputBoundary = success(edit(readyPlan(), 'context.timezone', zone))
    await invalidResponse(enabled(outputBoundary.client).readContext(owner))
    expectOneCall(outputBoundary, 'read')
  })
  it.each(invalidFreezeInputs)('ON rejects $name before any RPC', async ({
    path,
    value,
    remove,
  }) => {
    const boundary = success({ status: 'frozen', target: target() })
    await invalidInput(
      enabled(boundary.client).compareAndFreeze(
        edit(input(), path, value, remove) as StrengthWeekFreezeInput,
      ),
    )
    expect(boundary.calls).toEqual([])
  })
  it.each([
    null,
    undefined,
    [],
    'input',
  ] as const)('ON rejects nonobject freeze input %j without RPC', async (value) => {
    const boundary = success({ status: 'frozen', target: target() })
    await invalidInput(
      enabled(boundary.client).compareAndFreeze(value as unknown as StrengthWeekFreezeInput),
    )
    expect(boundary.calls).toEqual([])
  })
  it.each(
    invalidOrders,
  )('ON refuses noncanonical/unsafe input order %j before RPC', async (order) => {
    const boundary = success({ status: 'frozen', target: target() })
    await invalidInput(
      enabled(boundary.client).compareAndFreeze(
        edit(input(), 'sourceProof.plan.source_order', order) as StrengthWeekFreezeInput,
      ),
    )
    expect(boundary.calls).toEqual([])
  })

  it.each([
    ['accepted plan', input],
    ['frequency zero', frequencyInput],
    ['explicit absence', absentInput],
  ] as const)('freeze %s uses exactly six wire parameters and equals the exact committed proposal/proof', async (_name, makeInput) => {
    const request = makeInput()
    const wire = { status: 'frozen', target: targetFor(request) }
    const boundary = success(wire)
    await expect(enabled(boundary.client).compareAndFreeze(request)).resolves.toEqual(wire)
    expect(boundary.calls).toEqual([expectedFreezeCall(request)])
  })

  it.each([
    readyPlan,
    readyFrequency,
    readyAbsent,
    readyExisting,
  ])('accepts the complete strict read union fixture %#', async (make) => {
    const wire = make()
    const boundary = success(wire)
    await expect(enabled(boundary.client).readContext(owner)).resolves.toEqual(wire)
    expectOneCall(boundary, 'read')
  })
  it('accepts lower foreign-zone frequency when the selected plan makes that kind unnecessary', async () => {
    const wire = readyPlan()
    const lower = { ...frequencyReceipt(), observed_timezone: 'Asia/Tokyo' }
    const response = {
      ...wire,
      context: {
        ...wire.context,
        frequency: { coverage: 'covered', receipt: lower },
        source_proof: bothProof(),
      },
    }
    const boundary = success(response)
    await expect(enabled(boundary.client).readContext(owner)).resolves.toEqual(response)
    expectOneCall(boundary, 'read')
  })
  it('keeps existing target freeze timezone even when the current official context timezone changed', async () => {
    const base = readyExisting()
    const wire = {
      ...base,
      context: {
        ...base.context,
        target: { ...base.context.target, timezone_at_freeze: 'Pacific/Honolulu' },
      },
    }
    const boundary = success(wire)
    await expect(enabled(boundary.client).readContext(owner)).resolves.toEqual(wire)
    expectOneCall(boundary, 'read')
  })
  it('preserves distinct adjacent >2^53 orders and full PostgreSQL bigint maximum without numeric conversion', async () => {
    const wire = readyFrequency()
    const max = '9223372036854775807'
    wire.context.frequency.receipt.source_order = max
    wire.context.source_proof = {
      plan: { coverage: 'covered', source_version_id: planID, source_order: planOrder },
      frequency: { coverage: 'covered', source_version_id: frequencyID, source_order: max },
    }
    const boundary = success(wire)
    const result = await enabled(boundary.client).readContext(owner)
    expect(result).toEqual(wire)
    expect(JSON.stringify(result)).toContain('9007199254740993')
    expect(JSON.stringify(result)).toContain('9223372036854775807')
    expectOneCall(boundary, 'read')
  })
  it.each([
    ['source_version_id', planID],
    ['source_order', planOrder],
  ] as const)('rejects a ready response that aliases the plan and frequency %s', async (field, value) => {
    const wire = edit(readyFrequency(), 'context.frequency.receipt.' + field, value)
    const boundary = success(edit(wire, 'context.source_proof.frequency.' + field, value))
    await invalidResponse(enabled(boundary.client).readContext(owner))
    expectOneCall(boundary, 'read')
  })
  it.each([
    ['source_version_id', planID],
    ['source_order', planOrder],
  ] as const)('rejects a reused winner that aliases its two source %s values', async (field, value) => {
    const winner = { ...target(), source_proof: bothProof() }
    const boundary = success(
      edit({ status: 'reused', target: winner }, 'target.source_proof.frequency.' + field, value),
    )
    await invalidResponse(enabled(boundary.client).compareAndFreeze(input()))
    expectOneCall(boundary, 'freeze')
  })
  it('accepts a real leap-day timestamp preserving its six microsecond digits', async () => {
    const base = readyExisting()
    const wire = {
      ...base,
      context: {
        ...base.context,
        target: { ...base.context.target, frozen_at: '2024-02-29T23:59:59.000001Z' },
      },
    }
    const boundary = success(wire)
    await expect(enabled(boundary.client).readContext(owner)).resolves.toEqual(wire)
    expectOneCall(boundary, 'read')
  })

  it.each([
    [
      'plan unknown with matching unknown proof',
      () => {
        const wire = readyPlan()
        return {
          ...wire,
          context: {
            ...wire.context,
            plan: { coverage: 'unknown' },
            source_proof: { plan: { coverage: 'unknown' }, frequency: { coverage: 'unknown' } },
          },
        }
      },
    ],
    [
      'required frequency unknown with matching unknown proof',
      () => {
        const wire = readyFrequency()
        return {
          ...wire,
          context: {
            ...wire.context,
            frequency: { coverage: 'unknown' },
            source_proof: {
              plan: wire.context.source_proof.plan,
              frequency: { coverage: 'unknown' },
            },
          },
        }
      },
    ],
  ] as const)('rejects ready/%s even when all returned proof entries agree structurally', async (_name, make) => {
    const boundary = success(make())
    await invalidResponse(enabled(boundary.client).readContext(owner))
    expectOneCall(boundary, 'read')
  })

  it.each(malformedReads)('rejects malformed read: $name after one RPC', async ({
    base,
    path,
    value,
    remove,
  }) => {
    const boundary = success(edit(base(), path, value, remove))
    await invalidResponse(enabled(boundary.client).readContext(owner))
    expectOneCall(boundary, 'read')
  })
  it.each(
    invalidOrders,
  )('rejects invalid receipt order %j rather than coercing or truncating it', async (order) => {
    const wire = edit(readyPlan(), 'context.plan.receipt.source_order', order)
    const boundary = success(edit(wire, 'context.source_proof.plan.source_order', order))
    await invalidResponse(enabled(boundary.client).readContext(owner))
    expectOneCall(boundary, 'read')
  })

  it.each([
    'frozen',
    'reused',
  ] as const)('%s requires the complete owned, self-consistent target', async (status) => {
    const wire = { status, target: target() }
    const boundary = success(wire)
    await expect(enabled(boundary.client).compareAndFreeze(input())).resolves.toEqual(wire)
    expectOneCall(boundary, 'freeze')
  })
  for (const status of ['frozen', 'reused'] as const) {
    it.each(malformedTargets)(
      status + ' rejects $name after one RPC',
      async ({ path, value, remove }) => {
        const boundary = success(edit({ status, target: target() }, path, value, remove))
        await invalidResponse(enabled(boundary.client).compareAndFreeze(input()))
        expectOneCall(boundary, 'freeze')
      },
    )
  }
  it.each([
    ['different proposal value', 'target.planned_days', 4],
    ['different proof order', 'target.source_proof.plan.source_order', '9007199254740994'],
    ['different freeze timezone', 'target.timezone_at_freeze', 'Pacific/Honolulu'],
  ] as const)('frozen rejects $0 despite otherwise valid target syntax', async (_name, path, value) => {
    const boundary = success(edit({ status: 'frozen', target: target() }, path, value))
    await invalidResponse(enabled(boundary.client).compareAndFreeze(input()))
    expectOneCall(boundary, 'freeze')
  })
  it('reused returns the durable winner despite stale well-formed proposal/proof and old freeze timezone', async () => {
    const stale: StrengthWeekFreezeInput = {
      ...input(),
      sourceProof: {
        plan: { coverage: 'covered', source_version_id: staleID, source_order: '1' },
        frequency: { coverage: 'unknown' },
      },
      proposal: { source: 'accepted_plan', planned_days: 5, source_key: staleID },
    }
    const wire = {
      status: 'reused',
      target: { ...target(), timezone_at_freeze: 'Pacific/Honolulu' },
    }
    const boundary = success(wire)
    await expect(enabled(boundary.client).compareAndFreeze(stale)).resolves.toEqual(wire)
    expect(boundary.calls).toEqual([expectedFreezeCall(stale)])
  })
  it.each([
    [
      'frequency missing higher proof',
      frequencyInput,
      'target.source_proof.plan',
      { coverage: 'unknown' },
    ],
    [
      'absence missing lower proof',
      absentInput,
      'target.source_proof.frequency',
      { coverage: 'unknown' },
    ],
    ['absence has numeric value', absentInput, 'target.planned_days', 0],
    ['absence has source key', absentInput, 'target.source_key', frequencyID],
    ['frequency negative', frequencyInput, 'target.planned_days', -1],
  ] as const)('reused rejects %s using internal consistency even for a stale caller', async (_name, makeInput, path, value) => {
    const request = makeInput()
    const boundary = success(edit({ status: 'reused', target: targetFor(request) }, path, value))
    await invalidResponse(enabled(boundary.client).compareAndFreeze(request))
    expect(boundary.calls).toEqual([expectedFreezeCall(request)])
  })

  for (const operation of operations) {
    it.each(unavailableReasons)(
      operation + ' preserves unavailable/%s with one RPC and no local fabricated fallback',
      async (reason) => {
        const wire = { status: 'unavailable', reason }
        const boundary = success(wire)
        await expect(invoke(enabled(boundary.client), operation)).resolves.toEqual(wire)
        expectOneCall(boundary, operation)
      },
    )
    it.each([
      null,
      undefined,
      [],
      {},
      { data: readyPlan() },
      { status: 'disabled' },
      { status: 'unknown' },
      { status: 'unavailable', reason: 'network_error' },
      { status: 'unavailable', reason: 'calendar_unsupported', context: contextBase() },
    ])(operation + ' rejects malformed/wrong discriminator envelope %#', async (data) => {
      const boundary = success(data)
      await invalidResponse(invoke(enabled(boundary.client), operation))
      expectOneCall(boundary, operation)
    })
  }
  it.each(
    conflictReasons,
  )('freeze passes through conflict/%s without retry/readback', async (reason) => {
    const wire = { status: 'conflict', reason }
    const boundary = success(wire)
    await expect(enabled(boundary.client).compareAndFreeze(input())).resolves.toEqual(wire)
    expectOneCall(boundary, 'freeze')
  })
  it.each([
    { status: 'conflict', reason: 'network_error' },
    { status: 'conflict', reason: 'generation_changed', target: target() },
    readyPlan(),
  ])('freeze rejects invalid conflict/read-only union %#', async (wire) => {
    const boundary = success(wire)
    await invalidResponse(enabled(boundary.client).compareAndFreeze(input()))
    expectOneCall(boundary, 'freeze')
  })
  it.each([
    { status: 'conflict', reason: 'generation_changed' },
    { status: 'frozen', target: target() },
    { status: 'reused', target: target() },
  ])('read rejects freeze-only status %#', async (wire) => {
    const boundary = success(wire)
    await invalidResponse(enabled(boundary.client).readContext(owner))
    expectOneCall(boundary, 'read')
  })

  for (const operation of operations) {
    it.each([
      [
        '22023',
        'invalid_mobile_strength_week_input',
        422,
        'strength_week_invalid_input',
        'Invalid strength week input',
      ],
      [
        'P0002',
        'mobile_strength_week_patient_not_found',
        404,
        'strength_week_patient_not_found',
        'Patient profile not found',
      ],
      [
        '42501',
        'private denied detail',
        403,
        'strength_week_access_denied',
        'Strength week access denied',
      ],
      [
        '40001',
        'private serialization detail',
        409,
        'strength_week_transaction_conflict',
        'Strength week transaction changed; read again',
      ],
      [
        '40P01',
        'private deadlock detail',
        409,
        'strength_week_transaction_conflict',
        'Strength week transaction changed; read again',
      ],
      [
        '55P03',
        'private lock detail',
        409,
        'strength_week_transaction_conflict',
        'Strength week transaction changed; read again',
      ],
      [
        '22023',
        'mobile_strength_week_requires_read_committed',
        500,
        'strength_week_data_access_failed',
        'Strength week lookup failed',
      ],
      [
        '22023',
        'other invalid input',
        500,
        'strength_week_data_access_failed',
        'Strength week lookup failed',
      ],
      [
        'P0002',
        'other missing row',
        500,
        'strength_week_data_access_failed',
        'Strength week lookup failed',
      ],
      [
        '23514',
        'private constraint detail',
        500,
        'strength_week_data_access_failed',
        'Strength week lookup failed',
      ],
      [
        'PGRST202',
        'private config detail',
        500,
        'strength_week_data_access_failed',
        'Strength week lookup failed',
      ],
      [
        undefined,
        'private provider detail',
        500,
        'strength_week_data_access_failed',
        'Strength week lookup failed',
      ],
    ] as const)(
      operation + ' maps provider error %s / %s exactly with no retry or raw details',
      async (code, message, status, expectedCode, expectedMessage) => {
        const boundary = rpcBoundary({
          data: { status: 'unavailable', reason: 'missing_scope' },
          error: { code, message },
        })
        await apiError(
          invoke(enabled(boundary.client), operation),
          status,
          expectedCode,
          expectedMessage,
        )
        expectOneCall(boundary, operation)
      },
    )
    it('' + operation + ' maps network rejection safely after one call without retry', async () => {
      const boundary = rpcBoundary({ rejection: new Error('synthetic private network detail') })
      await apiError(
        invoke(enabled(boundary.client), operation),
        500,
        'strength_week_data_access_failed',
        'Strength week lookup failed',
      )
      expectOneCall(boundary, operation)
    })
  }
})
