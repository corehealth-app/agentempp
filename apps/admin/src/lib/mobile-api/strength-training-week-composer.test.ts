import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { acquireStrengthWeekTarget } from './strength-training-week-composer'
import {
  createStrengthWeekRepository,
  type StrengthWeekProposal,
  type StrengthWeekSourceProof,
  type StrengthWeekTarget,
} from './strength-training-week-service'

const owner = 'a3000000-0000-4000-8000-000000000001'
const generation = 'a3000000-0000-4000-8000-000000000002'
const planId = 'a3000000-0000-4000-8000-000000000003'
const frequencyId = 'a3000000-0000-4000-8000-000000000004'
const week = '2026-10-12'
const zone = 'America/Sao_Paulo'
const proof: StrengthWeekSourceProof = {
  plan: { coverage: 'covered', source_version_id: planId, source_order: '9007199254740993' },
  frequency: {
    coverage: 'covered',
    source_version_id: frequencyId,
    source_order: '9007199254740994',
  },
}

function read() {
  const receipt = {
    user_id: owner,
    generation,
    observed_at: '2026-10-08T12:00:00.123456Z',
    observed_timezone: zone,
    effective_week_start: week,
  }
  return {
    status: 'ready',
    context: {
      kind: 'source_facts',
      user_id: owner,
      generation,
      timezone: zone,
      week_start: week,
      week_start_at: '2026-10-12T03:00:00.000000Z',
      observed_at: '2026-10-14T12:00:00.123456Z',
      source_proof: proof,
      plan: {
        coverage: 'covered',
        receipt: {
          ...receipt,
          source_kind: 'accepted_plan',
          fact: 'value',
          planned_days: 3,
          source_version_id: planId,
          source_entity_id: 'a3000000-0000-4000-8000-000000000005',
          source_order: '9007199254740993',
          source_valid_until: '2026-11-19T12:00:00.123456Z',
        },
      },
      frequency: {
        coverage: 'covered',
        receipt: {
          ...receipt,
          source_kind: 'informed_frequency',
          fact: 'value',
          planned_days: 4,
          source_version_id: frequencyId,
          source_entity_id: null,
          source_order: '9007199254740994',
          source_valid_until: null,
        },
      },
    },
  }
}

function target(
  proposal: StrengthWeekProposal = {
    source: 'accepted_plan',
    planned_days: 3,
    source_key: planId,
  },
): StrengthWeekTarget {
  return {
    ...proposal,
    target_id: 'a3000000-0000-4000-8000-000000000006',
    user_id: owner,
    generation,
    week_start: week,
    timezone_at_freeze: zone,
    frozen_at: '2026-10-14T12:00:00.123457Z',
    source_proof: structuredClone(proof),
  }
}

function boundary(...outcomes: ({ data: unknown; error: unknown } | Error)[]) {
  const calls: { name: string; parameters: unknown }[] = []
  const client = {
    async rpc(this: unknown, name: string, parameters: unknown) {
      expect(this).toBe(client)
      calls.push({ name, parameters: structuredClone(parameters) })
      const outcome = outcomes.shift()
      if (!outcome) throw new Error('Unexpected RPC or retry')
      if (outcome instanceof Error) throw outcome
      return structuredClone(outcome)
    },
  }
  return {
    repository: createStrengthWeekRepository(client as unknown as ServiceClient, { enabled: true }),
    calls,
  }
}

describe('weekly target acquisition through the real repository, parser and core', () => {
  it('keeps the default OFF gate lazy and performs zero RPCs', async () => {
    const client = Object.defineProperty({}, 'rpc', {
      get() {
        throw new Error('OFF touched RPC')
      },
    })
    const repository = createStrengthWeekRepository(client as ServiceClient)
    await expect(acquireStrengthWeekTarget(repository, owner)).resolves.toEqual({
      status: 'disabled',
    })
  })

  it('returns only the stored target after read, preparation and freeze', async () => {
    const stored = { status: 'frozen', target: target() }
    const b = boundary({ data: read(), error: null }, { data: stored, error: null })
    await expect(acquireStrengthWeekTarget(b.repository, owner)).resolves.toEqual(stored)
    expect(b.calls).toEqual([
      { name: 'get_mobile_strength_week_context', parameters: { p_user_id: owner } },
      {
        name: 'freeze_mobile_strength_week_target',
        parameters: {
          p_user_id: owner,
          p_expected_generation: generation,
          p_expected_timezone: zone,
          p_expected_week_start: week,
          p_source_proof: proof,
          p_proposal: { source: 'accepted_plan', planned_days: 3, source_key: planId },
        },
      },
    ])
  })

  it('returns the CAS winner even when it differs from the earlier proposal', async () => {
    const winner = target({
      source: 'informed_frequency',
      planned_days: 4,
      source_key: frequencyId,
    })
    const stored = { status: 'reused', target: winner }
    const b = boundary({ data: read(), error: null }, { data: stored, error: null })
    await expect(acquireStrengthWeekTarget(b.repository, owner)).resolves.toEqual(stored)
    expect(b.calls).toHaveLength(2)
  })

  it.each([
    'missing_scope',
    'history_incomplete',
    'calendar_unsupported',
  ])('stops unavailable read %s before any freeze', async (reason) => {
    const unavailable = { status: 'unavailable', reason }
    const b = boundary({ data: unavailable, error: null })
    await expect(acquireStrengthWeekTarget(b.repository, owner)).resolves.toEqual(unavailable)
    expect(b.calls).toHaveLength(1)
  })

  it.each([
    'generation_changed',
    'timezone_changed',
    'week_changed',
    'source_proof_changed',
    'proposal_mismatch',
  ])('preserves CAS conflict %s without retrying or publishing a proposal', async (reason) => {
    const conflict = { status: 'conflict', reason }
    const b = boundary({ data: read(), error: null }, { data: conflict, error: null })
    await expect(acquireStrengthWeekTarget(b.repository, owner)).resolves.toEqual(conflict)
    expect(b.calls).toHaveLength(2)
  })

  it.each([
    'missing_scope',
    'history_incomplete',
    'calendar_unsupported',
  ])('preserves unavailable freeze %s without returning the earlier proposal', async (reason) => {
    const unavailable = { status: 'unavailable', reason }
    const b = boundary({ data: read(), error: null }, { data: unavailable, error: null })
    await expect(acquireStrengthWeekTarget(b.repository, owner)).resolves.toEqual(unavailable)
    expect(b.calls).toHaveLength(2)
  })

  it('does not fall back to an observed winner after a reset makes freeze conflict', async () => {
    const original = read().context
    const prior = {
      status: 'ready',
      context: {
        kind: 'existing_target',
        user_id: owner,
        generation,
        timezone: zone,
        week_start: week,
        observed_at: original.observed_at,
        target: { ...target(), frozen_at: original.observed_at },
      },
    }
    const conflict = { status: 'conflict', reason: 'generation_changed' }
    const b = boundary({ data: prior, error: null }, { data: conflict, error: null })
    await expect(acquireStrengthWeekTarget(b.repository, owner)).resolves.toEqual(conflict)
    expect(b.calls).toHaveLength(2)
  })

  it('preserves the selected expired receipt B in the fallback CAS', async () => {
    const initial = read()
    initial.context.plan.receipt.source_valid_until = '2026-10-12T02:59:59.999999Z'
    const stored = {
      status: 'frozen',
      target: target({ source: 'informed_frequency', planned_days: 4, source_key: frequencyId }),
    }
    const b = boundary({ data: initial, error: null }, { data: stored, error: null })
    await expect(acquireStrengthWeekTarget(b.repository, owner)).resolves.toEqual(stored)
    expect(b.calls[1]?.parameters).toMatchObject({
      p_source_proof: proof,
      p_proposal: { source: 'informed_frequency', planned_days: 4, source_key: frequencyId },
    })
  })

  it.each([
    'read',
    'freeze',
  ])('propagates %s failure without retry or stale publication', async (at) => {
    const failure = { data: null, error: { code: 'XX000', message: 'Synthetic database error' } }
    const b = at === 'read' ? boundary(failure) : boundary({ data: read(), error: null }, failure)
    await expect(acquireStrengthWeekTarget(b.repository, owner)).rejects.toMatchObject({
      code: 'strength_week_data_access_failed',
    })
    expect(b.calls).toHaveLength(at === 'read' ? 1 : 2)
  })
})
