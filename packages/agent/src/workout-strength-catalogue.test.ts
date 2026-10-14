/**
 * S2 test-first specification for the auxiliary read-only catalogue observer.
 * Missing module/core subpath is SETUP, not causal RED. No SQL/DB authority,
 * full-set CAS, operation binding, kcal recovery or consumer is proved here.
 * Only the narrow RPC port is faked; S1 is observed with a call-through spy.
 */
import * as classificationCore from '@mpp/core/workout-strength-classification'
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  observeWorkoutStrengthCatalogue,
  type WorkoutStrengthCatalogueObservationResult,
  type WorkoutStrengthCataloguePort,
} from './workout-strength-catalogue.js'

type Reply = Awaited<ReturnType<WorkoutStrengthCataloguePort['rpc']>>
type Category = 'musculacao' | 'cardio' | 'esporte' | 'mobilidade'
type WireRow = {
  id: string
  slug: string
  displayName: string
  category: Category
  isActive: true
  updatedAtLiteral: string
}
type AvailableWire = {
  status: 'available'
  observationKey: string
  observedAt: string
  matcherVersion: 'active_slug_then_unique_canonical_display_v1'
  complete: boolean
  rowCount: string
  activeRows: WireRow[]
}
const RAW = '  MÚSCULAÇÃO\t'
const OBSERVATION = {
  observationKey: 'c59a4000-0000-0000-0000-000000000009',
  observedAt: '2026-10-14T21:00:00.000009Z',
  matcherVersion: 'active_slug_then_unique_canonical_display_v1' as const,
}
function strengthRow(): WireRow {
  return {
    id: 'c59a4000-0000-0000-0000-000000000001',
    slug: 'musculacao',
    displayName: 'Musculação',
    category: 'musculacao',
    isActive: true,
    updatedAtLiteral: '2026-10-14T20:59:59.000001Z',
  }
}
function cardioRow(): WireRow {
  return {
    id: 'c59a4000-0000-0000-0000-000000000002',
    slug: 'natacao',
    displayName: 'Natação',
    category: 'cardio',
    isActive: true,
    updatedAtLiteral: '2026-10-14T20:59:59.000002Z',
  }
}
function available(rows: WireRow[] = [strengthRow(), cardioRow()]): AvailableWire {
  return {
    status: 'available',
    ...OBSERVATION,
    complete: true,
    rowCount: String(rows.length),
    activeRows: rows,
  }
}
/** Deliberately malformed responses stay at the declared unknown RPC boundary. */
function portFor(reply: unknown) {
  const rpc = vi
    .fn<WorkoutStrengthCataloguePort['rpc']>()
    .mockImplementation(() => Promise.resolve(reply as Reply))
  const createClient = vi.fn((): WorkoutStrengthCataloguePort => ({ rpc }))
  return { rpc, createClient }
}
function observeData(data: unknown, rawType = RAW) {
  const port = portFor({ data, error: null })
  return {
    ...port,
    result: observeWorkoutStrengthCatalogue(rawType, {
      enabled: true,
      createClient: port.createClient,
    }),
  }
}
function unavailable(
  rawType: string,
  reason: 'catalogue_read_error' | 'catalogue_invalid' | 'catalogue_incomplete',
) {
  return {
    status: 'observed',
    originalOperationType: rawType,
    read: { status: 'unavailable', reason },
    classification: { status: 'unavailable', reason },
  }
}
function requireObserved(result: WorkoutStrengthCatalogueObservationResult) {
  expect(result.status).toBe('observed')
  if (result.status !== 'observed') throw new Error('Expected an observed result after assertion')
  return result
}
afterEach(() => {
  vi.restoreAllMocks()
})

describe('observeWorkoutStrengthCatalogue: lazy OFF and exact auxiliary port', () => {
  it.each([
    {},
    { enabled: undefined },
    { enabled: false },
  ])('returns only disabled before factory/RPC/classifier for OFF option %#', async (enabledOption) => {
    const rpc = vi.fn<WorkoutStrengthCataloguePort['rpc']>()
    const createClient = vi.fn((): WorkoutStrengthCataloguePort => ({ rpc }))
    const classify = vi.spyOn(classificationCore, 'classifyConfirmedWorkoutType')
    expect(
      await observeWorkoutStrengthCatalogue(RAW, { ...enabledOption, createClient }),
    ).toStrictEqual({ status: 'disabled' })
    expect(createClient).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
    expect(classify).not.toHaveBeenCalled()
  })

  it('uses one factory, exactly one named empty-args RPC and the real S1 classifier', async () => {
    const wire = available()
    const { rpc, createClient } = portFor({
      data: wire,
      error: null,
      status: 200,
      statusText: 'OK',
      count: null,
    })
    const classify = vi.spyOn(classificationCore, 'classifyConfirmedWorkoutType')
    const result = requireObserved(
      await observeWorkoutStrengthCatalogue(RAW, { enabled: true, createClient }),
    )
    const read = { status: 'complete', observation: OBSERVATION, activeRows: wire.activeRows }
    expect(result).toStrictEqual({
      status: 'observed',
      originalOperationType: RAW,
      read,
      classification: {
        status: 'matched',
        observation: OBSERVATION,
        method: 'active_slug',
        catalogue: strengthRow(),
      },
    })
    expect(createClient).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('get_workout_strength_catalogue_context', {})
    expect(classify).toHaveBeenCalledTimes(1)
    expect(classify).toHaveBeenCalledWith(RAW, read)
  })

  it('accepts the PromiseLike port shape used by a Supabase builder without importing an SDK', async () => {
    const reply = { data: available(), error: null }
    const thenable: PromiseLike<Reply> = {
      // biome-ignore lint/suspicious/noThenProperty: Exercise the intentional PromiseLike RPC builder contract without an SDK.
      then(onfulfilled, onrejected) {
        return Promise.resolve(reply).then(onfulfilled, onrejected)
      },
    }
    const port = portFor(null)
    port.rpc.mockReturnValue(thenable)
    const result = requireObserved(
      await observeWorkoutStrengthCatalogue('musculacao', {
        enabled: true,
        createClient: port.createClient,
      }),
    )
    expect(result.classification.status).toBe('matched')
    expect(port.rpc).toHaveBeenCalledTimes(1)
  })
})

describe('auxiliary errors are bounded away from configuration/parser/classifier defects', () => {
  it('propagates factory failure without mapping it to catalogue_read_error', async () => {
    const failure = new Error('synthetic factory configuration failure')
    const createClient = vi.fn((): WorkoutStrengthCataloguePort => {
      throw failure
    })
    await expect(
      observeWorkoutStrengthCatalogue(RAW, { enabled: true, createClient }),
    ).rejects.toBe(failure)
    expect(createClient).toHaveBeenCalledTimes(1)
  })

  it('propagates a non-callable port rpc as configuration failure', async () => {
    const createClient = vi.fn(
      () => ({ rpc: undefined }) as unknown as WorkoutStrengthCataloguePort,
    )
    await expect(
      observeWorkoutStrengthCatalogue(RAW, { enabled: true, createClient }),
    ).rejects.toThrow()
  })

  it.each([
    'throw',
    'reject',
  ] as const)('maps only an auxiliary RPC %s to read_error without retry', async (kind) => {
    const failure = new Error('synthetic auxiliary read failure')
    const port = portFor(null)
    if (kind === 'throw')
      port.rpc.mockImplementation(() => {
        throw failure
      })
    else port.rpc.mockRejectedValue(failure)
    expect(
      await observeWorkoutStrengthCatalogue('outro', {
        enabled: true,
        createClient: port.createClient,
      }),
    ).toStrictEqual(unavailable('outro', 'catalogue_read_error'))
    expect(port.rpc).toHaveBeenCalledTimes(1)
  })

  it('gives an explicit non-null RPC error priority over valid positive data and does not log its body', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined)
    const error = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const port = portFor({ data: available(), error: { message: 'synthetic private error body' } })
    expect(
      await observeWorkoutStrengthCatalogue(RAW, {
        enabled: true,
        createClient: port.createClient,
      }),
    ).toStrictEqual(unavailable(RAW, 'catalogue_read_error'))
    expect(port.rpc).toHaveBeenCalledTimes(1)
    expect(warn).not.toHaveBeenCalled()
    expect(error).not.toHaveBeenCalled()
  })

  it('treats an explicitly non-null falsy error as read_error, not successful data', async () => {
    const port = portFor({ data: available(), error: false })
    expect(
      await observeWorkoutStrengthCatalogue(RAW, {
        enabled: true,
        createClient: port.createClient,
      }),
    ).toStrictEqual(unavailable(RAW, 'catalogue_read_error'))
    expect(port.rpc).toHaveBeenCalledTimes(1)
  })

  it('does not catch an internal parser defect after the fulfilled RPC returns', async () => {
    const failure = new Error('synthetic parser defect sentinel')
    const data = Object.defineProperty(available(), 'status', {
      enumerable: true,
      get() {
        throw failure
      },
    })
    await expect(observeData(data).result).rejects.toBe(failure)
  })

  it('does not catch a classifier defect after a valid read', async () => {
    const failure = new Error('synthetic classifier defect sentinel')
    vi.spyOn(classificationCore, 'classifyConfirmedWorkoutType').mockImplementationOnce(() => {
      throw failure
    })
    await expect(observeData(available()).result).rejects.toBe(failure)
  })
})

describe('strict transport/data shape and unavailable precedence', () => {
  it.each([
    null,
    [],
    {},
    { data: available() },
    { error: null },
    { data: available(), error: undefined },
    { data: undefined, error: null },
  ])('refuses malformed transport envelope %# instead of treating it as a catalogue miss', async (reply) => {
    const port = portFor(reply)
    expect(
      await observeWorkoutStrengthCatalogue(RAW, {
        enabled: true,
        createClient: port.createClient,
      }),
    ).toStrictEqual(unavailable(RAW, 'catalogue_invalid'))
    expect(port.rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    'catalogue_read_error',
    'catalogue_invalid',
    'catalogue_incomplete',
  ] as const)('preserves explicit wire unavailable %s even for the generic literal', async (reason) => {
    expect(await observeData({ status: 'unavailable', reason }, 'outro').result).toStrictEqual(
      unavailable('outro', reason),
    )
  })

  it.each([
    null,
    [],
    {},
    { status: 'unavailable', reason: 'legacy_provenance_gap' },
    { status: 'unavailable', reason: 'catalogue_incomplete', activeRows: [] },
    { ...available(), status: 'complete' },
    { ...available(), matcherVersion: 'fuzzy_v2' },
    { ...available(), extra: 'patient_category' },
    { ...available(), observationKey: OBSERVATION.observationKey.toUpperCase() },
    { ...available(), observationKey: 'not-a-uuid' },
    { ...available(), complete: 'true' },
    { ...available(), activeRows: null },
  ])('refuses invalid strict wire data %# before outro or a matching slug', async (data) => {
    expect(await observeData(data, 'outro').result).toStrictEqual(
      unavailable('outro', 'catalogue_invalid'),
    )
  })

  it('accepts a valid complete empty set as proven no_active_match', async () => {
    expect(await observeData(available([]), 'Natação').result).toStrictEqual({
      status: 'observed',
      originalOperationType: 'Natação',
      read: { status: 'complete', observation: OBSERVATION, activeRows: [] },
      classification: {
        status: 'unrecognized',
        observation: OBSERVATION,
        reason: 'no_active_match',
      },
    })
  })

  it('requires exact available data keys, including keys unused by a direct slug match', async () => {
    const missing: Record<string, unknown> = { ...available() }
    delete missing.complete
    expect(await observeData(missing).result).toStrictEqual(unavailable(RAW, 'catalogue_invalid'))
  })
})

describe('whole active set, exact DB literals and no invented vocabulary constraints', () => {
  it.each([
    'musculacao',
    'cardio',
    'esporte',
    'mobilidade',
  ] as const)('parses category %s as a real row field rather than guessing from the typed name', async (category) => {
    const row = { ...strengthRow(), category }
    const result = requireObserved(await observeData(available([row])).result)
    expect(result.classification).toStrictEqual({
      status: 'matched',
      observation: OBSERVATION,
      method: 'active_slug',
      catalogue: row,
    })
  })

  it.each([
    { ...cardioRow(), category: 'strength' },
    { ...cardioRow(), isActive: false },
    { ...cardioRow(), isActive: 'true' },
    { ...cardioRow(), id: cardioRow().id.toUpperCase() },
    { ...cardioRow(), displayName: null },
    { ...cardioRow(), slug: 7 },
    { ...cardioRow(), extra: 'not-a-row-field' },
  ])('validates trailing row %# before accepting the first matching row', async (badRow) => {
    expect(
      await observeData({ ...available(), activeRows: [strengthRow(), badRow] }).result,
    ).toStrictEqual(unavailable(RAW, 'catalogue_invalid'))
  })

  it.each([
    'id',
    'slug',
    'displayName',
    'category',
    'isActive',
    'updatedAtLiteral',
  ])('requires row key %s without weakening data to a partial read', async (key) => {
    const badRow: Record<string, unknown> = { ...strengthRow() }
    delete badRow[key]
    expect(await observeData(available([badRow as unknown as WireRow])).result).toStrictEqual(
      unavailable(RAW, 'catalogue_invalid'),
    )
  })

  it.each([
    [cardioRow(), strengthRow()],
    [strengthRow(), { ...cardioRow(), id: strengthRow().id }],
    [strengthRow(), { ...cardioRow(), slug: strengthRow().slug }],
  ])('rejects descending/duplicate IDs or duplicate literal slug %#', async (first, second) => {
    expect(await observeData(available([first, second])).result).toStrictEqual(
      unavailable(RAW, 'catalogue_invalid'),
    )
  })

  it('allows DB-valid empty text and distinct literal slugs differing only in case', async () => {
    const row = { ...cardioRow(), slug: 'MUSCULACAO', displayName: '' }
    const third = {
      ...cardioRow(),
      id: 'c59a4000-0000-0000-0000-000000000003',
      slug: '',
      displayName: '',
    }
    const result = requireObserved(await observeData(available([strengthRow(), row, third])).result)
    expect(result.read).toStrictEqual({
      status: 'complete',
      observation: OBSERVATION,
      activeRows: [strengthRow(), row, third],
    })
    expect(result.classification).toStrictEqual({
      status: 'matched',
      observation: OBSERVATION,
      method: 'active_slug',
      catalogue: strengthRow(),
    })
  })
})

describe('UTC US6 manual civil validation without rounding or new chronological policy', () => {
  it.each([
    '0001-01-01T00:00:00.000000Z',
    '2000-02-29T23:59:59.123456Z',
    '2024-02-29T00:00:00.000001Z',
    '9999-12-31T23:59:59.999999Z',
  ])('accepts the exact valid UTC literal %s without requiring UUIDv4 or a recent date', async (observedAt) => {
    const wire = { ...available(), observedAt }
    const result = requireObserved(await observeData(wire).result)
    expect(result.read).toMatchObject({ observation: { observedAt } })
    expect(result.classification).toMatchObject({ observation: { observedAt } })
  })

  it.each([
    '0000-01-01T00:00:00.000000Z',
    '10000-01-01T00:00:00.000000Z',
    '1900-02-29T00:00:00.000000Z',
    '2100-02-29T00:00:00.000000Z',
    '2026-04-31T00:00:00.000000Z',
    '2026-13-01T00:00:00.000000Z',
    '2026-01-00T00:00:00.000000Z',
    '2026-10-14T24:00:00.000000Z',
    '2026-10-14T00:60:00.000000Z',
    '2026-10-14T00:00:60.000000Z',
    '2026-10-14T00:00:00.00000Z',
    '2026-10-14T00:00:00.0000000Z',
    '2026-10-14T00:00:00.000000+00:00',
    '2026-10-14T00:00:00.000000z',
  ])('refuses invalid/noncanonical observedAt %s', async (observedAt) => {
    expect(await observeData({ ...available(), observedAt }).result).toStrictEqual(
      unavailable(RAW, 'catalogue_invalid'),
    )
  })

  it('validates row updatedAtLiteral too, even when another row already matches', async () => {
    const trailing = { ...cardioRow(), updatedAtLiteral: '2026-02-30T00:00:00.000000Z' }
    expect(await observeData(available([strengthRow(), trailing])).result).toStrictEqual(
      unavailable(RAW, 'catalogue_invalid'),
    )
  })

  it('preserves both sixth-decimal literals and permits a row timestamp after observedAt', async () => {
    const first = { ...strengthRow(), updatedAtLiteral: '2026-10-15T00:00:00.000001Z' }
    const second = { ...cardioRow(), updatedAtLiteral: '2026-10-15T00:00:00.000002Z' }
    const result = requireObserved(await observeData(available([first, second])).result)
    expect(result.read).toStrictEqual({
      status: 'complete',
      observation: OBSERVATION,
      activeRows: [first, second],
    })
    expect(result.classification).toStrictEqual({
      status: 'matched',
      observation: OBSERVATION,
      method: 'active_slug',
      catalogue: first,
    })
  })
})

describe('canonical exact rowCount and precedence of malformed versus partial', () => {
  it.each([
    2,
    '02',
    '+2',
    '-2',
    '2.0',
    ' 2',
    '2e0',
    '',
  ])('rejects noncanonical decimal rowCount %s', async (rowCount) => {
    expect(await observeData({ ...available(), rowCount }).result).toStrictEqual(
      unavailable(RAW, 'catalogue_invalid'),
    )
  })

  it('treats count below the real array length as invalid, even with complete false', async () => {
    expect(
      await observeData({ ...available(), complete: false, rowCount: '1' }).result,
    ).toStrictEqual(unavailable(RAW, 'catalogue_invalid'))
  })

  it.each([
    '3',
    '9007199254740993',
    '9'.repeat(400),
  ])('keeps large canonical count %s above the supplied set incomplete', async (rowCount) => {
    expect(await observeData({ ...available(), rowCount }, 'outro').result).toStrictEqual(
      unavailable('outro', 'catalogue_incomplete'),
    )
  })

  it('keeps complete false incomplete even when count equals the supplied set', async () => {
    expect(await observeData({ ...available(), complete: false }, 'outro').result).toStrictEqual(
      unavailable('outro', 'catalogue_incomplete'),
    )
  })

  it('validates every row before incomplete/outro instead of suppressing malformed trailing data', async () => {
    expect(
      await observeData(
        {
          ...available(),
          complete: false,
          rowCount: '3',
          activeRows: [strengthRow(), { ...cardioRow(), category: 'unknown' }],
        },
        'outro',
      ).result,
    ).toStrictEqual(unavailable('outro', 'catalogue_invalid'))
  })
})

describe('raw operation type and returned observations do not alias transport data', () => {
  it('copies only declared read fields and leaves rawType/payload unchanged during parsing', async () => {
    const wire = available()
    const before = JSON.stringify(wire)
    const result = requireObserved(await observeData(wire).result)
    expect(result.originalOperationType).toBe(RAW)
    expect(RAW).toBe('  MÚSCULAÇÃO\t')
    expect(JSON.stringify(wire)).toBe(before)
    expect(result.read).toStrictEqual({
      status: 'complete',
      observation: OBSERVATION,
      activeRows: wire.activeRows,
    })
    expect(Object.keys(result).sort()).toStrictEqual([
      'classification',
      'originalOperationType',
      'read',
      'status',
    ])
  })

  it('does not let later payload mutation rewrite the returned read or S1 classification', async () => {
    const wire = available()
    const expectedRows = wire.activeRows.map((row) => ({ ...row }))
    const result = requireObserved(await observeData(wire).result)
    const firstRow = wire.activeRows[0]
    if (firstRow === undefined) throw new Error('S2_SETUP_FIRST_ROW_MISSING')
    wire.observedAt = '2026-10-16T00:00:00.000000Z'
    firstRow.category = 'mobilidade'
    firstRow.updatedAtLiteral = '2026-10-16T01:02:03.999999Z'
    wire.activeRows.push({
      ...cardioRow(),
      id: 'c59a4000-0000-0000-0000-000000000003',
      slug: 'other',
    })
    expect(result.read).toStrictEqual({
      status: 'complete',
      observation: OBSERVATION,
      activeRows: expectedRows,
    })
    expect(result.classification).toStrictEqual({
      status: 'matched',
      observation: OBSERVATION,
      method: 'active_slug',
      catalogue: strengthRow(),
    })
  })
})
