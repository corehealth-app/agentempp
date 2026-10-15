import type { Json } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  createWorkoutRegistrationRepository,
  toWorkoutRegistrationDto,
  type WorkoutRegistrationPort,
} from './workout-registration-repository'

const OWNER = '00000000-0000-4000-8000-000000000001'
const OTHER = '00000000-0000-4000-8000-000000000002'
const ID = '00000000-0000-4000-8000-000000000003'
const ADMISSION = '00000000-0000-4000-8000-000000000004'
const KEY = 'wui1:ABCDEF01-0000-4000-8000-000000000005'
const EDIT_KEY = 'wue1:ABCDEF01-0000-4000-8000-000000000006'
const INPUT = {
  kind: 'workout' as const,
  workout_type: 'Natação',
  duration_min: 40,
  intensity: 'moderada' as const,
}
const RAW_PROPOSAL = {
  kind: 'workout',
  workoutType: 'Natação',
  durationMin: 40,
  kcalEst: 400,
  intensity: 'moderada',
  source_provider_message_id: KEY,
  source_timestamp: '2026-10-15T15:00:00.000Z',
  source_timezone: 'America/Sao_Paulo',
  source_local_date: '2026-10-15',
  sourceContentType: 'mobile',
  raw_args: { workout_type: 'Natação', duration_min: 40, intensity: 'moderada' },
  express_eligible: false,
}

function registration(revision = 0, status = 'pending') {
  return {
    id: ID,
    status,
    workout_protocol: 'ui-v1',
    content_revision: revision,
    created_at: '2026-10-15T15:00:00.123456+00:00',
    expires_at: '2026-10-16T15:00:00.123456+00:00',
    resolved_at: status === 'pending' ? null : '2026-10-15T15:01:00.123456+00:00',
    proposal: RAW_PROPOSAL,
  }
}

function admission() {
  return {
    ownerID: OWNER,
    admissionID: ADMISSION,
    epoch: OTHER,
    requestNamespace: 'mobile_workout_proposal_v1',
    requestKey: KEY,
    requestHash: '1'.repeat(64),
    admittedAt: '2026-10-15T15:00:00.123456Z',
  }
}

function harness(data: unknown, error: unknown = null) {
  const rpc = vi.fn<WorkoutRegistrationPort['rpc']>().mockResolvedValue({ data, error })
  const port = { rpc }
  return { rpc, port, repository: createWorkoutRegistrationRepository(port) }
}

describe('workout registration RPC adapter — no active product caller', () => {
  it('is lazy and never queries while constructing the repository', () => {
    const getter = vi.fn(() => {
      throw new Error('must remain lazy')
    })
    const port = Object.defineProperty({}, 'rpc', { get: getter }) as WorkoutRegistrationPort
    createWorkoutRegistrationRepository(port)
    expect(getter).not.toHaveBeenCalled()
  })

  it('admits the authenticated owner and preserves literal key case/input', async () => {
    const h = harness({ status: 'admitted', admission: admission() })
    expect(await h.repository.admit(OWNER, KEY, INPUT)).toStrictEqual({
      status: 'admitted',
      admission: admission(),
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('admit_mobile_workout_registration', {
      p_user_id: OWNER,
      p_request_key: KEY,
      p_input: INPUT,
    })
    expect(h.rpc.mock.contexts[0]).toBe(h.port)
  })

  it.each([
    ['mixed owner', { ...admission(), ownerID: OTHER }],
    ['another key', { ...admission(), requestKey: KEY.toLowerCase() }],
    ['another namespace', { ...admission(), requestNamespace: 'legacy' }],
  ])('rejects an admission with %s instead of trusting shape alone', async (_name, value) => {
    await expect(
      harness({ status: 'reused', admission: value }).repository.admit(OWNER, KEY, INPUT),
    ).rejects.toThrow('Invalid workout registration reply')
  })

  it('materialization probes with SQL NULL before any candidate is required', async () => {
    const h = harness({
      status: 'reused',
      pendingID: ID,
      pendingStatus: 'confirmed',
      cancelledCount: 0,
    })
    expect(await h.repository.materialize(OWNER, ADMISSION, INPUT, null, null)).toStrictEqual({
      status: 'reused',
      pendingID: ID,
      pendingStatus: 'confirmed',
      cancelledCount: 0,
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('materialize_mobile_workout_registration', {
      p_user_id: OWNER,
      p_admission_id: ADMISSION,
      p_input: INPUT,
      p_proposal: null,
      p_expires_at: null,
    })
  })

  it('passes the first actual candidate without adding a marker or changing its fields', async () => {
    const h = harness({
      status: 'materialized',
      pendingID: ID,
      pendingStatus: 'pending',
      cancelledCount: 2,
    })
    await h.repository.materialize(OWNER, ADMISSION, INPUT, RAW_PROPOSAL, '2026-10-16T15:00:00Z')
    expect(h.rpc.mock.calls[0]?.[1]).toStrictEqual({
      p_user_id: OWNER,
      p_admission_id: ADMISSION,
      p_input: INPUT,
      p_proposal: RAW_PROPOSAL,
      p_expires_at: '2026-10-16T15:00:00Z',
    })
  })

  it.each([
    'materialize',
    'edit',
  ] as const)('%s recognizes only the exact NULL-probe candidate error', async (method) => {
    const h = harness(null, { code: '22023', message: 'invalid_mobile_workout_proposal_candidate' })
    const result =
      method === 'edit'
        ? h.repository.edit(OWNER, ID, 0, EDIT_KEY, INPUT, null)
        : h.repository.materialize(OWNER, ADMISSION, INPUT, null, null)
    await expect(result).resolves.toStrictEqual({ status: 'preparation_required' })
  })

  it.each([
    { code: '22023', message: 'invalid_mobile_workout_proposal_input' },
    { code: 'P0002', message: 'invalid_mobile_workout_proposal_candidate' },
    { code: '22023', message: 'invalid_mobile_workout_proposal_candidate detail' },
    { code: '42501', message: 'permission denied' },
  ])('does not turn a different database error into permission to prepare', async (error) => {
    const h = harness(null, error)
    await expect(h.repository.edit(OWNER, ID, 0, EDIT_KEY, INPUT, null)).rejects.toBe(error)
  })

  it('does not swallow the candidate error from a real edit', async () => {
    const error = { code: '22023', message: 'invalid_mobile_workout_proposal_candidate' }
    await expect(
      harness(null, error).repository.edit(OWNER, ID, 0, EDIT_KEY, INPUT, RAW_PROPOSAL),
    ).rejects.toBe(error)
  })

  it('reads payload and revision from the single official projection', async () => {
    const h = harness({ status: 'available', registration: registration(2) })
    const reply = await h.repository.get(OWNER, ID)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('get_mobile_workout_registration', {
      p_user_id: OWNER,
      p_registration_id: ID,
    })
    expect(reply).toStrictEqual({ status: 'available', registration: registration(2) })
    if (reply.status !== 'available') throw new Error('missing projection')
    expect(toWorkoutRegistrationDto(reply.registration)).toStrictEqual({
      id: ID,
      status: 'pending',
      created_at: registration().created_at,
      expires_at: registration().expires_at,
      resolved_at: null,
      workout_protocol: 'ui-v1',
      content_revision: 2,
      proposal: {
        kind: 'workout',
        workout_type: 'Natação',
        duration_min: 40,
        estimated_kcal: 400,
        intensity: 'moderada',
      },
    })
    expect(JSON.stringify(toWorkoutRegistrationDto(reply.registration))).not.toContain('source_')
    expect(JSON.stringify(toWorkoutRegistrationDto(reply.registration))).not.toContain('raw_args')
  })

  it.each([
    ['another pending', { ...registration(), id: OTHER }],
    ['missing revision', { ...registration(), content_revision: undefined }],
    ['negative revision', { ...registration(), content_revision: -1 }],
    ['overflow revision', { ...registration(), content_revision: 2147483648 }],
    ['legacy protocol', { ...registration(), workout_protocol: 'legacy' }],
    ['meal proposal', { ...registration(), proposal: { kind: 'meal' } }],
  ])('rejects %s from the official projection', async (_name, value) => {
    await expect(
      harness({ status: 'available', registration: value }).repository.get(OWNER, ID),
    ).rejects.toThrow('Invalid workout registration reply')
  })

  it('recovers EDIT receipt0/1 with current revision2 instead of replacing it by the old response', async () => {
    const wire = {
      status: 'reused',
      registration: registration(2),
      receipt: { requestKey: EDIT_KEY, expectedRevision: 0, resultRevision: 1 },
    }
    const h = harness(wire)
    expect(await h.repository.edit(OWNER, ID, 0, EDIT_KEY, INPUT, null)).toStrictEqual(wire)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('edit_mobile_workout_registration', {
      p_user_id: OWNER,
      p_registration_id: ID,
      p_expected_revision: 0,
      p_request_key: EDIT_KEY,
      p_input: INPUT,
      p_proposal: null,
    })
  })

  it.each([
    { requestKey: KEY, expectedRevision: 0, resultRevision: 1 },
    { requestKey: EDIT_KEY, expectedRevision: 1, resultRevision: 2 },
    { requestKey: EDIT_KEY, expectedRevision: 0, resultRevision: 2 },
  ])('refuses a receipt for another immutable edit attempt', async (receipt) => {
    await expect(
      harness({ status: 'reused', registration: registration(2), receipt }).repository.edit(
        OWNER,
        ID,
        0,
        EDIT_KEY,
        INPUT,
        null,
      ),
    ).rejects.toThrow('Invalid workout registration reply')
  })

  it('keeps owned revision conflicts as conflicts with their current projection', async () => {
    const wire = { status: 'conflict', reason: 'revision_conflict', registration: registration(2) }
    const h = harness(wire)
    expect(await h.repository.cancel(OWNER, ID, 0)).toStrictEqual(wire)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('cancel_mobile_workout_registration', {
      p_user_id: OWNER,
      p_registration_id: ID,
      p_expected_revision: 0,
    })
  })

  it('cancel replay uses its actual revision without a calculation or writer', async () => {
    const wire = { status: 'reused', registration: registration(2, 'cancelled') }
    expect(await harness(wire).repository.cancel(OWNER, ID, 2)).toStrictEqual(wire)
  })

  it('recovers confirmed replay through the RPC with all preparation/catalogue inputs NULL', async () => {
    const capture = {
      legacy_result: { success: true, exercise_calories: 900 },
      strength: { status: 'reuse_existing' },
    }
    const wire = { status: 'reused', registration: registration(2, 'confirmed'), capture }
    const h = harness(wire)
    expect(await h.repository.confirm(OWNER, ID, 2, null, null, null)).toStrictEqual(wire)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('confirm_mobile_workout_registration', {
      p_user_id: OWNER,
      p_registration_id: ID,
      p_expected_revision: 2,
      p_legacy_arguments: null,
      p_catalogue_observation: null,
      p_catalogue_decision: null,
    })
  })

  it('passes the official first13 and catalogue as independent values without rebuilding them', async () => {
    const args: Json = { p_protein_target: 150.125, p_replace_recent: false, p_replace_since: null }
    const observation: Json = { rowCount: '58', activeRows: [] }
    const decision: Json = { status: 'unrecognized' }
    const h = harness({
      status: 'confirmed',
      registration: registration(0, 'confirmed'),
      capture: { legacy_result: null, strength: { status: 'committed' } },
    })
    await h.repository.confirm(OWNER, ID, 0, args, observation, decision)
    expect(h.rpc.mock.calls[0]?.[1]).toStrictEqual({
      p_user_id: OWNER,
      p_registration_id: ID,
      p_expected_revision: 0,
      p_legacy_arguments: args,
      p_catalogue_observation: observation,
      p_catalogue_decision: decision,
    })
  })

  it('does not misinterpret capture_not_accepted as missing preparation or success', async () => {
    const wire = {
      status: 'conflict',
      reason: 'capture_not_accepted',
      registration: registration(),
      capture: {
        legacy_result: null,
        strength: { status: 'forbidden', reason: 'invalid_authority' },
      },
    }
    expect(await harness(wire).repository.confirm(OWNER, ID, 0, null, null, null)).toStrictEqual(
      wire,
    )
  })

  it('preserves preparation_required returned by SQL without inventing a confirmation', async () => {
    const wire = {
      status: 'unavailable',
      reason: 'preparation_required',
      registration: registration(),
    }
    expect(await harness(wire).repository.confirm(OWNER, ID, 0, null, null, null)).toStrictEqual(
      wire,
    )
  })

  it.each([
    'admit',
    'materialize',
    'get',
    'edit',
    'cancel',
    'confirm',
  ] as const)('%s preserves a forbidden authority result without adding a projection', async (method) => {
    const wire = { status: 'forbidden', reason: 'invalid_admission' }
    const h = harness(wire)
    const result = {
      admit: () => h.repository.admit(OWNER, KEY, INPUT),
      materialize: () => h.repository.materialize(OWNER, ADMISSION, INPUT, null, null),
      get: () => h.repository.get(OWNER, ID),
      edit: () => h.repository.edit(OWNER, ID, 0, EDIT_KEY, INPUT, null),
      cancel: () => h.repository.cancel(OWNER, ID, 0),
      confirm: () => h.repository.confirm(OWNER, ID, 0, null, null, null),
    }[method]()
    await expect(result).resolves.toStrictEqual(wire)
  })

  it('propagates a transport failure without retrying or falling back', async () => {
    const h = harness(null)
    const failure = new Error('network failed after request')
    h.rpc.mockRejectedValueOnce(failure)
    await expect(h.repository.confirm(OWNER, ID, 0, null, null, null)).rejects.toBe(failure)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
})
