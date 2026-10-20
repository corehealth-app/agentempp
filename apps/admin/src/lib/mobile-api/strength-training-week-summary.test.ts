import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { readStrengthTrainingWeek } from './strength-training-week-composer'
import {
  createStrengthWeekRepository,
  type StrengthWeekTarget,
} from './strength-training-week-service'

const id = (n: number) => `a6000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const owner = id(1)
const generation = id(2)
const life = id(3)
const monday = '2026-10-12'
const target = (): StrengthWeekTarget => ({
  target_id: id(4),
  user_id: owner,
  generation,
  week_start: monday,
  timezone_at_freeze: 'UTC',
  frozen_at: '2026-10-12T00:00:00.123456Z',
  source: 'accepted_plan',
  planned_days: 3,
  source_key: id(5),
  source_proof: {
    plan: { coverage: 'covered', source_version_id: id(5), source_order: '9007199254740993' },
    frequency: {
      coverage: 'covered',
      source_version_id: id(6),
      source_order: '9223372036854775807',
    },
  },
})
const workout = (n: number, localDate = monday) => ({
  ownerKey: owner,
  workoutKey: id(n),
  localDate,
  state: 'confirmed',
  catalogueCategory: 'musculacao',
  storedStrengthAnswer: null,
})
function available(t = target()) {
  return {
    status: 'available',
    target: t,
    binding: {
      ownerID: owner,
      generation,
      epoch: id(7),
      lifecycleKey: life,
      signupAdmissionID: id(8),
      frequencySourceVersionID: id(9),
      workoutAdmissionID: id(10),
      workoutContentRevision: 0,
      boundAt: '2026-10-11T12:00:00.123456Z',
    },
    calendar: {
      ownerID: owner,
      lifecycleKey: life,
      scopeKey: id(11),
      timeZone: 'UTC',
      weekStartDate: monday,
      asOfLocalDate: '2026-10-14',
    },
    projection: {
      status: 'available',
      workouts: [workout(20), workout(21), workout(22, '2026-10-13')],
    },
    observed_at: '2026-10-14T12:00:00.123457Z',
  }
}
function boundary(...outcomes: ({ data: unknown; error: unknown } | Error)[]) {
  const calls: { name: string; parameters: unknown }[] = []
  const client = {
    async rpc(this: unknown, name: string, parameters: unknown) {
      expect(this).toBe(client)
      calls.push({ name, parameters: structuredClone(parameters) })
      const next = outcomes.shift()
      if (!next) throw new Error('Unexpected RPC or retry')
      if (next instanceof Error) throw next
      return structuredClone(next)
    },
  }
  return {
    calls,
    repository: createStrengthWeekRepository(client as unknown as ServiceClient, { enabled: true }),
  }
}
const full = (raw: unknown = available(), t = target()) =>
  boundary(
    {
      data: {
        status: 'ready',
        context: {
          kind: 'existing_target',
          user_id: owner,
          generation,
          timezone: 'UTC',
          week_start: monday,
          observed_at: '2026-10-14T12:00:00.123456Z',
          target: t,
        },
      },
      error: null,
    },
    { data: { status: 'reused', target: t }, error: null },
    { data: raw, error: null },
  )

function setPath(root: object, path: string, value: unknown): void {
  const keys = path.split('.')
  let cursor: unknown = root
  for (const key of keys.slice(0, -1)) {
    if (cursor === null || typeof cursor !== 'object') throw new Error('Invalid test mutation path')
    cursor = (cursor as Record<string, unknown>)[key]
  }
  if (cursor === null || typeof cursor !== 'object') throw new Error('Invalid test mutation target')
  const key = keys.at(-1)
  if (!key) throw new Error('Empty test mutation path')
  Reflect.set(cursor, key, value)
}

describe('atomic weekly projection and summary', () => {
  it('keeps default OFF lazy for projection and composition', async () => {
    const client = Object.defineProperty({}, 'rpc', {
      get() {
        throw new Error('OFF touched RPC')
      },
    })
    const repository = createStrengthWeekRepository(client as ServiceClient)
    await expect(repository.projectAcquiredTarget(owner, target())).resolves.toEqual({
      status: 'disabled',
    })
    await expect(readStrengthTrainingWeek(repository, owner)).resolves.toEqual({
      status: 'disabled',
    })
  })

  it('acquires, projects once and uses the real core to count unique strength days', async () => {
    const raw = available()
    const b = full(raw)
    const result = await readStrengthTrainingWeek(b.repository, owner)
    expect(result).toMatchObject({
      ...raw,
      summary: {
        status: 'counted',
        completedStrengthDays: 2,
        plannedDays: 3,
        percentage: 67,
        targetSource: 'accepted_plan',
        targetAvailability: 'available',
        countedLocalDates: [monday, '2026-10-13'],
        issues: [],
      },
    })
    expect(b.calls.map((c) => c.name)).toEqual([
      'get_mobile_strength_week_context',
      'freeze_mobile_strength_week_target',
      'get_mobile_strength_week_projection',
    ])
    expect(b.calls[2]?.parameters).toEqual({
      p_user_id: owner,
      p_expected_generation: generation,
      p_target_id: id(4),
    })
  })

  it('preserves UTC6, bigint proof and an original signup frequency distinct from the selected source', async () => {
    const raw = available()
    const b = boundary({ data: raw, error: null })
    await expect(b.repository.projectAcquiredTarget(owner, target())).resolves.toEqual(raw)
    expect(raw.binding.frequencySourceVersionID).not.toBe(
      raw.target.source_proof.frequency.coverage === 'covered' &&
        raw.target.source_proof.frequency.source_version_id,
    )
  })

  it('uses the CAS winner when it differs from the earlier read', async () => {
    const initial = target()
    const winner: StrengthWeekTarget = {
      ...target(),
      target_id: id(12),
      source: 'informed_frequency',
      source_key: id(6),
      planned_days: 4,
    }
    const b = boundary(
      {
        data: {
          status: 'ready',
          context: {
            kind: 'existing_target',
            user_id: owner,
            generation,
            timezone: 'UTC',
            week_start: monday,
            observed_at: '2026-10-14T12:00:00.123456Z',
            target: initial,
          },
        },
        error: null,
      },
      { data: { status: 'reused', target: winner }, error: null },
      { data: available(winner), error: null },
    )
    await expect(readStrengthTrainingWeek(b.repository, owner)).resolves.toMatchObject({
      status: 'available',
      target: winner,
      summary: { plannedDays: 4, percentage: 50 },
    })
    expect(b.calls[2]?.parameters).toEqual({
      p_user_id: owner,
      p_expected_generation: generation,
      p_target_id: id(12),
    })
  })

  it.each([
    'zero',
    'absent',
  ] as const)('preserves %s target without creating a percentage', async (kind) => {
    const t: StrengthWeekTarget = {
      ...target(),
      ...(kind === 'zero'
        ? { source: 'informed_frequency', source_key: id(6), planned_days: 0 }
        : { source: 'absent', source_key: null, planned_days: null }),
    }
    const raw = available(t)
    raw.projection.workouts = []
    const b = full(raw, t)
    await expect(readStrengthTrainingWeek(b.repository, owner)).resolves.toMatchObject({
      status: 'available',
      summary: {
        completedStrengthDays: 0,
        plannedDays: t.planned_days,
        targetAvailability: kind,
        percentage: null,
      },
    })
  })

  it('preserves other and unclassified events and an affirmative stored answer', async () => {
    const raw = {
      ...available(),
      projection: {
        status: 'available',
        workouts: [
          { ...workout(20), catalogueCategory: 'cardio' },
          { ...workout(21), catalogueCategory: null },
          {
            ...workout(22, '2026-10-13'),
            catalogueCategory: null,
            storedStrengthAnswer: { ownerKey: owner, workoutKey: id(22), answer: 'yes' },
          },
        ],
      },
    }
    const b = full(raw)
    await expect(readStrengthTrainingWeek(b.repository, owner)).resolves.toMatchObject({
      summary: {
        completedStrengthDays: 1,
        otherWorkoutKeys: [id(20)],
        unclassifiedWorkoutKeys: [id(21)],
      },
    })
  })

  it.each([
    ['unavailable', 'binding_unproved'],
    ['unavailable', 'zone_unproved'],
    ['unavailable', 'calendar_unproved'],
    ['unavailable', 'timezone_incompatible'],
    ['unavailable', 'provenance_gap'],
    ['unavailable', 'identity_unproved'],
    ['conflict', 'generation_changed'],
    ['conflict', 'target_changed'],
    ['conflict', 'week_changed'],
  ])('keeps %s/%s without partial target or a zero summary', async (status, reason) => {
    const b = full({ status, reason })
    await expect(readStrengthTrainingWeek(b.repository, owner)).resolves.toEqual({ status, reason })
    expect(b.calls).toHaveLength(3)
  })

  it('does not project after acquisition is unavailable', async () => {
    const b = boundary({ data: { status: 'unavailable', reason: 'missing_scope' }, error: null })
    await expect(readStrengthTrainingWeek(b.repository, owner)).resolves.toEqual({
      status: 'unavailable',
      reason: 'missing_scope',
    })
    expect(b.calls).toHaveLength(1)
  })

  it.each([
    ['extra field', 'extra', true],
    ['changed immutable target', 'target.frozen_at', '2026-10-12T00:00:00.123457Z'],
    ['changed proof', 'target.source_proof.frequency.source_order', '9007199254740994'],
    ['mixed binding owner', 'binding.ownerID', 'a6000000-0000-4000-8000-000000000999'],
    ['mixed binding generation', 'binding.generation', 'a6000000-0000-4000-8000-000000000999'],
    ['invalid epoch', 'binding.epoch', '1'],
    ['invalid revision', 'binding.workoutContentRevision', 2147483648],
    ['binding extra field', 'binding.extra', true],
    ['mixed calendar lifecycle', 'calendar.lifecycleKey', 'a6000000-0000-4000-8000-000000000999'],
    ['mixed calendar owner', 'calendar.ownerID', 'a6000000-0000-4000-8000-000000000999'],
    ['mixed calendar week', 'calendar.weekStartDate', '2026-10-19'],
    ['mixed calendar zone', 'calendar.timeZone', 'Europe/Lisbon'],
    ['as of outside week', 'calendar.asOfLocalDate', '2026-10-19'],
    ['UTC milliseconds', 'observed_at', '2026-10-14T12:00:00.123Z'],
    ['clock before freeze', 'observed_at', '2026-10-12T00:00:00.123455Z'],
    ['clock before binding', 'binding.boundAt', '2026-10-14T12:00:00.123458Z'],
    [
      'inner unavailable',
      'projection',
      { status: 'unavailable', reason: 'calendar_unproved', workouts: null },
    ],
    ['pending workout', 'projection.workouts.0.state', 'pending'],
    ['workout after as of', 'projection.workouts.0.localDate', '2026-10-15'],
    [
      'mixed workout owner',
      'projection.workouts.0.ownerKey',
      'a6000000-0000-4000-8000-000000000999',
    ],
    ['duplicate workout', 'projection.workouts.1', workout(20)],
    [
      'unordered workouts',
      'projection.workouts',
      [workout(22, '2026-10-13'), workout(21), workout(20)],
    ],
    [
      'recognized answer',
      'projection.workouts.0.storedStrengthAnswer',
      { ownerKey: owner, workoutKey: id(20), answer: 'yes' },
    ],
  ] as const)('rejects %s', async (_label, path, value) => {
    const raw = available()
    setPath(raw, path, value)
    const b = boundary({ data: raw, error: null })
    await expect(b.repository.projectAcquiredTarget(owner, target())).rejects.toMatchObject({
      status: 500,
      code: 'strength_week_invalid_response',
    })
    expect(b.calls).toHaveLength(1)
  })

  it('rejects a foreign acquired target before RPC', async () => {
    const b = boundary()
    await expect(b.repository.projectAcquiredTarget(id(999), target())).rejects.toMatchObject({
      status: 422,
      code: 'strength_week_invalid_input',
    })
    expect(b.calls).toHaveLength(0)
  })

  it.each([
    { status: 'disabled' },
    { status: 'unavailable', reason: 'binding_unproved', workouts: [] },
    { status: 'conflict', reason: 'target_changed', target: target() },
  ])('rejects a server negative with local-only status or partial data: $status', async (raw) => {
    const b = boundary({ data: raw, error: null })
    await expect(b.repository.projectAcquiredTarget(owner, target())).rejects.toMatchObject({
      status: 500,
      code: 'strength_week_invalid_response',
    })
  })

  it.each([
    ['22023', 'invalid_strength_week_projection_input', 422, 'strength_week_invalid_input'],
    ['P0002', 'strength_week_projection_patient_not_found', 404, 'strength_week_patient_not_found'],
    ['42501', 'hidden detail', 403, 'strength_week_access_denied'],
    ['40001', 'hidden detail', 409, 'strength_week_transaction_conflict'],
    ['40P01', 'hidden detail', 409, 'strength_week_transaction_conflict'],
    ['55P03', 'hidden detail', 409, 'strength_week_transaction_conflict'],
    [
      '22023',
      'strength_week_projection_requires_read_committed',
      500,
      'strength_week_data_access_failed',
    ],
    ['XX001', 'hidden detail', 500, 'strength_week_data_access_failed'],
  ])('maps provider %s/%s without retry or leaked detail', async (code, message, status, expected) => {
    const b = boundary({ data: null, error: { code, message } })
    await expect(b.repository.projectAcquiredTarget(owner, target())).rejects.toMatchObject({
      status,
      code: expected,
    })
    expect(b.calls).toHaveLength(1)
  })
})
