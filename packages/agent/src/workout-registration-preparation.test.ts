import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from './calc-config-loader.js'
import type { ToolContext } from './tools/types.js'
import { registraTreino } from './tools.js'
import {
  prepareWorkoutRegistration,
  type WorkoutRegistrationArguments,
  type WorkoutRegistrationPreparation,
} from './workout-registration-preparation.js'

const USER = 'c59b7000-0000-0000-0000-000000000017'
const NOW = new Date('2026-10-15T12:00:00.000Z')
const REFERENCE = new Date('2026-10-04T02:30:00.123Z')
const TODAY = '2026-10-03'
const RAW = 'Natação 🏋️ e\u0301'
const PROVIDER = 'wamid.S17A:literal'
const ARGS: WorkoutRegistrationArguments = {
  workout_type: RAW,
  duration_min: 40,
  intensity: 'moderada',
}
type Stage = 'correction' | 'config' | 'targets' | 'weight' | 'kcal'
type DbError = { message?: string }
type Step = [method: string, ...args: unknown[]]
type Reply = { data: unknown; error: DbError | null }
interface Recorded {
  kind: 'from' | 'rpc'
  target: string
  steps?: Step[]
  params?: Record<string, unknown>
}
interface Options {
  targetProfile?: Record<string, unknown> | null
  weightProfile?: Record<string, unknown> | null
  oldRows?: Array<{ id: string; estimated_kcal: number | null; duration_min: number | null }> | null
  kcal?: number | null
  fault?: { stage: Stage; error: DbError }
  rpcRejection?: Error
  eventError?: DbError
  eventRejection?: Error
  onConfigRead?: () => void
}

/** Only the transport is fake; all preparation/config/target/detector code is real. */
function recordingClient(options: Options = {}) {
  const calls: Recorded[] = []
  function response(table: string, steps: Step[]): Reply {
    const select = steps.find(([method]) => method === 'select')?.[1]
    let stage: Stage
    let data: unknown
    if (table === 'global_config') {
      stage = 'config'
      options.onConfigRead?.()
      data = []
    } else if (table === 'user_profiles') {
      stage = select === 'weight_kg' ? 'weight' : 'targets'
      data =
        stage === 'weight'
          ? Object.hasOwn(options, 'weightProfile')
            ? options.weightProfile
            : { weight_kg: 70 }
          : Object.hasOwn(options, 'targetProfile')
            ? options.targetProfile
            : { weight_kg: 70 }
    } else if (table === 'workout_logs') {
      stage = 'correction'
      if (
        steps.some(
          ([method, column]) =>
            method === 'limit' ||
            (method === 'eq' &&
              ['raw_provider_message_id', 'duration_min'].includes(String(column))),
        )
      ) {
        throw new Error('preparation must not perform the tool early dedup')
      }
      data = options.oldRows ?? []
    } else {
      throw new Error('unexpected preparation table ' + table)
    }
    return { data, error: options.fault?.stage === stage ? options.fault.error : null }
  }
  const client = {
    from(table: string) {
      const steps: Step[] = []
      calls.push({ kind: 'from', target: table, steps })
      const builder: Record<string, unknown> = {}
      for (const method of ['select', 'eq', 'gte', 'like']) {
        builder[method] = (...args: unknown[]) => {
          steps.push([method, ...args])
          return builder
        }
      }
      builder.maybeSingle = () => {
        steps.push(['maybeSingle'])
        return Promise.resolve(response(table, steps))
      }
      builder.insert = (row: unknown) => {
        steps.push(['insert', row])
        if (table !== 'product_events') throw new Error('unexpected preparation write ' + table)
        return options.eventRejection
          ? Promise.reject(options.eventRejection)
          : Promise.resolve({ data: null, error: options.eventError ?? null })
      }
      // biome-ignore lint/suspicious/noThenProperty: mirrors the awaitable PostgREST transport
      builder.then = (
        onFulfilled: (value: Reply) => unknown,
        onRejected?: (reason: unknown) => unknown,
      ) => Promise.resolve(response(table, steps)).then(onFulfilled, onRejected)
      return builder
    },
    rpc(name: string, params: Record<string, unknown>) {
      calls.push({ kind: 'rpc', target: name, params: { ...params } })
      if (name !== 'calc_workout_kcal') throw new Error('unexpected preparation RPC ' + name)
      if (options.rpcRejection) return Promise.reject(options.rpcRejection)
      return Promise.resolve({
        data: Object.hasOwn(options, 'kcal') ? options.kcal : 240,
        error: options.fault?.stage === 'kcal' ? options.fault.error : null,
      })
    },
  }
  return { calls, client: client as unknown as ServiceClient }
}
function context(client: ServiceClient, extra: Partial<ToolContext> = {}): ToolContext {
  return {
    supabase: client,
    userId: USER,
    userWpp: '5511999999917',
    userTimezone: 'America/Sao_Paulo',
    providerMessageId: PROVIDER,
    ...extra,
  }
}
function arguments13(overrides: Partial<WorkoutRegistrationPreparation['legacyArguments']> = {}) {
  return {
    p_user_id: USER,
    p_date: TODAY,
    p_workout_type: RAW,
    p_duration_min: 40,
    p_estimated_kcal: 240,
    p_intensity: 'moderada',
    p_notes: '[kcal_source=formula, formula=240, image=n/a]',
    p_performed_at: '2026-10-04T02:30:00.123Z',
    p_provider_message_id: PROVIDER,
    p_calories_target: null,
    p_protein_target: null,
    p_replace_recent: false,
    p_replace_since: null,
    ...overrides,
  }
}
function baseCalls(): Recorded[] {
  return [
    {
      kind: 'from',
      target: 'global_config',
      steps: [
        ['select', 'key, value'],
        ['like', 'key', 'calc.%'],
      ],
    },
    {
      kind: 'from',
      target: 'user_profiles',
      steps: [
        [
          'select',
          'sex, birth_date, height_cm, weight_kg, body_fat_percent, activity_level, training_frequency, water_intake, hunger_level, current_protocol, goal_type, goal_value, deficit_level',
        ],
        ['eq', 'user_id', USER],
        ['maybeSingle'],
      ],
    },
    {
      kind: 'from',
      target: 'user_profiles',
      steps: [['select', 'weight_kg'], ['eq', 'user_id', USER], ['maybeSingle']],
    },
    {
      kind: 'rpc',
      target: 'calc_workout_kcal',
      params: {
        p_slug: RAW,
        p_duration_min: 40,
        p_intensity: 'moderada',
        p_weight_kg: 70,
      },
    },
  ]
}
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
})
afterEach(() => {
  clearCalcConfigCache()
  vi.useRealTimers()
})

describe('prepareWorkoutRegistration — actual preparation, never confirmation', () => {
  it('returns exact thirteen legacy arguments and six preparation fields with literal call order', async () => {
    const h = recordingClient()
    const result: WorkoutRegistrationPreparation = await prepareWorkoutRegistration(
      ARGS,
      context(h.client),
      REFERENCE,
      TODAY,
    )
    expect(result).toEqual({
      legacyArguments: arguments13(),
      replacementAudit: null,
      finalKcal: 240,
      kcalSource: 'formula',
      formulaKcal: 240,
      imageDiscarded: false,
    })
    expect(Object.keys(result.legacyArguments)).toHaveLength(13)
    expect(result).not.toHaveProperty('success')
    expect(result).not.toHaveProperty('deduped')
    expect(h.calls).toEqual(baseCalls())
  })

  it.each([
    undefined,
    'natacao',
  ])('keeps raw Unicode and all write fields when kcal lookup slug is %s', async (slug) => {
    const h = recordingClient()
    const result = await prepareWorkoutRegistration(
      ARGS,
      context(h.client, { workoutKcalLookupSlug: slug }),
      REFERENCE,
      TODAY,
    )
    expect(result.legacyArguments).toEqual(arguments13())
    expect(h.calls.at(-1)).toEqual({
      kind: 'rpc',
      target: 'calc_workout_kcal',
      params: { p_slug: slug ?? RAW, p_duration_min: 40, p_intensity: 'moderada', p_weight_kg: 70 },
    })
    expect(result.legacyArguments.p_workout_type).toBe('Natação 🏋️ e\u0301')
  })

  it.each([
    { name: 'missing weight property', profile: {} },
    { name: 'null weight property', profile: { weight_kg: null } },
    { name: 'null profile', profile: null },
    { name: 'undefined profile', profile: undefined },
  ])('uses 70 only for $name and keeps absent intensity/provider NULL in write', async ({
    profile,
  }) => {
    const h = recordingClient({ weightProfile: profile })
    const result = await prepareWorkoutRegistration(
      { workout_type: RAW, duration_min: 40 },
      context(h.client, { providerMessageId: undefined }),
      REFERENCE,
      TODAY,
    )
    expect(result.legacyArguments).toEqual(
      arguments13({ p_intensity: null, p_provider_message_id: null }),
    )
    expect(h.calls.at(-1)?.params).toEqual({
      p_slug: RAW,
      p_duration_min: 40,
      p_intensity: 'moderada',
      p_weight_kg: 70,
    })
  })

  it('converts a successful SQL NULL formula to zero without declaring a write', async () => {
    const h = recordingClient({ kcal: null })
    const result = await prepareWorkoutRegistration(ARGS, context(h.client), REFERENCE, TODAY)
    expect(result).toEqual({
      legacyArguments: arguments13({
        p_estimated_kcal: 0,
        p_notes: '[kcal_source=formula, formula=0, image=n/a]',
      }),
      replacementAudit: null,
      finalKcal: 0,
      kcalSource: 'formula',
      formulaKcal: 0,
      imageDiscarded: false,
    })
    expect(h.calls.map((c) => c.target)).toEqual([
      'global_config',
      'user_profiles',
      'user_profiles',
      'calc_workout_kcal',
    ])
  })

  it.each([
    { notes: undefined, expected: '[kcal_source=formula, formula=240, image=n/a]' },
    { notes: '', expected: '[kcal_source=formula, formula=240, image=n/a]' },
    { notes: '  sessão 🏋️  ', expected: '  sessão 🏋️   [src=formula]' },
  ])('preserves current notes formatting: $notes', async ({ notes, expected }) => {
    const h = recordingClient()
    const result = await prepareWorkoutRegistration(
      { ...ARGS, notes },
      context(h.client),
      REFERENCE,
      TODAY,
    )
    expect(result.legacyArguments).toEqual(arguments13({ p_notes: expected }))
    expect(h.calls).toEqual(baseCalls())
  })

  it.each([
    {
      name: 'inclusive lower',
      formula: 400,
      image: 40,
      final: 40,
      source: 'image',
      discarded: false,
      ratio: 0.1,
    },
    {
      name: 'inclusive upper',
      formula: 400,
      image: 1200,
      final: 1200,
      source: 'image',
      discarded: false,
      ratio: 3,
    },
    {
      name: 'below lower',
      formula: 400,
      image: 39,
      final: 400,
      source: 'formula',
      discarded: true,
      ratio: 0.1,
    },
    {
      name: 'above upper',
      formula: 400,
      image: 1201,
      final: 400,
      source: 'formula',
      discarded: true,
      ratio: 3,
    },
    {
      name: 'round accepted image',
      formula: 400,
      image: 100.5,
      final: 101,
      source: 'image',
      discarded: false,
      ratio: 0.25,
    },
    {
      name: 'zero formula lower',
      formula: 0,
      image: 0.1,
      final: 0,
      source: 'image',
      discarded: false,
      ratio: 0.1,
    },
    {
      name: 'zero formula upper',
      formula: 0,
      image: 3,
      final: 3,
      source: 'image',
      discarded: false,
      ratio: 3,
    },
    {
      name: 'zero formula above',
      formula: 0,
      image: 3.01,
      final: 0,
      source: 'formula',
      discarded: true,
      ratio: 3.01,
    },
  ])('preserves image ratio/rounding/event: $name', async (c) => {
    const h = recordingClient({ kcal: c.formula })
    const result = await prepareWorkoutRegistration(
      { ...ARGS, estimated_kcal_from_image: c.image },
      context(h.client),
      REFERENCE,
      TODAY,
    )
    expect(result).toEqual({
      legacyArguments: arguments13({
        p_estimated_kcal: c.final,
        p_notes: '[kcal_source=' + c.source + ', formula=' + c.formula + ', image=' + c.image + ']',
      }),
      replacementAudit: null,
      finalKcal: c.final,
      kcalSource: c.source,
      formulaKcal: c.formula,
      imageDiscarded: c.discarded,
    })
    expect(h.calls.slice(0, -1)).toEqual(baseCalls())
    expect(h.calls.at(-1)).toEqual({
      kind: 'from',
      target: 'product_events',
      steps: [
        [
          'insert',
          {
            user_id: USER,
            event: c.discarded ? 'workout.kcal_image_discarded' : 'workout.kcal_image_used',
            properties: {
              workout_type: RAW,
              duration_min: 40,
              intensity: 'moderada',
              weight_kg: 70,
              formula_kcal: c.formula,
              image_kcal: c.image,
              ratio: c.ratio,
              chosen: c.source,
            },
          },
        ],
      ],
    })
  })

  it.each([
    {
      name: 'real rows',
      rows: [
        { id: 'old-A', estimated_kcal: 165, duration_min: 60 },
        { id: 'old-B', estimated_kcal: null, duration_min: null },
      ],
      replace: true,
    },
    { name: 'empty rows', rows: [], replace: false },
    { name: 'NULL rows', rows: null, replace: false },
  ])('collects correction with the two-hour now cutoff, without performing replacement: $name', async ({
    rows,
    replace,
  }) => {
    const h = recordingClient({ oldRows: rows })
    const result = await prepareWorkoutRegistration(
      ARGS,
      context(h.client, { recentUserMessages: ['Correção: a natação foi 40 minutos'] }),
      REFERENCE,
      TODAY,
    )
    expect(result.legacyArguments).toEqual(
      arguments13({
        p_replace_recent: replace,
        p_replace_since: replace ? '2026-10-15T10:00:00.000Z' : null,
      }),
    )
    expect(result.replacementAudit).toEqual(
      replace ? { correctionWord: 'Correção', oldRows: rows } : null,
    )
    expect(h.calls).toEqual([
      {
        kind: 'from',
        target: 'workout_logs',
        steps: [
          ['select', 'id, estimated_kcal, duration_min'],
          ['eq', 'user_id', USER],
          ['eq', 'workout_type', RAW],
          ['gte', 'created_at', '2026-10-15T10:00:00.000Z'],
        ],
      },
      ...baseCalls(),
    ])
  })

  it('passes the official non-NULL daily targets and distinct weight from the real loaders', async () => {
    const h = recordingClient({
      targetProfile: {
        sex: 'masculino',
        birth_date: '1990-01-01',
        height_cm: 180,
        weight_kg: 80,
        body_fat_percent: 20,
        activity_level: 'sedentario',
        training_frequency: 0,
        water_intake: null,
        hunger_level: 'pouca',
        current_protocol: 'recomposicao',
        goal_type: null,
        goal_value: null,
        deficit_level: 400,
      },
      weightProfile: { weight_kg: 83.25 },
    })
    const result = await prepareWorkoutRegistration(ARGS, context(h.client), REFERENCE, TODAY)
    // Canonical core: (370 + 21.6*64)*1.2 -400 rounds1703; 80*1.5 =120.
    expect(result.legacyArguments).toEqual(
      arguments13({ p_calories_target: 1703, p_protein_target: 120 }),
    )
    expect(h.calls.at(-1)?.params?.p_weight_kg).toBe(83.25)
  })

  it('keeps the explicit reference/day even when the first awaited lookup crosses days', async () => {
    const h = recordingClient({
      onConfigRead: () => vi.setSystemTime(new Date('2026-10-18T12:00:00Z')),
    })
    const result = await prepareWorkoutRegistration(
      ARGS,
      context(h.client, { referenceTimestamp: new Date('2030-01-01T00:00:00Z') }),
      REFERENCE,
      TODAY,
    )
    expect(result.legacyArguments).toEqual(arguments13())
    expect(h.calls).toEqual(baseCalls())
  })

  it.each([
    {
      stage: 'correction',
      error: { message: 'correction sentinel' },
      message: 'correction sentinel',
      last: 'workout_logs',
    },
    {
      stage: 'correction',
      error: {},
      message: 'recent workout lookup failed',
      last: 'workout_logs',
    },
    {
      stage: 'config',
      error: { message: 'config sentinel' },
      message: 'config sentinel',
      last: 'global_config',
    },
    {
      stage: 'config',
      error: {},
      message: 'calculation config lookup failed',
      last: 'global_config',
    },
    {
      stage: 'targets',
      error: { message: 'targets sentinel' },
      message: 'targets sentinel',
      last: 'user_profiles',
    },
    { stage: 'targets', error: {}, message: 'profile lookup failed', last: 'user_profiles' },
    {
      stage: 'weight',
      error: { message: 'weight sentinel' },
      message: 'weight sentinel',
      last: 'user_profiles',
    },
    { stage: 'weight', error: {}, message: 'workout profile lookup failed', last: 'user_profiles' },
    {
      stage: 'kcal',
      error: { message: 'kcal sentinel' },
      message: 'kcal sentinel',
      last: 'calc_workout_kcal',
    },
    { stage: 'kcal', error: {}, message: 'calc_workout_kcal failed', last: 'calc_workout_kcal' },
  ] satisfies Array<{
    stage: Stage
    error: DbError
    message: string
    last: string
  }>)('propagates $stage errors before later work: $message', async ({
    stage,
    error,
    message,
    last,
  }) => {
    const h = recordingClient({ fault: { stage, error } })
    const c = context(
      h.client,
      stage === 'correction' ? { recentUserMessages: ['Correção: natação'] } : {},
    )
    await expect(prepareWorkoutRegistration(ARGS, c, REFERENCE, TODAY)).rejects.toThrow(message)
    expect(h.calls.at(-1)?.target).toBe(last)
    expect(h.calls.some((call) => call.target === 'register_workout_atomic')).toBe(false)
    expect(h.calls.some((call) => call.target === 'product_events')).toBe(false)
  })

  it('preserves a rejected calculation transport error by identity', async () => {
    const sentinel = new Error('transport sentinel')
    const h = recordingClient({ rpcRejection: sentinel })
    await expect(
      prepareWorkoutRegistration(ARGS, context(h.client), REFERENCE, TODAY),
    ).rejects.toBe(sentinel)
    expect(h.calls.at(-1)?.target).toBe('calc_workout_kcal')
  })

  it('keeps the existing returned image event error semantics without a training write', async () => {
    const h = recordingClient({ kcal: 400, eventError: { message: 'returned event error' } })
    const result = await prepareWorkoutRegistration(
      { ...ARGS, estimated_kcal_from_image: 100 },
      context(h.client),
      REFERENCE,
      TODAY,
    )
    expect(result.finalKcal).toBe(100)
    expect(result.kcalSource).toBe('image')
    expect(h.calls.at(-1)?.target).toBe('product_events')
    expect(h.calls.some((call) => call.target === 'register_workout_atomic')).toBe(false)
  })

  it('preserves a rejected awaited image event by identity, before any training write', async () => {
    const sentinel = new Error('event promise rejection')
    const h = recordingClient({ kcal: 400, eventRejection: sentinel })
    await expect(
      prepareWorkoutRegistration(
        { ...ARGS, estimated_kcal_from_image: 100 },
        context(h.client),
        REFERENCE,
        TODAY,
      ),
    ).rejects.toBe(sentinel)
    expect(h.calls.at(-1)?.target).toBe('product_events')
    expect(h.calls.some((call) => call.target === 'register_workout_atomic')).toBe(false)
  })
})

describe('registraTreino — provider early return remains before shared preparation', () => {
  it('returns the exact provider-hit receipt after only the first owned type lookup', async () => {
    const calls: Recorded[] = []
    const steps: Step[] = []
    const builder = {
      select(columns: string) {
        steps.push(['select', columns])
        return builder
      },
      eq(column: string, value: unknown) {
        steps.push(['eq', column, value])
        return builder
      },
      limit(count: number) {
        steps.push(['limit', count])
        return Promise.resolve({
          data: [
            {
              id: 'already-owned',
              snapshot_id: 'original-snapshot',
              workout_type: RAW,
              estimated_kcal: 240,
            },
          ],
          error: null,
        })
      },
    }
    const from = vi.fn((table: string) => {
      if (table !== 'workout_logs' || calls.length !== 0) {
        throw new Error('provider hit must not reach another query or event')
      }
      calls.push({ kind: 'from', target: table, steps })
      return builder
    })
    const rpc = vi.fn(() => {
      throw new Error('provider hit must not calculate or write')
    })
    const client = { from, rpc } as unknown as ServiceClient
    const result = await registraTreino.execute(ARGS, context(client))
    expect(result).toEqual({
      success: true,
      deduped: true,
      message: 'Treino Natação 🏋️ e\u0301 já registrado (msg_id+tipo repetido). Não duplicou.',
    })
    expect(calls).toEqual([
      {
        kind: 'from',
        target: 'workout_logs',
        steps: [
          ['select', 'id, snapshot_id, workout_type, estimated_kcal'],
          ['eq', 'user_id', USER],
          ['eq', 'raw_provider_message_id', PROVIDER],
          ['eq', 'workout_type', RAW],
          ['limit', 2],
        ],
      },
    ])
    expect(from).toHaveBeenCalledTimes(1)
    expect(rpc).not.toHaveBeenCalled()
  })
})
