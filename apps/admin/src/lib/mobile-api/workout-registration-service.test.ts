import type { Json, ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import type { WorkoutRegistrationPort } from './workout-registration-repository'
import {
  admitWorkoutProposal,
  cancelVersionedWorkoutRegistration,
  confirmVersionedWorkoutRegistration,
  createWorkoutRegistrationService,
  editVersionedWorkoutRegistration,
  loadVersionedWorkoutRegistration,
} from './workout-registration-service'

// The production repository is intentionally NOT mocked. Its validators, NULL
// probe classification and closed DTO projection run against this controlled port.
const mocks = vi.hoisted(() => ({
  enabled: vi.fn(),
  buildCandidate: vi.fn(),
  prepareConfirmation: vi.fn(),
  observeCatalogue: vi.fn(),
}))

vi.mock('./workout-registration-switch', () => ({
  workoutRegistrationEnabled: mocks.enabled,
}))
vi.mock('./registration-service', () => ({
  buildWorkoutRegistrationCandidate: mocks.buildCandidate,
  prepareWorkoutRegistrationConfirmation: mocks.prepareConfirmation,
}))
vi.mock('@mpp/agent/workout-strength-catalogue', () => ({
  observeWorkoutStrengthCatalogue: mocks.observeCatalogue,
}))

const OWNER = '00000000-0000-4000-8000-000000000001'
const OTHER = '00000000-0000-4000-8000-000000000002'
const ID = '00000000-0000-4000-8000-000000000003'
const ADMISSION = '00000000-0000-4000-8000-000000000004'
const CREATE_HTTP_KEY = 'ABCDEF01-0000-4000-8000-000000000005'
const EDIT_HTTP_KEY = 'ABCDEF01-0000-4000-8000-000000000006'
const SQL_CREATE_KEY = `wui1:${CREATE_HTTP_KEY}`
const SQL_EDIT_KEY = `wue1:${EDIT_HTTP_KEY}`
const NOW = '2026-10-15T15:00:00.000Z'
const TOMORROW = '2026-10-16T15:00:00.000Z'
const INPUT = {
  kind: 'workout' as const,
  workout_type: 'Natação',
  duration_min: 40,
  intensity: 'moderada' as const,
  performed_at: NOW,
}
const EDIT_INPUT = { ...INPUT, duration_min: 45 }
const RAW_PROPOSAL = {
  kind: 'workout',
  workoutType: 'Natação',
  durationMin: 40,
  kcalEst: 400,
  intensity: 'moderada',
  source_provider_message_id: SQL_CREATE_KEY,
  source_timestamp: NOW,
  source_timezone: 'America/Sao_Paulo',
  source_local_date: '2026-10-15',
  sourceContentType: 'mobile',
  raw_args: { workout_type: 'Natação', duration_min: 40, intensity: 'moderada' },
  express_eligible: false,
  private_debug: { admissionID: ADMISSION, ownerID: OWNER, requestHash: 'a'.repeat(64) },
}
const EDIT_PROPOSAL = {
  ...RAW_PROPOSAL,
  durationMin: 45,
  kcalEst: 450,
  source_provider_message_id: SQL_EDIT_KEY,
  raw_args: { workout_type: 'Natação', duration_min: 45, intensity: 'moderada' },
}
const AUTH: MobileAuthContext = {
  accessToken: 'synthetic-test-token',
  authUserId: OTHER,
  userId: OWNER,
  identity: { id: OTHER, email: 'synthetic@example.invalid', emailConfirmedAt: NOW },
  patient: {
    id: OWNER,
    authUserId: OTHER,
    email: 'synthetic@example.invalid',
    name: 'Synthetic QA',
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}

function registration(revision = 0, status = 'pending', proposal = RAW_PROPOSAL) {
  return {
    id: ID,
    status,
    created_at: '2026-10-15T15:00:00.123456+00:00',
    expires_at: '2026-10-16T15:00:00.123456+00:00',
    resolved_at: status === 'pending' ? null : '2026-10-15T15:01:00.123456+00:00',
    proposal,
    workout_protocol: 'ui-v1',
    content_revision: revision,
  }
}

// Deliberately independent expected whitelist: do not derive this with the
// repository's serializer, which is part of the exercised path.
function dto(revision = 0, status = 'pending', proposal = RAW_PROPOSAL) {
  const row = registration(revision, status, proposal)
  return {
    id: ID,
    status,
    created_at: row.created_at,
    expires_at: row.expires_at,
    resolved_at: row.resolved_at,
    proposal: {
      kind: 'workout',
      workout_type: proposal.workoutType,
      duration_min: proposal.durationMin,
      estimated_kcal: proposal.kcalEst,
      intensity: proposal.intensity,
    },
    workout_protocol: 'ui-v1',
    content_revision: revision,
  }
}

function admitted(status = 'admitted') {
  return {
    status,
    admission: {
      ownerID: OWNER,
      admissionID: ADMISSION,
      epoch: OTHER,
      requestNamespace: 'mobile_workout_proposal_v1',
      requestKey: SQL_CREATE_KEY,
      requestHash: '1'.repeat(64),
      admittedAt: NOW,
    },
  }
}

const CANDIDATE_REQUIRED = {
  code: '22023',
  message: 'invalid_mobile_workout_proposal_candidate',
}
const LEGACY_13: Json = {
  p_user_id: OWNER,
  p_date: '2026-10-16',
  p_workout_type: 'Natação',
  p_duration_min: 40,
  // The official current preparation may differ from the preview's400/date15.
  p_estimated_kcal: 525,
  p_intensity: 'moderada',
  p_notes: 'S17F café 🏋️',
  p_performed_at: NOW,
  p_provider_message_id: SQL_CREATE_KEY,
  p_calories_target: 2200,
  p_protein_target: 150.125,
  p_replace_recent: false,
  p_replace_since: null,
}
const OBSERVATION = {
  observationKey: '00000000-0000-4000-8000-000000000007',
  observedAt: '2026-10-15T15:00:01.123456Z',
  matcherVersion: 'active_slug_then_unique_canonical_display_v1' as const,
}
const CATALOGUE_ROW = {
  id: '00000000-0000-4000-8000-000000000008',
  slug: 'natacao',
  displayName: 'Natação',
  category: 'esporte' as const,
  isActive: true as const,
  updatedAtLiteral: '2026-10-01T10:00:00.123456Z',
}
const OBSERVED_CATALOGUE = {
  status: 'observed',
  originalOperationType: 'Natação',
  read: { status: 'complete', observation: OBSERVATION, activeRows: [CATALOGUE_ROW] },
  classification: {
    status: 'matched',
    observation: OBSERVATION,
    method: 'active_slug',
    catalogue: CATALOGUE_ROW,
  },
}
const SQL_OBSERVATION = {
  status: 'available',
  ...OBSERVATION,
  complete: true,
  rowCount: '1',
  activeRows: [CATALOGUE_ROW],
}
const SQL_DECISION = {
  status: 'matched',
  observationKey: OBSERVATION.observationKey,
  matcherVersion: OBSERVATION.matcherVersion,
  originalOperationType: 'Natação',
  method: 'active_slug',
  selectedRowID: CATALOGUE_ROW.id,
}

function capture(
  resolution = 'sql_insert',
  legacyResult: Json = { success: true, exercise_calories: 900 },
) {
  return {
    legacy_result: legacyResult,
    strength: {
      status: resolution === 'sql_insert' ? 'committed' : 'reuse_existing',
      binding: {
        ownerID: OWNER,
        lifecycleKey: `ui:${ADMISSION}`,
        operationKey: `ui:${ADMISSION}:r:0`,
        originalOperationType: 'Natação',
        workoutLogID: OTHER,
        resolution,
      },
      internal_fact: { user_id: OWNER, arbitrary: 'must not reach HTTP' },
    },
  }
}

function confirmation(status = 'confirmed', resultCapture = capture()) {
  return { status, registration: registration(0, 'confirmed'), capture: resultCapture }
}

const CONFIRMED_WORKOUT = '00000000-0000-4000-8000-000000000009'
const WORKOUT_LIFECYCLE = '00000000-0000-4000-8000-000000000010'
const WORKOUT_SNAPSHOT = '00000000-0000-4000-8000-000000000011'
const STRENGTH_QUESTION = '00000000-0000-4000-8000-000000000012'

// Complete trusted-producer wire fixture, unlike the deliberately opaque
// compatibility capture above. Only the transport is controlled in these tests.
function provenCapture(unrecognized = true, replay = false) {
  return {
    legacy_result: { success: true, exercise_calories: 900, deduped: false },
    strength: {
      status: replay ? 'reuse_existing' : 'committed',
      binding: {
        ownerID: OWNER,
        lifecycleKey: WORKOUT_LIFECYCLE,
        operationKey: `ui:${ADMISSION}:r:0`,
        originalOperationType: 'Natação',
        workoutLogID: CONFIRMED_WORKOUT,
        resolution: replay ? 'sql_replay' : 'sql_insert',
      },
      fact: {
        anchor: {
          ownerID: OWNER,
          workoutLogID: CONFIRMED_WORKOUT,
          lifecycleKey: WORKOUT_LIFECYCLE,
          snapshotID: WORKOUT_SNAPSHOT,
          storedWorkoutType: 'Natação',
          performedAt: '2026-10-15T15:00:00.123456Z',
          snapshotDate: '2026-10-15',
        },
        classification: unrecognized
          ? { status: 'unrecognized', observation: OBSERVATION, reason: 'no_active_match' }
          : {
              status: 'matched',
              observation: OBSERVATION,
              method: 'active_slug',
              catalogue: CATALOGUE_ROW,
            },
        calendar: {
          status: 'proven',
          performedAt: '2026-10-15T15:00:00.123456Z',
          localDate: '2026-10-15',
          timeZone: 'America/Sao_Paulo',
          zoneSource: 'official_owner_zone_at_recording',
          zoneObservedAt: '2026-10-15T14:59:59.654321Z',
          snapshotID: WORKOUT_SNAPSHOT,
          snapshotDate: '2026-10-15',
        },
        clarification: unrecognized
          ? { status: 'unanswered', questionKey: STRENGTH_QUESTION }
          : { status: 'not_applicable' },
        revision: 0,
      },
    },
  }
}

function confirmedWithStrength(strength: Json, replay = false) {
  const result = confirmation(replay ? 'reused' : 'confirmed')
  return { ...result, capture: { ...result.capture, strength } }
}

describe('confirmed workout identity for strength clarification', () => {
  it.each([
    { unrecognized: true, replay: false },
    { unrecognized: false, replay: false },
    { unrecognized: true, replay: true },
  ])('exposes only the proven workout UUID: $unrecognized / replay $replay', async ({
    unrecognized,
    replay,
  }) => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: confirmedWithStrength(provenCapture(unrecognized, replay).strength, replay),
      },
    ])
    const result = await confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)
    expect(result).toStrictEqual({
      ...dto(0, 'confirmed'),
      already_confirmed: replay,
      deduped: false,
      confirmed_workout_id: CONFIRMED_WORKOUT,
    })
    expect(result.id).toBe(ID)
    expect(result.content_revision).toBe(0)
    expect(result.proposal).toMatchObject({ estimated_kcal: 400 })
    for (const privateField of [
      'capture',
      'binding',
      'fact',
      'questionKey',
      'lifecycleKey',
      'ownerID',
    ]) {
      expect(result).not.toHaveProperty(privateField)
    }
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it.each([
    'classification_unavailable',
    'calendar_unavailable',
    'answered',
    'dedup_stored_type',
  ])('retains proven identity independently of %s', async (scenario) => {
    const strength: Record<string, Json> = provenCapture().strength
    const fact = strength.fact as Record<string, Json>
    if (scenario === 'classification_unavailable') {
      fact.classification = { status: 'unavailable', reason: 'catalogue_read_error' }
      fact.clarification = { status: 'not_applicable' }
    } else if (scenario === 'calendar_unavailable') {
      fact.calendar = { status: 'unavailable', reason: 'zone_unproved' }
    } else if (scenario === 'answered') {
      fact.revision = 1
      fact.clarification = {
        status: 'answered',
        receipt: {
          ownerID: OWNER,
          workoutLogID: CONFIRMED_WORKOUT,
          questionKey: STRENGTH_QUESTION,
          answer: 'yes',
          operationKey: 'winner-answer-key-not-capture',
          acceptedAt: '2026-10-15T15:01:00.654321Z',
        },
      }
    } else {
      const binding = strength.binding as Record<string, Json>
      binding.resolution = 'provider_type_dedup'
      strength.status = 'reuse_existing'
      const anchor = fact.anchor as Record<string, Json>
      anchor.storedWorkoutType = 'Natação livre'
    }
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: confirmedWithStrength(strength),
      },
    ])
    expect(await confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)).toStrictEqual({
      ...dto(0, 'confirmed'),
      already_confirmed: false,
      deduped: false,
      confirmed_workout_id: CONFIRMED_WORKOUT,
    })
    h.done()
  })

  it.each([
    ['binding.ownerID', OTHER],
    ['binding.operationKey', ''],
    ['binding.originalOperationType', 'Musculação'],
    ['binding.workoutLogID', ID],
    ['binding.lifecycleKey', ADMISSION],
    ['fact.anchor.ownerID', OTHER],
    ['fact.anchor.workoutLogID', ID],
    ['fact.anchor.lifecycleKey', ADMISSION],
    ['fact.anchor.snapshotID', 'not-a-uuid'],
    ['fact.anchor.performedAt', NOW],
    ['fact.revision', 1],
    ['fact.clarification', { status: 'not_applicable' }],
    ['unexpected', 'private data'],
  ] as const)('never exposes a partial identity from incoherent capture %s', async (path, replacement) => {
    const strength: Record<string, Json> = structuredClone(provenCapture().strength)
    const keys = path.split('.')
    const final = keys.pop() as string
    let parent = strength
    for (const key of keys) parent = parent[key] as Record<string, Json>
    parent[final] = replacement as Json
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: confirmedWithStrength(strength),
      },
    ])
    const result = await confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)
    expect(result).toStrictEqual({
      ...dto(0, 'confirmed'),
      already_confirmed: false,
      deduped: false,
    })
    h.done()
  })

  it('retains a confirmed legacy reply without promoting its isolated workout UUID', async () => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: confirmedWithStrength({
          status: 'unavailable',
          reason: 'legacy_provenance_gap',
          confirmedWorkoutLogID: CONFIRMED_WORKOUT,
        }),
      },
    ])
    expect(await confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)).toStrictEqual({
      ...dto(0, 'confirmed'),
      already_confirmed: false,
      deduped: false,
    })
    h.done()
  })
})

function nullConfirmArgs() {
  return {
    p_user_id: OWNER,
    p_registration_id: ID,
    p_expected_revision: 0,
    p_legacy_arguments: null,
    p_catalogue_observation: null,
    p_catalogue_decision: null,
  }
}
function editArgs(proposal: Json | null, expectedRevision = 0) {
  return {
    p_user_id: OWNER,
    p_registration_id: ID,
    p_expected_revision: expectedRevision,
    p_request_key: SQL_EDIT_KEY,
    p_input: EDIT_INPUT,
    p_proposal: proposal,
  }
}
const MATERIALIZE_ARGS = {
  p_user_id: OWNER,
  p_admission_id: ADMISSION,
  p_input: INPUT,
  p_proposal: null,
  p_expires_at: null,
}
const GET_ARGS = { p_user_id: OWNER, p_registration_id: ID }
const CANCEL_ARGS = { ...GET_ARGS, p_expected_revision: 0 }
const ADMIT_ARGS = { p_user_id: OWNER, p_request_key: SQL_CREATE_KEY, p_input: INPUT }

interface Step {
  name: string
  args: Record<string, unknown>
  data?: unknown
  error?: unknown
}
function harness(steps: Step[]) {
  const remaining = [...steps]
  const rpc = vi.fn<WorkoutRegistrationPort['rpc']>().mockImplementation(async (name, args) => {
    const step = remaining.shift()
    expect(step, `unexpected RPC ${name}`).toBeDefined()
    expect(name).toBe(step?.name)
    expect(args).toStrictEqual(step?.args)
    return { data: step?.data ?? null, error: step?.error ?? null }
  })
  const from = vi.fn(() => {
    throw new Error('versioned service must not query tables or call the legacy writer')
  })
  const supabase = { rpc, from } as unknown as ServiceClient
  return {
    supabase,
    rpc,
    from,
    done() {
      expect(remaining).toHaveLength(0)
      expect(from).not.toHaveBeenCalled()
    },
  }
}

async function apiFailure(action: () => Promise<unknown>, status: number, code: string) {
  const result = await action().then(
    () => ({ failed: false as const }),
    (error: unknown) => ({ failed: true as const, error }),
  )
  expect(result.failed).toBe(true)
  if (!result.failed) throw new Error('expected MobileApiError')
  expect(result.error).toBeInstanceOf(MobileApiError)
  expect(result.error).toMatchObject({ status, code })
  return result.error as MobileApiError
}

beforeEach(() => {
  vi.resetAllMocks()
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  mocks.enabled.mockReturnValue(true)
  mocks.buildCandidate.mockResolvedValue(RAW_PROPOSAL)
  mocks.prepareConfirmation.mockResolvedValue(LEGACY_13)
  mocks.observeCatalogue.mockResolvedValue(OBSERVED_CATALOGUE)
})
afterEach(() => vi.useRealTimers())

describe('explicit server composition without changing the default switch', () => {
  it('enables the real owned service independently of the default OFF switch', async () => {
    mocks.enabled.mockReturnValue(false)
    const service = createWorkoutRegistrationService(() => true)
    const h = harness([
      { name: 'admit_mobile_workout_registration', args: ADMIT_ARGS, data: admitted() },
      {
        name: 'materialize_mobile_workout_registration',
        args: MATERIALIZE_ARGS,
        data: {
          status: 'materialized',
          pendingID: ID,
          pendingStatus: 'pending',
          cancelledCount: 0,
        },
      },
      {
        name: 'get_mobile_workout_registration',
        args: GET_ARGS,
        data: { status: 'available', registration: registration() },
      },
    ])
    expect(service.meWithWorkoutRegistrationCapability(AUTH)).toHaveProperty(
      'workout_registration_protocol',
      'ui-v1',
    )
    const intent = await service.admitWorkoutProposal(h.supabase, AUTH, INPUT, CREATE_HTTP_KEY)
    expect(await intent.execute()).toStrictEqual(dto())
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    h.done()
  })

  it('consults the callback again before executing an already admitted intent', async () => {
    let enabled = true
    const service = createWorkoutRegistrationService(() => enabled)
    const h = harness([
      { name: 'admit_mobile_workout_registration', args: ADMIT_ARGS, data: admitted() },
    ])
    const intent = await service.admitWorkoutProposal(h.supabase, AUTH, INPUT, CREATE_HTTP_KEY)
    enabled = false
    await apiFailure(() => intent.execute(), 503, 'workout_registration_unavailable')
    expect(service.meWithWorkoutRegistrationCapability(AUTH)).not.toHaveProperty(
      'workout_registration_protocol',
    )
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(h.rpc).toHaveBeenCalledTimes(1)
    h.done()
  })

  it('does not observe or freeze the switch while constructing the service', () => {
    let reads = 0
    let enabled = false
    const service = createWorkoutRegistrationService(() => {
      reads += 1
      return enabled
    })
    expect(reads).toBe(0)
    expect(service.meWithWorkoutRegistrationCapability(AUTH)).not.toHaveProperty(
      'workout_registration_protocol',
    )
    enabled = true
    expect(service.meWithWorkoutRegistrationCapability(AUTH)).toHaveProperty(
      'workout_registration_protocol',
      'ui-v1',
    )
    expect(reads).toBe(2)
  })

  it('keeps every explicit OFF operation closed before client access even when the default is ON', async () => {
    const service = createWorkoutRegistrationService(() => false)
    const accessed = vi.fn(() => {
      throw new Error('disabled client must remain unread')
    })
    const db = Object.defineProperties(
      {},
      { rpc: { get: accessed }, from: { get: accessed } },
    ) as ServiceClient
    const actions = [
      () => service.admitWorkoutProposal(db, AUTH, INPUT, CREATE_HTTP_KEY),
      () => service.editVersionedWorkoutRegistration(db, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
      () => service.confirmVersionedWorkoutRegistration(db, AUTH, ID, 0),
      () => service.cancelVersionedWorkoutRegistration(db, AUTH, ID, 0),
      () => service.loadVersionedWorkoutRegistration(db, OWNER, ID),
      () => service.loadWorkoutAwarePendingRegistrations(db, OWNER),
    ]
    for (const action of actions) await apiFailure(action, 503, 'workout_registration_unavailable')
    expect(accessed).not.toHaveBeenCalled()
  })

  it('does not hide a real repository failure behind the explicit enabled composition', async () => {
    const service = createWorkoutRegistrationService(() => true)
    const error = { code: 'XX001', message: 'private failure' }
    const h = harness([{ name: 'get_mobile_workout_registration', args: GET_ARGS, error }])
    await expect(service.loadVersionedWorkoutRegistration(h.supabase, OWNER, ID)).rejects.toBe(
      error,
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
    h.done()
  })
})

describe('versioned workout service — dormant switch and owned reads', () => {
  it.each([
    'propose',
    'edit',
    'confirm',
    'cancel',
    'get',
  ] as const)('OFF rejects %s with503 before accessing a client or preparing anything', async (method) => {
    mocks.enabled.mockReturnValue(false)
    const accessed = vi.fn(() => {
      throw new Error('OFF must not access a database client')
    })
    const supabase = Object.defineProperties(
      {},
      {
        rpc: { get: accessed },
        from: { get: accessed },
      },
    ) as ServiceClient
    const actions = {
      propose: () => admitWorkoutProposal(supabase, AUTH, INPUT, CREATE_HTTP_KEY),
      edit: () =>
        editVersionedWorkoutRegistration(supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
      confirm: () => confirmVersionedWorkoutRegistration(supabase, AUTH, ID, 0),
      cancel: () => cancelVersionedWorkoutRegistration(supabase, AUTH, ID, 0),
      get: () => loadVersionedWorkoutRegistration(supabase, OWNER, ID),
    }
    await apiFailure(actions[method], 503, 'workout_registration_unavailable')
    expect(accessed).not.toHaveBeenCalled()
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
  })

  it('GET uses the official owned RPC and exposes only the eight-field projection', async () => {
    const h = harness([
      {
        name: 'get_mobile_workout_registration',
        args: GET_ARGS,
        data: { status: 'available', registration: registration(2, 'pending', EDIT_PROPOSAL) },
      },
    ])
    expect(await loadVersionedWorkoutRegistration(h.supabase, OWNER, ID)).toStrictEqual(
      dto(2, 'pending', EDIT_PROPOSAL),
    )
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it('does not repair or fall back when the real adapter rejects another pendingID', async () => {
    const h = harness([
      {
        name: 'get_mobile_workout_registration',
        args: GET_ARGS,
        data: { status: 'available', registration: { ...registration(), id: OTHER } },
      },
    ])
    await expect(loadVersionedWorkoutRegistration(h.supabase, OWNER, ID)).rejects.toThrow(
      'Invalid workout registration reply',
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
    h.done()
  })
})

describe('versioned workout PROPOSE admission before the HTTP claim/cache', () => {
  it('admits first but leaves calculation/materialization lazy until execute', async () => {
    const h = harness([
      { name: 'admit_mobile_workout_registration', args: ADMIT_ARGS, data: admitted() },
    ])
    const prepared = await admitWorkoutProposal(h.supabase, AUTH, INPUT, CREATE_HTTP_KEY)
    expect(typeof prepared.execute).toBe('function')
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    // A route may return its HTTP cache at this point. Admission already ran.
    h.done()
  })

  it('only the exact NULL-probe error permits one calculation and first materialization', async () => {
    const h = harness([
      { name: 'admit_mobile_workout_registration', args: ADMIT_ARGS, data: admitted() },
      {
        name: 'materialize_mobile_workout_registration',
        args: MATERIALIZE_ARGS,
        error: CANDIDATE_REQUIRED,
      },
      {
        name: 'materialize_mobile_workout_registration',
        args: { ...MATERIALIZE_ARGS, p_proposal: RAW_PROPOSAL, p_expires_at: TOMORROW },
        data: {
          status: 'materialized',
          pendingID: ID,
          pendingStatus: 'pending',
          cancelledCount: 1,
        },
      },
      {
        name: 'get_mobile_workout_registration',
        args: GET_ARGS,
        data: { status: 'available', registration: registration() },
      },
    ])
    mocks.buildCandidate.mockImplementation(async (...args: unknown[]) => {
      expect(h.rpc).toHaveBeenCalledTimes(2)
      expect(args).toStrictEqual([h.supabase, AUTH, INPUT, SQL_CREATE_KEY])
      return RAW_PROPOSAL
    })
    const operation = await admitWorkoutProposal(h.supabase, AUTH, INPUT, CREATE_HTTP_KEY)
    expect(await operation.execute()).toStrictEqual(dto())
    expect(mocks.buildCandidate).toHaveBeenCalledTimes(1)
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    h.done()
  })

  it('reuses admission/materialization and returns CURRENT confirmed revision2 without calculation', async () => {
    const h = harness([
      { name: 'admit_mobile_workout_registration', args: ADMIT_ARGS, data: admitted('reused') },
      {
        name: 'materialize_mobile_workout_registration',
        args: MATERIALIZE_ARGS,
        data: { status: 'reused', pendingID: ID, pendingStatus: 'confirmed', cancelledCount: 0 },
      },
      {
        name: 'get_mobile_workout_registration',
        args: GET_ARGS,
        data: { status: 'available', registration: registration(2, 'confirmed', EDIT_PROPOSAL) },
      },
    ])
    const operation = await admitWorkoutProposal(h.supabase, AUTH, INPUT, CREATE_HTTP_KEY)
    expect(await operation.execute()).toStrictEqual(dto(2, 'confirmed', EDIT_PROPOSAL))
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it('rejects changed content in admission before a cached HTTP answer could be used', async () => {
    const h = harness([
      {
        name: 'admit_mobile_workout_registration',
        args: ADMIT_ARGS,
        data: { status: 'conflict', reason: 'request_content_conflict' },
      },
    ])
    await apiFailure(
      () => admitWorkoutProposal(h.supabase, AUTH, INPUT, CREATE_HTTP_KEY),
      409,
      'registration_request_conflict',
    )
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    h.done()
  })
})

describe('versioned workout EDIT immutable attempt and current projection', () => {
  it('probes first, prepares once with wue1 literal key, then returns an explicit receipt', async () => {
    const receipt = { requestKey: SQL_EDIT_KEY, expectedRevision: 0, resultRevision: 1 }
    const h = harness([
      { name: 'edit_mobile_workout_registration', args: editArgs(null), error: CANDIDATE_REQUIRED },
      {
        name: 'edit_mobile_workout_registration',
        args: editArgs(EDIT_PROPOSAL),
        data: {
          status: 'edited',
          registration: registration(1, 'pending', EDIT_PROPOSAL),
          receipt,
        },
      },
    ])
    mocks.buildCandidate.mockImplementation(async (...args: unknown[]) => {
      expect(h.rpc).toHaveBeenCalledTimes(1)
      expect(args).toStrictEqual([h.supabase, AUTH, EDIT_INPUT, SQL_EDIT_KEY])
      return EDIT_PROPOSAL
    })
    expect(
      await editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
    ).toStrictEqual({ ...dto(1, 'pending', EDIT_PROPOSAL), receipt })
    expect(mocks.buildCandidate).toHaveBeenCalledTimes(1)
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    h.done()
  })

  it('receipt0/1 replay may carry CURRENT revision2 without calculation or replacing it by revision1', async () => {
    const receipt = { requestKey: SQL_EDIT_KEY, expectedRevision: 0, resultRevision: 1 }
    const h = harness([
      {
        name: 'edit_mobile_workout_registration',
        args: editArgs(null),
        data: {
          status: 'reused',
          registration: registration(2, 'pending', EDIT_PROPOSAL),
          receipt,
        },
      },
    ])
    expect(
      await editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
    ).toStrictEqual({ ...dto(2, 'pending', EDIT_PROPOSAL), receipt })
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it.each([
    { code: '22023', message: 'invalid_mobile_workout_proposal_input' },
    { code: '22023', message: 'invalid_mobile_workout_proposal_candidate detail' },
    { code: '42501', message: 'permission denied' },
  ])('does not calculate, retry, or fall back for a different SQL probe error: $message', async (error) => {
    const h = harness([{ name: 'edit_mobile_workout_registration', args: editArgs(null), error }])
    await expect(
      editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
    ).rejects.toBe(error)
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    h.done()
  })

  it('propagates the exact candidate error from the actual prepared EDIT instead of preparing again', async () => {
    const h = harness([
      { name: 'edit_mobile_workout_registration', args: editArgs(null), error: CANDIDATE_REQUIRED },
      {
        name: 'edit_mobile_workout_registration',
        args: editArgs(EDIT_PROPOSAL),
        error: CANDIDATE_REQUIRED,
      },
    ])
    mocks.buildCandidate.mockResolvedValue(EDIT_PROPOSAL)
    await expect(
      editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
    ).rejects.toBe(CANDIDATE_REQUIRED)
    expect(mocks.buildCandidate).toHaveBeenCalledTimes(1)
    h.done()
  })

  it('returns request-key content conflict as409 without calculating or exposing the raw proposal', async () => {
    const h = harness([
      {
        name: 'edit_mobile_workout_registration',
        args: editArgs(null),
        data: { status: 'conflict', reason: 'request_key_conflict', registration: registration(2) },
      },
    ])
    const error = await apiFailure(
      () => editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
      409,
      'registration_request_conflict',
    )
    expect(error.details).toStrictEqual({ registration: dto(2) })
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    h.done()
  })
})

describe('versioned workout conflicts keep UI drafts recoverable', () => {
  it.each([
    'edit',
    'confirm',
    'cancel',
  ] as const)('%s revision conflict is409 with sanitized CURRENT snapshot, never a not-pending fallback', async (method) => {
    const h = harness([
      {
        name: `${method}_mobile_workout_registration`,
        args:
          method === 'edit'
            ? editArgs(null)
            : method === 'confirm'
              ? nullConfirmArgs()
              : CANCEL_ARGS,
        data: {
          status: 'conflict',
          reason: 'revision_conflict',
          registration: registration(2, 'pending', EDIT_PROPOSAL),
        },
      },
    ])
    const action = {
      edit: () =>
        editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
      confirm: () => confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
      cancel: () => cancelVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
    }[method]
    const error = await apiFailure(action, 409, 'registration_revision_conflict')
    expect(error.details).toStrictEqual({ registration: dto(2, 'pending', EDIT_PROPOSAL) })
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it.each([
    ['expired', 'expired', 410, 'registration_expired'],
    ['not_pending', 'cancelled', 409, 'registration_not_pending'],
    ['already_confirmed', 'confirmed', 409, 'registration_already_confirmed'],
  ] as const)('preserves the distinct %s outcome without fabricating an edit success', async (reason, status, http, code) => {
    const h = harness([
      {
        name: 'edit_mobile_workout_registration',
        args: editArgs(null),
        data: { status: 'conflict', reason, registration: registration(0, status) },
      },
    ])
    const error = await apiFailure(
      () => editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
      http,
      code,
    )
    expect(error.details).toStrictEqual({ registration: dto(0, status) })
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    h.done()
  })

  it.each([
    'get',
    'edit',
    'confirm',
    'cancel',
  ] as const)('%s forbidden authority becomes409 without a registration or private identifiers', async (method) => {
    const h = harness([
      {
        name: `${method}_mobile_workout_registration`,
        args:
          method === 'get'
            ? GET_ARGS
            : method === 'edit'
              ? editArgs(null)
              : method === 'confirm'
                ? nullConfirmArgs()
                : CANCEL_ARGS,
        data: { status: 'forbidden', reason: 'stale_epoch' },
      },
    ])
    const action = {
      get: () => loadVersionedWorkoutRegistration(h.supabase, OWNER, ID),
      edit: () =>
        editVersionedWorkoutRegistration(h.supabase, AUTH, ID, EDIT_INPUT, EDIT_HTTP_KEY, 0),
      confirm: () => confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
      cancel: () => cancelVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
    }[method]
    const error = await apiFailure(action, 409, 'registration_authority_stale')
    expect(error.details ?? {}).not.toHaveProperty('registration')
    const details = JSON.stringify(error.details ?? {})
    for (const privateValue of [OWNER, ID, ADMISSION, 'source_provider_message_id', 'raw_args']) {
      expect(details).not.toContain(privateValue)
    }
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })
})

describe('versioned workout CONFIRM replay, official preparation, bounded catalogue recovery', () => {
  it('confirmed replay starts with three NULL inputs and returns no capture or daily calories as workout calories', async () => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: confirmation(
          'reused',
          capture('sql_replay', { success: true, exercise_calories: 900, deduped: false }),
        ),
      },
    ])
    const result = await confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)
    expect(result).toStrictEqual({
      ...dto(0, 'confirmed'),
      already_confirmed: true,
      deduped: false,
    })
    expect(result.proposal).toMatchObject({ estimated_kcal: 400 })
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it('preparation_required prepares the official13 once and preserves all numeric, date and NULL literals', async () => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: {
          status: 'unavailable',
          reason: 'preparation_required',
          registration: registration(),
        },
      },
      {
        name: 'confirm_mobile_workout_registration',
        args: {
          ...nullConfirmArgs(),
          p_legacy_arguments: LEGACY_13,
          p_catalogue_observation: SQL_OBSERVATION,
          p_catalogue_decision: SQL_DECISION,
        },
        data: confirmation(),
      },
    ])
    mocks.prepareConfirmation.mockImplementation(async (...args: unknown[]) => {
      expect(h.rpc).toHaveBeenCalledTimes(1)
      expect(args).toStrictEqual([h.supabase, AUTH, RAW_PROPOSAL])
      return LEGACY_13
    })
    expect(await confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)).toStrictEqual({
      ...dto(0, 'confirmed'),
      already_confirmed: false,
      deduped: false,
    })
    expect(mocks.prepareConfirmation).toHaveBeenCalledTimes(1)
    expect(mocks.observeCatalogue).toHaveBeenCalledTimes(1)
    expect(mocks.observeCatalogue).toHaveBeenCalledWith(
      'Natação',
      expect.objectContaining({ enabled: true }),
    )
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    h.done()
  })

  it('only NULL-probe capture invalid_authority may observe and repeat with legacy13 still NULL', async () => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: {
          status: 'conflict',
          reason: 'capture_not_accepted',
          registration: registration(),
          capture: {
            legacy_result: null,
            strength: { status: 'forbidden', reason: 'invalid_authority' },
          },
        },
      },
      {
        name: 'confirm_mobile_workout_registration',
        args: {
          ...nullConfirmArgs(),
          p_catalogue_observation: SQL_OBSERVATION,
          p_catalogue_decision: SQL_DECISION,
        },
        data: confirmation('confirmed', capture('provider_type_dedup', null)),
      },
    ])
    expect(await confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)).toStrictEqual({
      ...dto(0, 'confirmed'),
      already_confirmed: false,
      deduped: true,
    })
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).toHaveBeenCalledTimes(1)
    h.done()
  })

  it.each([
    { status: 'conflict', reason: 'source_observation_changed' },
    { status: 'conflict', reason: 'invalid_authority' },
    { status: 'forbidden', reason: 'stale_lifecycle' },
    { status: 'unavailable', reason: 'catalogue_incomplete' },
  ])('keeps other capture negatives as409 instead of recalculating or refreshing: $reason', async (strength) => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: {
          status: 'conflict',
          reason: 'capture_not_accepted',
          registration: registration(),
          capture: { legacy_result: null, strength },
        },
      },
    ])
    const error = await apiFailure(
      () => confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
      409,
      'registration_capture_conflict',
    )
    expect(error.details).toStrictEqual({ registration: dto() })
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it('does not confuse top-level forbidden invalid_authority with the exact nested capture recovery', async () => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: { status: 'forbidden', reason: 'invalid_authority' },
      },
    ])
    const error = await apiFailure(
      () => confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
      409,
      'registration_authority_stale',
    )
    expect(error.details ?? {}).not.toHaveProperty('registration')
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })

  it('does not grant the NULL-probe catalogue recovery after sending the actual prepared13', async () => {
    const h = harness([
      {
        name: 'confirm_mobile_workout_registration',
        args: nullConfirmArgs(),
        data: {
          status: 'unavailable',
          reason: 'preparation_required',
          registration: registration(),
        },
      },
      {
        name: 'confirm_mobile_workout_registration',
        args: {
          ...nullConfirmArgs(),
          p_legacy_arguments: LEGACY_13,
          p_catalogue_observation: SQL_OBSERVATION,
          p_catalogue_decision: SQL_DECISION,
        },
        data: {
          status: 'conflict',
          reason: 'capture_not_accepted',
          registration: registration(),
          capture: {
            legacy_result: null,
            strength: { status: 'forbidden', reason: 'invalid_authority' },
          },
        },
      },
    ])
    await apiFailure(
      () => confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
      409,
      'registration_capture_conflict',
    )
    expect(mocks.prepareConfirmation).toHaveBeenCalledTimes(1)
    expect(mocks.observeCatalogue).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledTimes(2)
    h.done()
  })

  it('bounds stored-winner catalogue recovery to one observation/retry even if invalid_authority repeats', async () => {
    const negative = {
      status: 'conflict',
      reason: 'capture_not_accepted',
      registration: registration(),
      capture: {
        legacy_result: null,
        strength: { status: 'forbidden', reason: 'invalid_authority' },
      },
    }
    const h = harness([
      { name: 'confirm_mobile_workout_registration', args: nullConfirmArgs(), data: negative },
      {
        name: 'confirm_mobile_workout_registration',
        args: {
          ...nullConfirmArgs(),
          p_catalogue_observation: SQL_OBSERVATION,
          p_catalogue_decision: SQL_DECISION,
        },
        data: negative,
      },
    ])
    await apiFailure(
      () => confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0),
      409,
      'registration_capture_conflict',
    )
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledTimes(2)
    h.done()
  })

  it('propagates operational SQL errors from confirmation without legacy fallback or automatic replay', async () => {
    const error = { code: '40P01', message: 'deadlock detected', details: 'synthetic detail' }
    const h = harness([
      { name: 'confirm_mobile_workout_registration', args: nullConfirmArgs(), error },
    ])
    await expect(confirmVersionedWorkoutRegistration(h.supabase, AUTH, ID, 0)).rejects.toBe(error)
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })
})

describe('versioned workout CANCEL does not load profiles or recalculate', () => {
  it.each([
    'cancelled',
    'reused',
  ] as const)('%s uses one CAS RPC, with the frozen revision, and no preparation', async (status) => {
    const h = harness([
      {
        name: 'cancel_mobile_workout_registration',
        args: { ...CANCEL_ARGS, p_expected_revision: 2 },
        data: { status, registration: registration(2, 'cancelled', EDIT_PROPOSAL) },
      },
    ])
    expect(await cancelVersionedWorkoutRegistration(h.supabase, AUTH, ID, 2)).toStrictEqual(
      dto(2, 'cancelled', EDIT_PROPOSAL),
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(mocks.buildCandidate).not.toHaveBeenCalled()
    expect(mocks.prepareConfirmation).not.toHaveBeenCalled()
    expect(mocks.observeCatalogue).not.toHaveBeenCalled()
    h.done()
  })
})
