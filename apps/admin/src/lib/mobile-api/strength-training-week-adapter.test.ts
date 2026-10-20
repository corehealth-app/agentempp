import { resolveStrengthWeekTarget } from '@mpp/core/strength-training-week'
import { describe, expect, it } from 'vitest'
import {
  prepareStrengthWeekFreeze,
  type StrengthWeekContext,
  type StrengthWeekReadResult,
  type StrengthWeekSourceProof,
} from './strength-training-week-service'

const owner = 'a2000000-0000-4000-8000-000000000001'
const generation = 'a2000000-0000-4000-8000-000000000002'
const planId = 'a2000000-0000-4000-8000-000000000003'
const frequencyId = 'a2000000-0000-4000-8000-000000000004'
const mondayAt = '2026-10-12T03:00:00.000000Z'
const week = '2026-10-12'
const proof: StrengthWeekSourceProof = {
  plan: { coverage: 'covered', source_version_id: planId, source_order: '9007199254740993' },
  frequency: {
    coverage: 'covered',
    source_version_id: frequencyId,
    source_order: '9007199254740995',
  },
}

type SourceContext = Extract<StrengthWeekContext, { kind: 'source_facts' }>
type MutableSourceFixture = { -readonly [Key in keyof SourceContext]: SourceContext[Key] }

function context(validUntil: string | null = mondayAt): MutableSourceFixture {
  const receipt = {
    user_id: owner,
    generation,
    observed_at: '2026-10-08T12:00:00.123456Z',
    observed_timezone: 'America/Sao_Paulo',
    effective_week_start: week,
  }
  return {
    kind: 'source_facts',
    user_id: owner,
    generation,
    timezone: 'America/Sao_Paulo',
    week_start: week,
    week_start_at: mondayAt,
    observed_at: '2026-10-16T18:00:00.123456Z',
    plan: {
      coverage: 'covered',
      receipt: {
        ...receipt,
        source_kind: 'accepted_plan',
        fact: 'value',
        source_version_id: planId,
        source_order: '9007199254740993',
        source_entity_id: 'a2000000-0000-4000-8000-000000000005',
        source_valid_until: validUntil,
        planned_days: 3,
      },
    },
    frequency: {
      coverage: 'covered',
      receipt: {
        ...receipt,
        source_kind: 'informed_frequency',
        fact: 'value',
        source_version_id: frequencyId,
        source_order: '9007199254740995',
        source_entity_id: null,
        source_valid_until: null,
        planned_days: 4,
      },
    },
    source_proof: structuredClone(proof),
  }
}

function prepare(value: StrengthWeekContext) {
  const result = prepareStrengthWeekFreeze({ status: 'ready', context: value })
  expect(result.status).toBe('prepared')
  if (result.status !== 'prepared') throw new Error('Expected freeze preparation')
  return result.input
}

function freezeDeep(value: unknown): void {
  if (value === null || typeof value !== 'object') return
  for (const nested of Object.values(value)) freezeDeep(nested)
  Object.freeze(value)
}

describe('weekly strength adapter uses the real core runtime', () => {
  it('resolves through the package subpath without an alias or mocked core', () => {
    expect(
      resolveStrengthWeekTarget({
        scope: { ownerKey: owner, weekStartDate: week },
        existingRecord: null,
        effectiveSources: null,
      }).status,
    ).toBe('unavailable')
  })

  it.each([
    ['one microsecond before Monday', '2026-10-12T02:59:59.999999Z', 'informed_frequency', 4],
    ['exactly Monday', mondayAt, 'accepted_plan', 3],
    ['one microsecond after Monday', '2026-10-12T03:00:00.000001Z', 'accepted_plan', 3],
    ['Friday after Wednesday expiry', '2026-10-14T03:00:00.000000Z', 'accepted_plan', 3],
    ['42 day finite plan', '2026-11-19T12:00:00.123456Z', 'accepted_plan', 3],
    ['unlimited imported plan', null, 'accepted_plan', 3],
  ])('prepares the official Monday choice: %s', (_label, until, source, days) => {
    const c = context(until)
    const input = prepare(c)
    expect(input).toEqual({
      userId: owner,
      expectedGeneration: generation,
      expectedTimezone: c.timezone,
      expectedWeekStart: week,
      sourceProof: proof,
      proposal: {
        source,
        planned_days: days,
        source_key: source === 'accepted_plan' ? planId : frequencyId,
      },
    })
  })

  it('retains expired B and exact bigint proof without mutating a frozen input', () => {
    const c = context('2026-10-12T02:59:59.999999Z')
    const original = structuredClone(c)
    freezeDeep(c)
    const input = prepare(c)
    expect(input.sourceProof).toEqual(proof)
    expect(input.proposal.source_key).toBe(frequencyId)
    expect(c).toEqual(original)
  })

  it.each(['zero', 'absent'] as const)('keeps %s frequency distinct after expiry', (mode) => {
    const c = context('2026-10-12T02:59:59.999999Z')
    if (c.frequency.coverage !== 'covered') throw new Error('Expected covered fixture')
    c.frequency = {
      coverage: 'covered',
      receipt:
        mode === 'zero'
          ? { ...c.frequency.receipt, fact: 'value', planned_days: 0 }
          : { ...c.frequency.receipt, fact: 'absent', planned_days: null },
    }
    expect(prepare(c).proposal).toEqual({
      source: mode === 'zero' ? 'informed_frequency' : 'absent',
      planned_days: mode === 'zero' ? 0 : null,
      source_key: mode === 'zero' ? frequencyId : null,
    })
  })

  it('accepts a proved plan with unknown lower-priority frequency', () => {
    const c = context()
    c.frequency = { coverage: 'unknown' }
    c.source_proof = { ...proof, frequency: { coverage: 'unknown' } }
    expect(prepare(c).proposal.source).toBe('accepted_plan')
  })

  it.each([
    'missing_scope',
    'history_incomplete',
    'calendar_unsupported',
  ] as const)('preserves unavailable %s without manufacturing an absent proposal', (reason) => {
    const result: StrengthWeekReadResult = { status: 'unavailable', reason }
    expect(prepareStrengthWeekFreeze(result)).toEqual(result)
  })

  it('preserves the disabled gate without a prepared proposal', () => {
    expect(prepareStrengthWeekFreeze({ status: 'disabled' })).toEqual({ status: 'disabled' })
  })

  it.each([
    { source: 'accepted_plan', planned_days: 3, source_key: planId },
    { source: 'informed_frequency', planned_days: 0, source_key: frequencyId },
    { source: 'absent', planned_days: null, source_key: null },
  ] as const)('revalidates a stored $source winner with its original proof', (proposal) => {
    const c = context()
    const target = {
      target_id: 'a2000000-0000-4000-8000-000000000006',
      user_id: owner,
      generation,
      week_start: week,
      timezone_at_freeze: 'America/Sao_Paulo',
      frozen_at: '2026-10-12T12:00:00.123456Z',
      source_proof: proof,
      ...proposal,
    }
    const existing: StrengthWeekContext = {
      kind: 'existing_target',
      user_id: owner,
      generation,
      timezone: 'Asia/Tokyo',
      week_start: week,
      observed_at: c.observed_at,
      target,
    }
    freezeDeep(existing)
    const input = prepare(existing)
    expect(input.expectedTimezone).toBe('Asia/Tokyo')
    expect(input.sourceProof).toEqual(target.source_proof)
    expect(input.proposal).toEqual(proposal)
    expect(target.timezone_at_freeze).toBe('America/Sao_Paulo')
    expect(input).not.toHaveProperty('target')
    expect(input).not.toHaveProperty('frozen_at')
  })

  it('refuses a ready response with missing higher-priority history', () => {
    const c = context()
    c.plan = { coverage: 'unknown' }
    c.source_proof = { ...proof, plan: { coverage: 'unknown' } }
    expect(() => prepare(c)).toThrowError('Invalid strength week response')
  })

  it('refuses an expired plan with unknown frequency, instead of guessing absence', () => {
    const c = context('2026-10-12T02:59:59.999999Z')
    c.frequency = { coverage: 'unknown' }
    c.source_proof = { ...proof, frequency: { coverage: 'unknown' } }
    expect(() => prepare(c)).toThrowError('Invalid strength week response')
  })

  it('refuses a source from a different account before preparing a freeze', () => {
    const c = context()
    if (c.plan.coverage !== 'covered') throw new Error('Expected covered fixture')
    c.plan = {
      coverage: 'covered',
      receipt: { ...c.plan.receipt, user_id: 'a2000000-0000-4000-8000-000000000007' },
    }
    expect(() => prepare(c)).toThrowError('Invalid strength week response')
  })
})
