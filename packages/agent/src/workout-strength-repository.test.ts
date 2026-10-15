/** S6 test-first: only the typed unknown RPC boundary is faked.
 * No factory/type/fixture authenticates SQL provenance. Missing module is SETUP,
 * never causal RED. S1 and S2 implementations/tests remain unchanged here.
 */
import * as classificationCore from '@mpp/core/workout-strength-classification'
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  type AnswerWorkoutStrengthInput,
  type AnswerWorkoutStrengthResult,
  createWorkoutStrengthRepository,
  type WorkoutOwnerScope,
  type WorkoutStrengthCaptureResult,
  type WorkoutStrengthRepositoryPort,
} from './workout-strength-repository.js'

type Reply = Awaited<ReturnType<WorkoutStrengthRepositoryPort['rpc']>>
type Success = Extract<WorkoutStrengthCaptureResult, { status: 'committed' | 'reuse_existing' }>
const RPC = 'resolve_confirmed_workout_strength_capture' as const
const OWNER = 'c59a7000-0000-0000-0000-000000000001'
const LIFE = 'c59a7000-0000-0000-0000-000000000002'
const WORKOUT = 'c59a7000-0000-0000-0000-000000000003'
const SNAPSHOT = 'c59a7000-0000-0000-0000-000000000004'
const QUESTION = 'c59a7000-0000-0000-0000-000000000005'
const OTHER = 'c59a7000-0000-0000-0000-000000000099'
const KEY = 'capture-key'
const RAW = '  MÚSCULAÇÃO\t'
const INSTANT = '2026-10-12T15:00:00.123456Z'
const MISSING = Symbol('missing fixture field')
function scope() {
  return { ownerID: OWNER, expectedLifecycleKey: LIFE }
}
function matched(status: 'committed' | 'reuse_existing' = 'reuse_existing'): Success {
  return {
    status,
    binding: {
      ownerID: OWNER,
      lifecycleKey: LIFE,
      operationKey: KEY,
      originalOperationType: RAW,
      workoutLogID: WORKOUT,
      resolution: 'sql_replay',
    },
    fact: {
      anchor: {
        ownerID: OWNER,
        workoutLogID: WORKOUT,
        lifecycleKey: LIFE,
        snapshotID: SNAPSHOT,
        storedWorkoutType: 'musculacao',
        performedAt: INSTANT,
        snapshotDate: '2026-10-12',
      },
      classification: {
        status: 'matched',
        method: 'active_slug',
        observation: {
          observationKey: 'c59a7000-0000-0000-0000-000000000006',
          observedAt: '2026-10-12T14:59:59.000001Z',
          matcherVersion: 'active_slug_then_unique_canonical_display_v1',
        },
        catalogue: {
          id: 'c59a7000-0000-0000-0000-000000000007',
          slug: 'musculacao',
          displayName: 'Musculação',
          category: 'musculacao',
          isActive: true,
          updatedAtLiteral: '2026-10-10T01:02:03.000002Z',
        },
      },
      calendar: {
        status: 'proven',
        performedAt: INSTANT,
        localDate: '2026-10-12',
        timeZone: 'America/Sao_Paulo',
        zoneSource: 'official_owner_zone_at_recording',
        zoneObservedAt: '2026-10-12T14:59:58.000003Z',
        snapshotID: SNAPSHOT,
        snapshotDate: '2026-10-12',
      },
      clarification: { status: 'not_applicable' },
      revision: 0,
    },
  }
}
function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value))
    throw new Error('S6_SETUP_RECORD')
  return value as Record<string, unknown>
}
/** Fixture mutations stay at the declared unknown transport boundary. */
function change(value: unknown, ...changes: readonly (readonly [string, unknown])[]): unknown {
  const copy: unknown = structuredClone(value)
  for (const [path, replacement] of changes) {
    const keys = path.split('.')
    const final = keys.pop()
    if (final === undefined) throw new Error('S6_SETUP_PATH')
    let parent = record(copy)
    for (const key of keys) parent = record(parent[key])
    if (replacement === MISSING) delete parent[final]
    else parent[final] = replacement
  }
  return copy
}
function unknownFact(answer?: 'yes' | 'no'): unknown {
  const base = matched()
  const classification = record(base.fact.classification)
  return change(
    base,
    [
      'fact.classification',
      {
        status: 'unrecognized',
        observation: classification.observation,
        reason: 'no_active_match',
      },
    ],
    [
      'fact.clarification',
      answer === undefined
        ? { status: 'unanswered', questionKey: QUESTION }
        : {
            status: 'answered',
            receipt: {
              ownerID: OWNER,
              workoutLogID: WORKOUT,
              questionKey: QUESTION,
              answer,
              operationKey: 'winner-answer-key-not-capture',
              acceptedAt: '2026-10-12T15:02:03.654321Z',
            },
          },
    ],
    ['fact.revision', answer === undefined ? 0 : 1],
  )
}
function unavailable(
  reason = 'operation_key_missing',
  confirmedWorkoutLogID: string | null = null,
) {
  return { status: 'unavailable', reason, confirmedWorkoutLogID }
}
function portFor(reply: unknown) {
  const rpc = vi
    .fn<WorkoutStrengthRepositoryPort['rpc']>()
    .mockImplementation(() => Promise.resolve(reply as Reply))
  const port: WorkoutStrengthRepositoryPort = { rpc }
  return { rpc, port, repository: createWorkoutStrengthRepository(port) }
}
function readData(data: unknown, requestScope: WorkoutOwnerScope = scope(), key = KEY, raw = RAW) {
  const harness = portFor({ data, error: null })
  return {
    ...harness,
    result: harness.repository.resolveConfirmedWorkoutStrengthCapture(requestScope, key, raw),
  }
}
async function invalidData(data: unknown) {
  const { rpc, result } = readData(data)
  await expect(result).rejects.toEqual(new TypeError('Invalid workout strength reply'))
  expect(rpc).toHaveBeenCalledTimes(1)
}
function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  const promise = new Promise<T>((accept) => {
    resolve = accept
  })
  return { promise, resolve }
}
afterEach(() => {
  vi.restoreAllMocks()
})

describe('lazy factory, exact RPC and request snapshot', () => {
  it('does not inspect rpc until invocation and validates invalid requests first', async () => {
    const failure = new Error('synthetic rpc getter')
    const getter = vi.fn(() => {
      throw failure
    })
    const port = Object.defineProperty({}, 'rpc', { get: getter }) as WorkoutStrengthRepositoryPort
    const repository = createWorkoutStrengthRepository(port)
    expect(getter).not.toHaveBeenCalled()
    await expect(
      repository.resolveConfirmedWorkoutStrengthCapture(scope(), '', RAW),
    ).rejects.toEqual(new TypeError('Invalid workout strength request'))
    expect(getter).not.toHaveBeenCalled()
    await expect(repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW)).rejects.toBe(
      failure,
    )
    expect(getter).toHaveBeenCalledTimes(1)
  })
  it('preserves this and sends exactly the four original literals once without calling the classifier', async () => {
    const wire = matched()
    const before = structuredClone(wire)
    const classify = vi.spyOn(classificationCore, 'classifyConfirmedWorkoutType')
    const port: WorkoutStrengthRepositoryPort = {
      rpc(name, args) {
        expect(this).toBe(port)
        expect(name).toBe(RPC)
        expect(args).toStrictEqual({
          p_user_id: OWNER,
          p_expected_lifecycle_key: LIFE,
          p_operation_key: KEY,
          p_original_operation_type: RAW,
        })
        return Promise.resolve({ data: wire, error: null })
      },
    }
    const rpc = vi.spyOn(port, 'rpc')
    expect(
      await createWorkoutStrengthRepository(port).resolveConfirmedWorkoutStrengthCapture(
        scope(),
        KEY,
        RAW,
      ),
    ).toStrictEqual(before)
    expect(wire).toStrictEqual(before)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(classify).not.toHaveBeenCalled()
  })
  it('accepts PromiseLike builders without an SDK', async () => {
    const reply = { data: matched(), error: null }
    const thenable: PromiseLike<Reply> = {
      // biome-ignore lint/suspicious/noThenProperty: Exercise the explicit PromiseLike RPC builder contract.
      then(onfulfilled, onrejected) {
        return Promise.resolve(reply).then(onfulfilled, onrejected)
      },
    }
    const h = portFor(null)
    h.rpc.mockReturnValue(thenable)
    expect(
      await h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).toStrictEqual(reply.data)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    [null, KEY, RAW],
    [{}, KEY, RAW],
    [{ ownerID: null, expectedLifecycleKey: LIFE }, KEY, RAW],
    [{ ownerID: OWNER.toUpperCase(), expectedLifecycleKey: LIFE }, KEY, RAW],
    [{ ownerID: OWNER, expectedLifecycleKey: 'not-uuid' }, KEY, RAW],
    [scope(), null, RAW],
    [scope(), 0, RAW],
    [scope(), '', RAW],
    [scope(), KEY, null],
    [scope(), KEY, 0],
    [scope(), KEY, ''],
    [scope(), KEY, '   '],
  ])('rejects invalid request %# before any rpc', async (requestScope, key, raw) => {
    const h = portFor({ data: matched(), error: null })
    await expect(
      h.repository.resolveConfirmedWorkoutStrengthCapture(
        requestScope as WorkoutOwnerScope,
        key as string,
        raw as string,
      ),
    ).rejects.toEqual(new TypeError('Invalid workout strength request'))
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it.each([
    '\t',
    '\n',
    '\u00a0',
    '  MUSCULACAO  ',
  ])('uses SQL btrim space semantics, not JS trim, for raw %#', async (raw) => {
    const h = readData(unavailable(), scope(), ' ', raw)
    expect(await h.result).toStrictEqual(unavailable())
    expect(h.rpc).toHaveBeenCalledWith(RPC, {
      p_user_id: OWNER,
      p_expected_lifecycle_key: LIFE,
      p_operation_key: ' ',
      p_original_operation_type: raw,
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    null,
    {},
    { rpc: false },
  ])('defers noncallable port error until invocation %#', async (port) => {
    const repository = createWorkoutStrengthRepository(
      port as unknown as WorkoutStrengthRepositoryPort,
    )
    await expect(
      repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).rejects.toEqual(new TypeError('Workout strength port requires a callable rpc'))
  })
})

describe('R2 valid branches stay literal and do not reclassify history', () => {
  it.each(['committed', 'reuse_existing'] as const)('accepts exact %s success', async (status) => {
    expect(await readData(matched(status)).result).toStrictEqual(matched(status))
  })
  it.each([
    'sql_insert',
    'sql_replay',
    'provider_type_dedup',
    'recent6h_dedup',
  ])('preserves resolution %s', async (resolution) => {
    const wire = change(matched(), ['binding.resolution', resolution])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    'active_slug',
    'unique_active_display',
  ])('accepts method %s without recomputing it', async (method) => {
    const wire = change(matched(), ['fact.classification.method', method])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    'musculacao',
    'cardio',
    'esporte',
    'mobilidade',
  ])('preserves stored category %s', async (category) => {
    const wire = change(matched(), ['fact.classification.catalogue.category', category])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    'no_active_match',
    'ambiguous_active_name',
    'generic_outro',
  ])('accepts unanswered %s with revision0', async (reason) => {
    const wire = change(unknownFact(), ['fact.classification.reason', reason])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    'yes',
    'no',
  ] as const)('accepts stored answer %s and distinct winning operation key', async (answer) => {
    const wire = unknownFact(answer)
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    'catalogue_read_error',
    'catalogue_invalid',
    'catalogue_incomplete',
    'legacy_provenance_gap',
  ])('accepts classification unavailable %s without manufacturing a question', async (reason) => {
    const wire = change(matched(), ['fact.classification', { status: 'unavailable', reason }])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    'zone_unproved',
    'calendar_conflict',
    'legacy_calendar_gap',
  ])('accepts unavailable calendar %s', async (reason) => {
    const wire = change(matched(), ['fact.calendar', { status: 'unavailable', reason }])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    ['legacy_provenance_gap', null],
    ['legacy_provenance_gap', WORKOUT],
    ['identity_unproved', null],
    ['identity_unproved', WORKOUT],
    ['operation_key_missing', null],
    ['operation_key_missing', WORKOUT],
  ] as const)('preserves R2 unavailable reason/nullable ID %#', async (reason, id) => {
    expect(await readData(unavailable(reason, id)).result).toStrictEqual(unavailable(reason, id))
  })
  it.each([
    ['forbidden', 'stale_lifecycle'],
    ['forbidden', 'stale_workout'],
    ['forbidden', 'mixed_owner'],
    ['forbidden', 'source_observation_changed'],
    ['forbidden', 'invalid_authority'],
    ['conflict', 'stale_lifecycle'],
    ['conflict', 'stale_workout'],
    ['conflict', 'mixed_owner'],
    ['conflict', 'source_observation_changed'],
    ['conflict', 'invalid_authority'],
  ])('preserves legitimate %s/%s exactly', async (status, reason) => {
    const wire = { status, reason }
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it('accepts opaque nonempty historical zone and empty catalogue display/slug without inventing producer rules', async () => {
    const wire = change(
      matched(),
      ['fact.calendar.timeZone', 'historic-zone-not-in-current-catalogue'],
      ['fact.classification.catalogue.slug', ''],
      ['fact.classification.catalogue.displayName', ''],
    )
    expect(await readData(wire).result).toStrictEqual(wire)
  })
})

const invalidSuccessChanges: readonly (readonly [string, string, unknown])[] = [
  ['status_unknown', 'status', 'ok'],
  ['binding_missing', 'binding', MISSING],
  ['fact_null', 'fact', null],
  ['binding_owner', 'binding.ownerID', OTHER],
  ['binding_life', 'binding.lifecycleKey', OTHER],
  ['binding_key', 'binding.operationKey', 'another-key'],
  ['binding_raw_trim', 'binding.originalOperationType', RAW.trim()],
  ['binding_workout_nonuuid', 'binding.workoutLogID', 'pending-id'],
  ['binding_resolution', 'binding.resolution', 'dedup'],
  ['anchor_owner', 'fact.anchor.ownerID', OTHER],
  ['anchor_life', 'fact.anchor.lifecycleKey', OTHER],
  ['anchor_workout', 'fact.anchor.workoutLogID', OTHER],
  ['anchor_snapshot_nonuuid', 'fact.anchor.snapshotID', 'snapshot'],
  ['anchor_type_null', 'fact.anchor.storedWorkoutType', null],
  ['anchor_type_blank', 'fact.anchor.storedWorkoutType', '   '],
  ['classification_null', 'fact.classification', null],
  ['classification_unknown', 'fact.classification.status', 'known'],
  ['observation_uuid', 'fact.classification.observation.observationKey', 'key'],
  ['observation_uppercase', 'fact.classification.observation.observationKey', OWNER.toUpperCase()],
  ['matcher_version', 'fact.classification.observation.matcherVersion', 'v2'],
  ['method_unknown', 'fact.classification.method', 'fuzzy'],
  ['catalogue_uuid', 'fact.classification.catalogue.id', 'selected'],
  ['category_unknown', 'fact.classification.catalogue.category', 'strength'],
  ['active_false', 'fact.classification.catalogue.isActive', false],
  ['generic_outro', 'fact.classification.catalogue.slug', 'outro'],
  ['display_null', 'fact.classification.catalogue.displayName', null],
  ['calendar_null', 'fact.calendar', null],
  ['calendar_status', 'fact.calendar.status', 'estimated'],
  ['calendar_performed', 'fact.calendar.performedAt', '2026-10-12T15:00:00.123457Z'],
  ['calendar_snapshot', 'fact.calendar.snapshotID', OTHER],
  ['calendar_snapshotdate', 'fact.calendar.snapshotDate', '2026-10-13'],
  ['calendar_localdate', 'fact.calendar.localDate', '2026-10-13'],
  ['calendar_zone_empty', 'fact.calendar.timeZone', ''],
  ['calendar_source', 'fact.calendar.zoneSource', 'current_profile'],
  ['clarification_null', 'fact.clarification', null],
  ['matched_unanswered', 'fact.clarification', { status: 'unanswered', questionKey: QUESTION }],
  ['revision_string', 'fact.revision', '0'],
  ['revision_null', 'fact.revision', null],
  ['revision_negative', 'fact.revision', -1],
  ['matched_revision1', 'fact.revision', 1],
  ['revision2', 'fact.revision', 2],
]
describe('strict known keys, required fields and cross-record correlations', () => {
  it.each(
    invalidSuccessChanges,
  )('rejects success mismatch %s', async (_label, path, replacement) => {
    await invalidData(change(matched(), [path, replacement]))
  })
  it.each([
    '',
    'binding',
    'fact',
    'fact.anchor',
    'fact.classification',
    'fact.classification.observation',
    'fact.classification.catalogue',
    'fact.calendar',
    'fact.clarification',
  ])('rejects extra keys at %s', async (path) => {
    await invalidData(change(matched(), [(path === '' ? '' : path + '.') + 'unexpected', true]))
  })
  it.each([
    ['question_uuid', 'fact.clarification.questionKey', 'question'],
    ['unrecognized_not_applicable', 'fact.clarification', { status: 'not_applicable' }],
    ['unanswered_revision1', 'fact.revision', 1],
    ['unrecognized_reason', 'fact.classification.reason', 'unknown'],
    ['unrecognized_catalogue_leak', 'fact.classification.catalogue', {}],
  ] as const)('rejects unrecognized mismatch %s', async (_label, path, replacement) => {
    await invalidData(change(unknownFact(), [path, replacement]))
  })
  it.each([
    ['receipt_owner', 'fact.clarification.receipt.ownerID', OTHER],
    ['receipt_workout', 'fact.clarification.receipt.workoutLogID', OTHER],
    ['receipt_question', 'fact.clarification.receipt.questionKey', 'invalid'],
    [
      'receipt_question_uppercase',
      'fact.clarification.receipt.questionKey',
      QUESTION.toUpperCase(),
    ],
    ['receipt_answer', 'fact.clarification.receipt.answer', 'YES'],
    ['receipt_key_empty', 'fact.clarification.receipt.operationKey', ''],
    ['receipt_key_null', 'fact.clarification.receipt.operationKey', null],
    ['receipt_missing', 'fact.clarification.receipt', MISSING],
    ['receipt_extra', 'fact.clarification.receipt.extra', true],
    ['answered_revision0', 'fact.revision', 0],
  ] as const)('rejects answered mismatch %s', async (_label, path, replacement) => {
    await invalidData(change(unknownFact('yes'), [path, replacement]))
  })
  it.each([
    null,
    [],
    {},
    { status: 'disabled' },
    { status: 'unavailable', reason: 'catalogue_invalid', confirmedWorkoutLogID: null },
    { status: 'unavailable', reason: 'operation_key_missing' },
    { ...unavailable(), confirmedWorkoutLogID: 1 },
    { ...unavailable(), confirmedWorkoutLogID: OWNER.toUpperCase() },
    { ...unavailable(), extra: true },
    { status: 'forbidden', reason: 'operation_key_missing' },
    { status: 'conflict', reason: 'stale_workout', fact: null },
  ])('rejects malformed outer branch %#', async (wire) => {
    await invalidData(wire)
  })
  it.each([
    ['fact.classification', { status: 'unavailable', reason: 'temporary' }],
    ['fact.calendar', { status: 'unavailable', reason: 'unknown_zone' }],
  ] as const)('rejects an unrecognized nested unavailable reason at %s', async (path, branch) => {
    await invalidData(change(matched(), [path, branch]))
  })
  it('rejects mixed unavailable/calendar/clarification fields instead of stripping them', async () => {
    await invalidData(
      change(matched(), [
        'fact.classification',
        { status: 'unavailable', reason: 'catalogue_invalid', observation: {} },
      ]),
    )
    await invalidData(
      change(matched(), [
        'fact.calendar',
        { status: 'unavailable', reason: 'zone_unproved', timeZone: 'UTC' },
      ]),
    )
    await invalidData(
      change(
        matched(),
        ['fact.classification', { status: 'unavailable', reason: 'catalogue_invalid' }],
        ['fact.clarification', { status: 'unanswered', questionKey: QUESTION }],
      ),
    )
  })
})

describe('envelope and error boundaries', () => {
  it('allows Supabase envelope metadata but copies only the exact domain result', async () => {
    const wire = matched()
    const h = portFor({ data: wire, error: null, status: 200, statusText: 'OK', count: null })
    expect(
      await h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).toStrictEqual(wire)
  })
  it.each([
    false,
    0,
    '',
    { message: 'synthetic untrusted detail' },
  ])('treats every non-null error %# as fixed operational failure without retry', async (error) => {
    const h = portFor({ data: matched(), error })
    await expect(
      h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).rejects.toEqual(new Error('Workout strength RPC failed'))
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    null,
    [],
    {},
    { data: matched() },
    { error: null },
    { data: matched(), error: undefined },
    Object.create({ data: matched(), error: null }),
  ])('rejects missing/undefined/inherited envelope fields %#', async (reply) => {
    const h = portFor(reply)
    await expect(
      h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).rejects.toEqual(new TypeError('Invalid workout strength reply'))
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'throw',
    'reject',
  ] as const)('propagates original transport %s value unchanged', async (mode) => {
    const failure = { synthetic: 'transport failure' }
    const h = portFor(null)
    h.rpc.mockImplementation(() => {
      if (mode === 'throw') throw failure
      return Promise.reject(failure)
    })
    await expect(
      h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).rejects.toBe(failure)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it('does not catch defects while accessing the reply', async () => {
    const failure = new Error('synthetic wire getter failure')
    const h = portFor({
      get data() {
        throw failure
      },
      error: null,
    })
    await expect(
      h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).rejects.toBe(failure)
  })
})

describe('manual UTC US6 and civil dates, precision and no chronology inference', () => {
  it.each([
    '0001-01-01T00:00:00.000000Z',
    '2000-02-29T23:59:59.123456Z',
    '2024-02-29T00:00:00.000001Z',
    '9999-12-31T23:59:59.999999Z',
  ])('keeps valid boundary literal %s', async (observedAt) => {
    const wire = change(matched(), ['fact.classification.observation.observedAt', observedAt])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    '0000-01-01T00:00:00.000000Z',
    '10000-01-01T00:00:00.000000Z',
    '1900-02-29T00:00:00.000000Z',
    '2100-02-29T00:00:00.000000Z',
    '2026-04-31T00:00:00.000000Z',
    '2026-13-01T00:00:00.000000Z',
    '2026-01-00T00:00:00.000000Z',
    '2026-10-12T24:00:00.000000Z',
    '2026-10-12T00:60:00.000000Z',
    '2026-10-12T00:00:60.000000Z',
    '2026-10-12T00:00:00.123Z',
    '2026-10-12T00:00:00.1234567Z',
    '2026-10-12T00:00:00.123456+00:00',
  ])('rejects noncanonical/impossible timestamp %s', async (observedAt) => {
    await invalidData(change(matched(), ['fact.classification.observation.observedAt', observedAt]))
  })
  it.each([
    'fact.anchor.performedAt',
    'fact.calendar.performedAt',
    'fact.calendar.zoneObservedAt',
    'fact.classification.catalogue.updatedAtLiteral',
    'fact.clarification.receipt.acceptedAt',
  ])('validates every instant field %s', async (path) => {
    await invalidData(
      change(path.includes('receipt') ? unknownFact('yes') : matched(), [
        path,
        '2026-02-30T00:00:00.000001Z',
      ]),
    )
  })
  it.each([
    '0001-01-01',
    '2000-02-29',
    '2024-02-29',
    '9999-12-31',
  ])('accepts coherent civil date %s without deriving it from current timezone', async (date) => {
    const wire = change(
      matched(),
      ['fact.anchor.snapshotDate', date],
      ['fact.calendar.snapshotDate', date],
      ['fact.calendar.localDate', date],
    )
    expect(await readData(wire).result).toStrictEqual(wire)
  })
  it.each([
    '0000-01-01',
    '1900-02-29',
    '2026-02-30',
    '2026-04-31',
    '2026-1-01',
    '2026-10-12T00:00:00Z',
  ])('rejects impossible/noncivil anchor date %s', async (date) => {
    await invalidData(
      change(
        matched(),
        ['fact.anchor.snapshotDate', date],
        ['fact.calendar.snapshotDate', date],
        ['fact.calendar.localDate', date],
      ),
    )
  })
  it('preserves sixth decimals and does not invent ordering between stored instants', async () => {
    const wire = change(unknownFact('yes'), [
      'fact.classification.observation.observedAt',
      '2026-10-15T00:00:00.000001Z',
    ])
    expect(await readData(wire).result).toStrictEqual(wire)
  })
})

describe('pending identity, payload copies and independent concurrent operations', () => {
  it('snapshots request fields before await and keeps RPC args stable after scope mutation', async () => {
    const h = portFor(null)
    const gate = deferred<Reply>()
    const entered = deferred<void>()
    h.rpc.mockImplementation(() => {
      entered.resolve(undefined)
      return gate.promise
    })
    const requestScope = scope()
    const result = h.repository.resolveConfirmedWorkoutStrengthCapture(requestScope, KEY, RAW)
    requestScope.ownerID = OTHER
    requestScope.expectedLifecycleKey = OTHER
    // Observe real port entry, without assuming the implementation calls it synchronously.
    await Promise.race([entered.promise, result.then(() => undefined)])
    expect(h.rpc).toHaveBeenCalledTimes(1)
    const args = h.rpc.mock.calls[0]?.[1]
    expect(args).toStrictEqual({
      p_user_id: OWNER,
      p_expected_lifecycle_key: LIFE,
      p_operation_key: KEY,
      p_original_operation_type: RAW,
    })
    gate.resolve({ data: matched(), error: null })
    expect(await result).toStrictEqual(matched())
    expect(args).toStrictEqual({
      p_user_id: OWNER,
      p_expected_lifecycle_key: LIFE,
      p_operation_key: KEY,
      p_original_operation_type: RAW,
    })
  })
  it('rejects an internally coherent foreign-owner payload changed before delivery against the input snapshot', async () => {
    const h = portFor(null)
    const gate = deferred<Reply>()
    h.rpc.mockReturnValue(gate.promise)
    const result = h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW)
    const wire = change(matched(), ['binding.ownerID', OTHER], ['fact.anchor.ownerID', OTHER])
    gate.resolve({ data: wire, error: null })
    await expect(result).rejects.toEqual(new TypeError('Invalid workout strength reply'))
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    matched(),
    unknownFact('yes'),
  ])('deep copies all returned nested branches before later port payload mutations %#', async (wire) => {
    const before = structuredClone(wire)
    const result = await readData(wire).result
    expect(result).toStrictEqual(before)
    const root = record(wire)
    const fact = record(root.fact)
    record(root.binding).operationKey = 'changed-after-return'
    record(fact.anchor).ownerID = OTHER
    record(fact.calendar).timeZone = 'changed-after-return'
    const classification = record(fact.classification)
    record(classification.observation).observedAt = '9999-12-31T23:59:59.999999Z'
    if (classification.catalogue !== undefined) record(classification.catalogue).category = 'cardio'
    const clarification = record(fact.clarification)
    if (clarification.receipt !== undefined) record(clarification.receipt).answer = 'no'
    expect(result).toStrictEqual(before)
  })
  it('keeps A/B calls isolated when B resolves before A on the same repository', async () => {
    const a = deferred<Reply>()
    const b = deferred<Reply>()
    const h = portFor(null)
    h.rpc.mockReturnValueOnce(a.promise).mockReturnValueOnce(b.promise)
    const first = h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW)
    const otherScope = { ownerID: OTHER, expectedLifecycleKey: OTHER }
    const otherWire = change(
      matched(),
      ['binding.ownerID', OTHER],
      ['binding.lifecycleKey', OTHER],
      ['binding.operationKey', 'key-B'],
      ['binding.originalOperationType', 'natacao'],
      ['fact.anchor.ownerID', OTHER],
      ['fact.anchor.lifecycleKey', OTHER],
    )
    const second = h.repository.resolveConfirmedWorkoutStrengthCapture(
      otherScope,
      'key-B',
      'natacao',
    )
    b.resolve({ data: otherWire, error: null })
    expect(await second).toStrictEqual(otherWire)
    a.resolve({ data: matched(), error: null })
    expect(await first).toStrictEqual(matched())
    expect(h.rpc).toHaveBeenCalledTimes(2)
    expect(h.rpc.mock.calls.map((call) => call[1])).toStrictEqual([
      {
        p_user_id: OWNER,
        p_expected_lifecycle_key: LIFE,
        p_operation_key: KEY,
        p_original_operation_type: RAW,
      },
      {
        p_user_id: OTHER,
        p_expected_lifecycle_key: OTHER,
        p_operation_key: 'key-B',
        p_original_operation_type: 'natacao',
      },
    ])
  })
  it('does not cache a previous result or suppress a later request after RPC failure', async () => {
    const h = portFor(null)
    h.rpc
      .mockReturnValueOnce(Promise.resolve({ data: null, error: false }))
      .mockReturnValueOnce(Promise.resolve({ data: matched(), error: null }))
    await expect(
      h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).rejects.toEqual(new Error('Workout strength RPC failed'))
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(
      await h.repository.resolveConfirmedWorkoutStrengthCapture(scope(), KEY, RAW),
    ).toStrictEqual(matched())
    expect(h.rpc).toHaveBeenCalledTimes(2)
  })
})

// S10 test-first: injected unknown RPC boundary only. No SQL authority is faked.
// Missing future exports/method are SETUP, not a causal product RED.
type S10MutableInput = {
  -readonly [K in keyof AnswerWorkoutStrengthInput]: AnswerWorkoutStrengthInput[K]
}
type S10Success = Extract<AnswerWorkoutStrengthResult, { status: 'accepted' | 'reuse_existing' }>
type S10ResolveArgs = {
  readonly p_user_id: string
  readonly p_expected_lifecycle_key: string
  readonly p_operation_key: string
  readonly p_original_operation_type: string
}
type S10AnswerArgs = {
  readonly p_user_id: string
  readonly p_expected_lifecycle_key: string
  readonly p_workout_log_id: string
  readonly p_expected_fact_revision: number
  readonly p_question_key: string
  readonly p_answer: 'yes' | 'no'
  readonly p_operation_key: string
}
type S10ExpectedInput = {
  readonly ownerID: string
  readonly expectedLifecycleKey: string
  readonly workoutLogID: string
  readonly expectedFactRevision: number
  readonly questionKey: string
  readonly answer: 'yes' | 'no'
  readonly operationKey: string
}
type S10ExpectedResult =
  | {
      readonly status: 'accepted' | 'reuse_existing'
      readonly receipt: {
        readonly ownerID: string
        readonly workoutLogID: string
        readonly questionKey: string
        readonly answer: 'yes' | 'no'
        readonly operationKey: string
        readonly acceptedAt: string
      }
    }
  | {
      readonly status: 'conflict' | 'forbidden' | 'not_available'
      readonly reason:
        | 'answer_already_differs'
        | 'operation_content_conflict'
        | 'mixed_owner'
        | 'stale_workout'
        | 'stale_lifecycle'
        | 'stale_fact'
        | 'not_unrecognized'
    }
type S10ExpectedRpcParameters =
  | [name: 'resolve_confirmed_workout_strength_capture', args: S10ResolveArgs]
  | [name: 'answer_confirmed_workout_strength', args: S10AnswerArgs]
type S10Equal<A, B> =
  (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2 ? true : false
const S10_RPC = 'answer_confirmed_workout_strength' as const
const S10_KEY = 'answer-A'
const S10_TIME = '2026-10-12T15:02:03.654321Z'
function s10Input(patch: Partial<S10MutableInput> = {}): S10MutableInput {
  return {
    ownerID: OWNER,
    expectedLifecycleKey: LIFE,
    workoutLogID: WORKOUT,
    expectedFactRevision: 0,
    questionKey: QUESTION,
    answer: 'yes',
    operationKey: S10_KEY,
    ...patch,
  }
}
function s10Success(
  status: 'accepted' | 'reuse_existing' = 'accepted',
  answer: 'yes' | 'no' = 'yes',
): S10Success {
  return {
    status,
    receipt: {
      ownerID: OWNER,
      workoutLogID: WORKOUT,
      questionKey: QUESTION,
      answer,
      operationKey: S10_KEY,
      acceptedAt: S10_TIME,
    },
  }
}
function s10Args(input: AnswerWorkoutStrengthInput): S10AnswerArgs {
  return {
    p_user_id: input.ownerID,
    p_expected_lifecycle_key: input.expectedLifecycleKey,
    p_workout_log_id: input.workoutLogID,
    p_expected_fact_revision: input.expectedFactRevision,
    p_question_key: input.questionKey,
    p_answer: input.answer,
    p_operation_key: input.operationKey,
  }
}
function s10Read(data: unknown, input = s10Input()) {
  const h = portFor({ data, error: null })
  return { ...h, result: h.repository.answerConfirmedWorkoutStrength(input) }
}
async function s10InvalidData(data: unknown) {
  const h = s10Read(data)
  await expect(h.result).rejects.toEqual(new TypeError('Invalid workout strength reply'))
  expect(h.rpc).toHaveBeenCalledTimes(1)
}
const s10InvalidInputs: readonly (readonly [string, unknown])[] = [
  ['whole_null', null],
  ['whole_undefined', undefined],
  ['whole_array', []],
  ['whole_empty', {}],
  ['whole_number', 0],
  ['owner_null', { ...s10Input(), ownerID: null }],
  ['owner_uppercase', { ...s10Input(), ownerID: OWNER.toUpperCase() }],
  ['owner_nonuuid', { ...s10Input(), ownerID: 'owner' }],
  ['life_null', { ...s10Input(), expectedLifecycleKey: null }],
  ['life_uppercase', { ...s10Input(), expectedLifecycleKey: LIFE.toUpperCase() }],
  ['life_nonuuid', { ...s10Input(), expectedLifecycleKey: 'life' }],
  ['workout_null', { ...s10Input(), workoutLogID: null }],
  ['workout_uppercase', { ...s10Input(), workoutLogID: WORKOUT.toUpperCase() }],
  ['workout_nonuuid', { ...s10Input(), workoutLogID: 'workout' }],
  ['question_null', { ...s10Input(), questionKey: null }],
  ['question_uppercase', { ...s10Input(), questionKey: QUESTION.toUpperCase() }],
  ['question_nonuuid', { ...s10Input(), questionKey: 'question' }],
  ['revision_null', { ...s10Input(), expectedFactRevision: null }],
  ['revision_undefined', { ...s10Input(), expectedFactRevision: undefined }],
  ['revision_string', { ...s10Input(), expectedFactRevision: '0' }],
  ['revision_negative', { ...s10Input(), expectedFactRevision: -1 }],
  ['revision_fraction', { ...s10Input(), expectedFactRevision: 0.5 }],
  ['revision_nan', { ...s10Input(), expectedFactRevision: Number.NaN }],
  ['revision_infinity', { ...s10Input(), expectedFactRevision: Number.POSITIVE_INFINITY }],
  ['revision_int32_overflow', { ...s10Input(), expectedFactRevision: 2147483648 }],
  [
    'revision_safe_integer_not_int32',
    { ...s10Input(), expectedFactRevision: Number.MAX_SAFE_INTEGER },
  ],
  ['answer_null', { ...s10Input(), answer: null }],
  ['answer_case', { ...s10Input(), answer: 'YES' }],
  ['answer_padded', { ...s10Input(), answer: 'yes ' }],
  ['answer_empty', { ...s10Input(), answer: '' }],
  ['answer_boolean', { ...s10Input(), answer: false }],
  ['key_null', { ...s10Input(), operationKey: null }],
  ['key_undefined', { ...s10Input(), operationKey: undefined }],
  ['key_number', { ...s10Input(), operationKey: 0 }],
  ['key_empty', { ...s10Input(), operationKey: '' }],
]
const s10NegativeCases = [
  ['conflict', 'answer_already_differs'],
  ['conflict', 'operation_content_conflict'],
  ['conflict', 'mixed_owner'],
  ['conflict', 'stale_workout'],
  ['conflict', 'stale_lifecycle'],
  ['conflict', 'stale_fact'],
  ['conflict', 'not_unrecognized'],
  ['forbidden', 'answer_already_differs'],
  ['forbidden', 'operation_content_conflict'],
  ['forbidden', 'mixed_owner'],
  ['forbidden', 'stale_workout'],
  ['forbidden', 'stale_lifecycle'],
  ['forbidden', 'stale_fact'],
  ['forbidden', 'not_unrecognized'],
  ['not_available', 'answer_already_differs'],
  ['not_available', 'operation_content_conflict'],
  ['not_available', 'mixed_owner'],
  ['not_available', 'stale_workout'],
  ['not_available', 'stale_lifecycle'],
  ['not_available', 'stale_fact'],
  ['not_available', 'not_unrecognized'],
] as const
const s10MalformedOuter: readonly (readonly [string, unknown])[] = [
  ['null', null],
  ['undefined', undefined],
  ['array', []],
  ['number', 0],
  ['empty', {}],
  ['missing_status', { receipt: s10Success().receipt }],
  ['unknown_status', { ...s10Success(), status: 'committed' }],
  ['numeric_status', { ...s10Success(), status: 1 }],
  ['missing_receipt', { status: 'accepted' }],
  ['null_receipt', { status: 'accepted', receipt: null }],
  ['array_receipt', { status: 'accepted', receipt: [] }],
  ['empty_receipt', { status: 'accepted', receipt: {} }],
  ['extra_root', { ...s10Success(), extra: true }],
  ['success_reason', { ...s10Success(), reason: 'stale_fact' }],
  ['negative_missing_reason', { status: 'forbidden' }],
  ['negative_null_reason', { status: 'conflict', reason: null }],
  ['negative_unknown_reason', { status: 'not_available', reason: 'temporary' }],
  ['negative_other_union_reason', { status: 'forbidden', reason: 'catalogue_read_error' }],
  ['negative_receipt', { status: 'conflict', reason: 'stale_fact', receipt: null }],
  ['negative_extra', { status: 'forbidden', reason: 'stale_workout', extra: true }],
]
const s10ReceiptInvalid: readonly (readonly [string, string, unknown])[] = [
  ['owner_other', 'ownerID', OTHER],
  ['owner_uppercase', 'ownerID', OWNER.toUpperCase()],
  ['owner_nonuuid', 'ownerID', 'owner'],
  ['owner_null', 'ownerID', null],
  ['workout_other', 'workoutLogID', OTHER],
  ['workout_uppercase', 'workoutLogID', WORKOUT.toUpperCase()],
  ['workout_nonuuid', 'workoutLogID', 'workout'],
  ['workout_null', 'workoutLogID', null],
  ['question_other', 'questionKey', OTHER],
  ['question_uppercase', 'questionKey', QUESTION.toUpperCase()],
  ['question_nonuuid', 'questionKey', 'question'],
  ['question_null', 'questionKey', null],
  ['answer_different_literal', 'answer', 'no'],
  ['answer_case', 'answer', 'YES'],
  ['answer_null', 'answer', null],
  ['answer_number', 'answer', 0],
  ['winner_key_empty', 'operationKey', ''],
  ['winner_key_null', 'operationKey', null],
  ['winner_key_number', 'operationKey', 0],
]
const s10BadTimes: readonly unknown[] = [
  '0000-01-01T00:00:00.000000Z',
  '10000-01-01T00:00:00.000000Z',
  '1900-02-29T00:00:00.000000Z',
  '2100-02-29T00:00:00.000000Z',
  '2026-04-31T00:00:00.000000Z',
  '2026-13-01T00:00:00.000000Z',
  '2026-01-00T00:00:00.000000Z',
  '2026-10-12T24:00:00.000000Z',
  '2026-10-12T00:60:00.000000Z',
  '2026-10-12T00:00:60.000000Z',
  '2026-10-12T00:00:00.123Z',
  '2026-10-12T00:00:00.1234567Z',
  '2026-10-12T00:00:00.123456+00:00',
  '2026-10-12T00:00:00.123456z',
  ' 2026-10-12T00:00:00.123456Z',
  'infinity',
  'now',
  null,
  0,
]

describe('S10 correlated RPC types and lazy exact invocation', () => {
  it('S10 type contract preserves Parameters correlation and rejects both swapped name/args pairs', () => {
    type Actual = Parameters<WorkoutStrengthRepositoryPort['rpc']>
    const exact: S10Equal<Actual, S10ExpectedRpcParameters> = true
    const inputFieldsExact: S10Equal<AnswerWorkoutStrengthInput, S10ExpectedInput> = true
    const resultFieldsExact: S10Equal<AnswerWorkoutStrengthResult, S10ExpectedResult> = true
    const swappedAnswerRejected: [
      'answer_confirmed_workout_strength',
      S10ResolveArgs,
    ] extends Actual
      ? false
      : true = true
    const swappedResolveRejected: [
      'resolve_confirmed_workout_strength_capture',
      S10AnswerArgs,
    ] extends Actual
      ? false
      : true = true
    type Method = ReturnType<
      typeof createWorkoutStrengthRepository
    >['answerConfirmedWorkoutStrength']
    const inputExact: S10Equal<Parameters<Method>, [input: AnswerWorkoutStrengthInput]> = true
    const resultExact: S10Equal<ReturnType<Method>, Promise<AnswerWorkoutStrengthResult>> = true
    expect([
      exact,
      inputFieldsExact,
      resultFieldsExact,
      swappedAnswerRejected,
      swappedResolveRejected,
      inputExact,
      resultExact,
    ]).toStrictEqual([true, true, true, true, true, true, true])
  })
  it('S10 factory is lazy and captures a one-use rpc getter exactly once', async () => {
    const rpc = vi
      .fn<WorkoutStrengthRepositoryPort['rpc']>()
      .mockResolvedValue({ data: s10Success(), error: null })
    const secondRead = new Error('S10 second rpc getter access')
    let reads = 0
    const getter = vi.fn(() => {
      reads += 1
      if (reads > 1) throw secondRead
      return rpc
    })
    const port = Object.defineProperty({}, 'rpc', { get: getter }) as WorkoutStrengthRepositoryPort
    const repository = createWorkoutStrengthRepository(port)
    expect(getter).not.toHaveBeenCalled()
    expect(await repository.answerConfirmedWorkoutStrength(s10Input())).toStrictEqual(s10Success())
    expect(getter).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('S10 preserves this and sends exactly seven original arguments without classification', async () => {
    const classify = vi.spyOn(classificationCore, 'classifyConfirmedWorkoutType')
    const input = s10Input()
    const wire = s10Success()
    const port: WorkoutStrengthRepositoryPort = {
      rpc(name, args) {
        expect(this).toBe(port)
        expect([name, args]).toStrictEqual([S10_RPC, s10Args(input)])
        return Promise.resolve({ data: wire, error: null })
      },
    }
    const rpc = vi.spyOn(port, 'rpc')
    expect(
      await createWorkoutStrengthRepository(port).answerConfirmedWorkoutStrength(input),
    ).toStrictEqual(wire)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(classify).not.toHaveBeenCalled()
  })
  it('S10 supports a genuine PromiseLike RPC builder without a client SDK', async () => {
    const reply: Reply = { data: s10Success(), error: null }
    const thenable: PromiseLike<Reply> = {
      // biome-ignore lint/suspicious/noThenProperty: Exercise the explicit PromiseLike RPC builder contract.
      then(onfulfilled, onrejected) {
        return Promise.resolve(reply).then(onfulfilled, onrejected)
      },
    }
    const h = portFor(null)
    h.rpc.mockReturnValue(thenable)
    expect(await h.repository.answerConfirmedWorkoutStrength(s10Input())).toStrictEqual(
      s10Success(),
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it('S10 reads the seven scalar getters once before obtaining rpc and never after await', async () => {
    const input = s10Input()
    const counts = {
      ownerID: 0,
      expectedLifecycleKey: 0,
      workoutLogID: 0,
      expectedFactRevision: 0,
      questionKey: 0,
      answer: 0,
      operationKey: 0,
    }
    const keys: readonly (keyof S10MutableInput)[] = [
      'ownerID',
      'expectedLifecycleKey',
      'workoutLogID',
      'expectedFactRevision',
      'questionKey',
      'answer',
      'operationKey',
    ]
    for (const key of keys) {
      const value = input[key]
      Object.defineProperty(input, key, {
        enumerable: true,
        get() {
          counts[key] += 1
          return value
        },
      })
    }
    const rpc = vi
      .fn<WorkoutStrengthRepositoryPort['rpc']>()
      .mockResolvedValue({ data: s10Success(), error: null })
    const getter = vi.fn(() => {
      expect(counts).toStrictEqual({
        ownerID: 1,
        expectedLifecycleKey: 1,
        workoutLogID: 1,
        expectedFactRevision: 1,
        questionKey: 1,
        answer: 1,
        operationKey: 1,
      })
      return rpc
    })
    const port = Object.defineProperty({}, 'rpc', { get: getter }) as WorkoutStrengthRepositoryPort
    const repository = createWorkoutStrengthRepository(port)
    expect(getter).not.toHaveBeenCalled()
    expect(await repository.answerConfirmedWorkoutStrength(input)).toStrictEqual(s10Success())
    expect(counts).toStrictEqual({
      ownerID: 1,
      expectedLifecycleKey: 1,
      workoutLogID: 1,
      expectedFactRevision: 1,
      questionKey: 1,
      answer: 1,
      operationKey: 1,
    })
    expect(getter).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'ownerID',
    'expectedLifecycleKey',
    'workoutLogID',
    'expectedFactRevision',
    'questionKey',
    'answer',
    'operationKey',
  ] as const)('S10 propagates original input getter defect at %s before rpc access', async (field) => {
    const input = s10Input()
    const failure = new Error('S10 input getter ' + field)
    Object.defineProperty(input, field, {
      enumerable: true,
      get() {
        throw failure
      },
    })
    const rpc = vi.fn<WorkoutStrengthRepositoryPort['rpc']>()
    const getter = vi.fn(() => rpc)
    const port = Object.defineProperty({}, 'rpc', { get: getter }) as WorkoutStrengthRepositoryPort
    const repository = createWorkoutStrengthRepository(port)
    await expect(repository.answerConfirmedWorkoutStrength(input)).rejects.toBe(failure)
    expect(getter).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each(
    s10InvalidInputs,
  )('S10 rejects invalid input %s before rpc getter and any RPC', async (_label, input) => {
    const rpc = vi.fn<WorkoutStrengthRepositoryPort['rpc']>()
    const getter = vi.fn(() => rpc)
    const port = Object.defineProperty({}, 'rpc', { get: getter }) as WorkoutStrengthRepositoryPort
    const repository = createWorkoutStrengthRepository(port)
    // Deliberately malformed input at the public request boundary only.
    await expect(
      repository.answerConfirmedWorkoutStrength(input as AnswerWorkoutStrengthInput),
    ).rejects.toEqual(new TypeError('Invalid workout strength request'))
    expect(getter).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each([
    0, 1, 2, 2147483647,
  ])('S10 admits representable revision %i without inventing a current CAS', async (expectedFactRevision) => {
    const input = s10Input({ expectedFactRevision })
    const wire = { status: 'conflict', reason: 'stale_fact' }
    const h = s10Read(wire, input)
    expect(await h.result).toStrictEqual(wire)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith(S10_RPC, s10Args(input))
  })
  it.each([
    ' ',
    ' answer-A ',
    'answer-a',
    '\t',
  ])('S10 preserves nonempty literal operation key %j', async (operationKey) => {
    const input = s10Input({ operationKey })
    const h = s10Read(s10Success('reuse_existing'), input)
    expect(await h.result).toStrictEqual(s10Success('reuse_existing'))
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith(S10_RPC, s10Args(input))
  })
  it.each([
    null,
    undefined,
    {},
    { rpc: null },
    { rpc: 17 },
  ])('S10 rejects invalid port %# only on invocation', async (port) => {
    const repository = createWorkoutStrengthRepository(
      port as unknown as WorkoutStrengthRepositoryPort,
    )
    await expect(repository.answerConfirmedWorkoutStrength(s10Input())).rejects.toEqual(
      new TypeError('Workout strength port requires a callable rpc'),
    )
  })
  it('S10 propagates the original port getter defect without transport fallback', async () => {
    const failure = new Error('S10 rpc getter defect')
    const getter = vi.fn(() => {
      throw failure
    })
    const port = Object.defineProperty({}, 'rpc', { get: getter }) as WorkoutStrengthRepositoryPort
    const repository = createWorkoutStrengthRepository(port)
    expect(getter).not.toHaveBeenCalled()
    await expect(repository.answerConfirmedWorkoutStrength(s10Input())).rejects.toBe(failure)
    expect(getter).toHaveBeenCalledTimes(1)
  })
})

describe('S10 exact R2 answer branches, correlations and receipt copies', () => {
  it.each([
    ['accepted_yes', 'accepted', 'yes', 0, S10_KEY],
    ['accepted_no', 'accepted', 'no', 0, S10_KEY],
    ['replay_A0_yes', 'reuse_existing', 'yes', 0, S10_KEY],
    ['replay_A0_no', 'reuse_existing', 'no', 0, S10_KEY],
    ['B1_receiptA_yes', 'reuse_existing', 'yes', 1, 'answer-B'],
    ['B1_receiptA_no', 'reuse_existing', 'no', 1, 'answer-B'],
  ] as const)('S10 accepts %s with the exact winning receipt', async (_label, status, answer, expectedFactRevision, operationKey) => {
    const input = s10Input({ answer, expectedFactRevision, operationKey })
    const wire = s10Success(status, answer)
    const h = s10Read(wire, input)
    expect(await h.result).toStrictEqual(wire)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith(S10_RPC, s10Args(input))
    expect(wire.receipt.operationKey).toBe(S10_KEY)
  })
  it.each(
    s10NegativeCases,
  )('S10 accepts declared negative %s/%s without synthesis', async (status, reason) => {
    const wire = { status, reason }
    const h = s10Read(wire)
    const result = await h.result
    expect(result).toStrictEqual(wire)
    expect(result).not.toBe(wire)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each(s10MalformedOuter)('S10 rejects malformed outer result %s', async (_label, wire) => {
    await s10InvalidData(wire)
  })
  it.each(s10ReceiptInvalid)('S10 rejects forged receipt %s', async (_label, key, value) => {
    await s10InvalidData(change(s10Success(), ['receipt.' + key, value]))
  })
  it.each([
    'ownerID',
    'workoutLogID',
    'questionKey',
    'answer',
    'operationKey',
    'acceptedAt',
  ])('S10 rejects a missing receipt field %s', async (key) => {
    await s10InvalidData(change(s10Success(), ['receipt.' + key, MISSING]))
  })
  it('S10 rejects an extra receipt field instead of silently dropping it', async () => {
    await s10InvalidData(change(s10Success(), ['receipt.extra', true]))
  })
  it.each([
    'root',
    'receipt',
  ] as const)('S10 rejects inherited domain fields at %s', async (where) => {
    const wire =
      where === 'root'
        ? Object.create(s10Success())
        : { ...s10Success(), receipt: Object.create(s10Success().receipt) }
    await s10InvalidData(wire)
  })
  it.each([
    '0001-01-01T00:00:00.000000Z',
    '2000-02-29T23:59:59.123456Z',
    '2024-02-29T00:00:00.000001Z',
    '9999-12-31T23:59:59.999999Z',
  ])('S10 preserves exact acceptedAt UTC US6 boundary %s', async (acceptedAt) => {
    const wire = change(s10Success(), ['receipt.acceptedAt', acceptedAt])
    expect(await s10Read(wire).result).toStrictEqual(wire)
  })
  it.each(
    s10BadTimes,
  )('S10 rejects noncanonical or impossible receipt time %#', async (acceptedAt) => {
    await s10InvalidData(change(s10Success(), ['receipt.acceptedAt', acceptedAt]))
  })
})

describe('S10 envelope and uncaught operational/configuration defects', () => {
  it('S10 accepts transport metadata but emits only the copied exact domain object', async () => {
    const wire = s10Success()
    const h = portFor({ data: wire, error: null, status: 200, statusText: 'OK', count: null })
    const result = await h.repository.answerConfirmedWorkoutStrength(s10Input())
    expect(result).toStrictEqual(wire)
    expect(result).not.toBe(wire)
    if (result.status === 'accepted' || result.status === 'reuse_existing')
      expect(result.receipt).not.toBe(wire.receipt)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    false,
    0,
    '',
    { message: 'synthetic private detail must not enter the error' },
  ])('S10 rejects every non-null error %# with the fixed operational error', async (error) => {
    const h = portFor({ data: s10Success(), error })
    await expect(h.repository.answerConfirmedWorkoutStrength(s10Input())).rejects.toEqual(
      new Error('Workout strength RPC failed'),
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    null,
    [],
    {},
    { data: s10Success() },
    { error: null },
    { data: s10Success(), error: undefined },
    Object.create({ data: s10Success(), error: null }),
  ])('S10 rejects malformed or inherited envelope %#', async (reply) => {
    const h = portFor(reply)
    await expect(h.repository.answerConfirmedWorkoutStrength(s10Input())).rejects.toEqual(
      new TypeError('Invalid workout strength reply'),
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'throw',
    'reject',
  ] as const)('S10 propagates the original transport %s object unchanged', async (mode) => {
    const failure = { synthetic: 'S10 original transport object' }
    const h = portFor(null)
    h.rpc.mockImplementation(() => {
      if (mode === 'throw') throw failure
      return Promise.reject(failure)
    })
    await expect(h.repository.answerConfirmedWorkoutStrength(s10Input())).rejects.toBe(failure)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'data',
    'error',
    'status',
    'ownerID',
    'acceptedAt',
  ] as const)('S10 propagates original parser getter defect at %s', async (field) => {
    const failure = new Error('S10 parser getter ' + field)
    const wire = s10Success()
    const reply = { data: wire, error: null }
    const target =
      field === 'data' || field === 'error' ? reply : field === 'status' ? wire : wire.receipt
    Object.defineProperty(target, field, {
      enumerable: true,
      get() {
        throw failure
      },
    })
    const h = portFor(reply)
    await expect(h.repository.answerConfirmedWorkoutStrength(s10Input())).rejects.toBe(failure)
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
})

describe('S10 request snapshots, returned copies and isolated pending calls', () => {
  it('S10 preserves all seven original scalars and RPC args after input mutation during await', async () => {
    const h = portFor(null)
    const gate = deferred<Reply>()
    const entered = deferred<void>()
    h.rpc.mockImplementation(() => {
      entered.resolve(undefined)
      return gate.promise
    })
    const input = s10Input()
    const original = structuredClone(input)
    const result = h.repository.answerConfirmedWorkoutStrength(input)
    input.ownerID = OTHER
    input.expectedLifecycleKey = OTHER
    input.workoutLogID = OTHER
    input.expectedFactRevision = 2
    input.questionKey = OTHER
    input.answer = 'no'
    input.operationKey = 'changed-B'
    await Promise.race([entered.promise, result.then(() => undefined)])
    expect(h.rpc).toHaveBeenCalledTimes(1)
    const args = h.rpc.mock.calls[0]?.[1]
    expect(args).toStrictEqual(s10Args(original))
    gate.resolve({ data: s10Success(), error: null })
    expect(await result).toStrictEqual(s10Success())
    expect(args).toStrictEqual(s10Args(original))
  })
  it('S10 rejects a coherent foreign receipt matching mutated input against the original snapshot', async () => {
    const h = portFor(null)
    const gate = deferred<Reply>()
    h.rpc.mockReturnValue(gate.promise)
    const input = s10Input()
    const original = structuredClone(input)
    const result = h.repository.answerConfirmedWorkoutStrength(input)
    input.ownerID = OTHER
    input.expectedLifecycleKey = OTHER
    input.workoutLogID = OTHER
    input.expectedFactRevision = 1
    input.questionKey = OTHER
    input.answer = 'no'
    input.operationKey = 'foreign-B'
    const wire = change(
      s10Success(),
      ['receipt.ownerID', OTHER],
      ['receipt.workoutLogID', OTHER],
      ['receipt.questionKey', OTHER],
      ['receipt.answer', 'no'],
    )
    gate.resolve({ data: wire, error: null })
    await expect(result).rejects.toEqual(new TypeError('Invalid workout strength reply'))
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith(S10_RPC, s10Args(original))
  })
  it.each([
    ['accepted', s10Success()],
    ['reuse_existing', s10Success('reuse_existing')],
    ['negative', { status: 'conflict', reason: 'stale_fact' }],
  ] as const)('S10 detaches returned %s result from all later port payload mutations', async (_label, wire) => {
    const before = structuredClone(wire)
    const result = await s10Read(wire).result
    expect(result).toStrictEqual(before)
    const root = record(wire)
    if (root.receipt !== undefined) {
      const receipt = record(root.receipt)
      receipt.ownerID = OTHER
      receipt.workoutLogID = OTHER
      receipt.questionKey = OTHER
      receipt.answer = 'no'
      receipt.operationKey = 'changed'
      receipt.acceptedAt = '9999-12-31T23:59:59.999999Z'
    }
    root.status = 'changed'
    root.reason = 'changed'
    expect(result).toStrictEqual(before)
  })
  it('S10 keeps A/B isolated when B completes before A on the same repository', async () => {
    const a = deferred<Reply>()
    const b = deferred<Reply>()
    const h = portFor(null)
    h.rpc.mockReturnValueOnce(a.promise).mockReturnValueOnce(b.promise)
    const inputA = s10Input()
    const inputB = s10Input({
      ownerID: OTHER,
      expectedLifecycleKey: OTHER,
      workoutLogID: OTHER,
      expectedFactRevision: 1,
      questionKey: OTHER,
      answer: 'no',
      operationKey: 'request-B',
    })
    const wireB = change(
      s10Success('reuse_existing', 'no'),
      ['receipt.ownerID', OTHER],
      ['receipt.workoutLogID', OTHER],
      ['receipt.questionKey', OTHER],
      ['receipt.operationKey', 'original-winner-B'],
    )
    const first = h.repository.answerConfirmedWorkoutStrength(inputA)
    const second = h.repository.answerConfirmedWorkoutStrength(inputB)
    b.resolve({ data: wireB, error: null })
    expect(await second).toStrictEqual(wireB)
    a.resolve({ data: s10Success(), error: null })
    expect(await first).toStrictEqual(s10Success())
    expect(h.rpc).toHaveBeenCalledTimes(2)
    expect(h.rpc.mock.calls.map((call) => call)).toStrictEqual([
      [S10_RPC, s10Args(inputA)],
      [S10_RPC, s10Args(inputB)],
    ])
  })
  it('S10 neither retries nor caches a failure and allows a separate subsequent request', async () => {
    const h = portFor(null)
    h.rpc
      .mockReturnValueOnce(Promise.resolve({ data: null, error: false }))
      .mockReturnValueOnce(Promise.resolve({ data: s10Success(), error: null }))
    await expect(h.repository.answerConfirmedWorkoutStrength(s10Input())).rejects.toEqual(
      new Error('Workout strength RPC failed'),
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(await h.repository.answerConfirmedWorkoutStrength(s10Input())).toStrictEqual(
      s10Success(),
    )
    expect(h.rpc).toHaveBeenCalledTimes(2)
  })
})
