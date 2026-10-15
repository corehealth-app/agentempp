/**
 * `ToolContext.workoutKcalLookupSlug` — the WhatsApp side (review of
 * 2026-10-05).
 *
 * The mobile API resolves a workout type typed in the app to a catalogue slug
 * for the kcal lookup ("Natação" → `natacao`, docs/CALCULO-MPP.md §2d). Its
 * confirmation used to hand `registra_treino` a Proxy of the database client
 * that rewrote one RPC argument. That is replaced by an OPTIONAL typed field
 * of the tool context, read by ONE expression of the tool.
 *
 * What is locked here:
 *  - with the field ABSENT (the WhatsApp pipeline and its button tap never
 *    set it) the tool sends the database exactly what it sent before the
 *    field existed: every read, every RPC and every argument, written out
 *    below from the code of the commit before this change (3a625d2,
 *    tools.ts: `p_slug: args.workout_type`);
 *  - with the field PRESENT the only difference is `p_slug` of
 *    `calc_workout_kcal`: the stored type, the idempotency read, the 6 h
 *    dedup read and every other argument keep the type as given;
 *  - nothing but the mobile confirmation mentions the field.
 *
 * The database is a recording fake (no network): it answers the two RPCs
 * with a rate per slug (natacao 10, anything else 6 kcal/min, as the 'outro'
 * fallback of `calc_workout_kcal`) and records what it was asked.
 */
import { readdirSync, readFileSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from './calc-config-loader.js'
import type { ToolContext } from './tools.js'
import { registraTreino } from './tools.js'

const USER = '0b9f6f0e-0000-4000-8000-0000000000e4'
/** 12:00 of 2026-10-04 in America/Sao_Paulo. */
const NOW = new Date('2026-10-04T15:00:00.000Z')
const PROVIDER_MESSAGE_ID = 'wamid.HBgNNTUxMTkwMDAwMDAwMA'

type Step = [method: string, ...args: unknown[]]
interface Recorded {
  kind: 'from' | 'rpc'
  target: string
  steps?: Step[]
  params?: Record<string, unknown>
}

/** Only the weight is set: the day has no calorie target (targets null). */
const PROFILE = { weight_kg: 70 }

function recordingClient() {
  const calls: Recorded[] = []
  const query = (table: string, steps: Step[]) => {
    const builder: Record<string, unknown> = {}
    for (const method of ['select', 'eq', 'gte', 'lte', 'lt', 'gt', 'like', 'limit', 'order']) {
      builder[method] = (...args: unknown[]) => {
        steps.push([method, ...args])
        return builder
      }
    }
    builder.maybeSingle = () => {
      steps.push(['maybeSingle'])
      return Promise.resolve({ data: table === 'user_profiles' ? PROFILE : null, error: null })
    }
    builder.insert = (row: unknown) => {
      steps.push(['insert', row])
      return Promise.resolve({ data: null, error: null })
    }
    // biome-ignore lint/suspicious/noThenProperty: mirrors the awaitable PostgREST builder
    builder.then = (
      onFulfilled: (value: { data: unknown[]; error: null }) => unknown,
      onRejected?: (reason: unknown) => unknown,
    ) => Promise.resolve({ data: [], error: null }).then(onFulfilled, onRejected)
    return builder
  }
  const client = {
    from(table: string) {
      const steps: Step[] = []
      calls.push({ kind: 'from', target: table, steps })
      return query(table, steps)
    },
    rpc(name: string, params: Record<string, unknown>) {
      calls.push({ kind: 'rpc', target: name, params: { ...params } })
      if (name === 'calc_workout_kcal') {
        const rate = String(params.p_slug).toLowerCase() === 'natacao' ? 10 : 6
        return Promise.resolve({ data: rate * Number(params.p_duration_min), error: null })
      }
      if (name === 'register_workout_atomic') {
        return Promise.resolve({
          data: {
            snapshot_id: 'snapshot-1',
            inserted: true,
            replaced_count: 0,
            exercise_calories: params.p_estimated_kcal,
            training_done: true,
          },
          error: null,
        })
      }
      throw new Error(`recording client: unexpected rpc ${name}`)
    },
  }
  return { calls, client: client as unknown as ServiceClient }
}

/** The context the WhatsApp pipeline builds for a tool call (the fields this tool reads). */
function whatsappContext(supabase: ServiceClient): ToolContext {
  return {
    supabase,
    userId: USER,
    userWpp: '5511900000000',
    userCountry: 'BR',
    userTimezone: 'America/Sao_Paulo',
    providerMessageId: PROVIDER_MESSAGE_ID,
    referenceTimestamp: NOW,
    recentUserMessages: ['nadei 40 minutos hoje'],
  }
}

const ARGS = { workout_type: 'Natação', duration_min: 40, intensity: 'moderada' as const }

/**
 * What the tool of the commit before this change sent for ARGS, in order.
 * `Natação` is not a slug, so the function answers the generic 6 × 40 = 240.
 */
function expectedAtHead(sixHoursAgo: string): Recorded[] {
  return [
    {
      kind: 'from',
      target: 'workout_logs',
      steps: [
        ['select', 'id, snapshot_id, workout_type, estimated_kcal'],
        ['eq', 'user_id', USER],
        ['eq', 'raw_provider_message_id', PROVIDER_MESSAGE_ID],
        ['eq', 'workout_type', 'Natação'],
        ['limit', 2],
      ],
    },
    {
      kind: 'from',
      target: 'workout_logs',
      steps: [
        ['select', 'id'],
        ['eq', 'user_id', USER],
        ['eq', 'workout_type', 'Natação'],
        ['eq', 'duration_min', 40],
        ['gte', 'created_at', sixHoursAgo],
        ['limit', 1],
      ],
    },
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
        p_slug: 'Natação',
        p_duration_min: 40,
        p_intensity: 'moderada',
        p_weight_kg: 70,
      },
    },
    {
      kind: 'rpc',
      target: 'register_workout_atomic',
      params: {
        p_user_id: USER,
        p_date: '2026-10-04',
        p_workout_type: 'Natação',
        p_duration_min: 40,
        p_estimated_kcal: 240,
        p_intensity: 'moderada',
        p_notes: '[kcal_source=formula, formula=240, image=n/a]',
        p_performed_at: NOW.toISOString(),
        p_provider_message_id: PROVIDER_MESSAGE_ID,
        p_calories_target: null,
        p_protein_target: null,
        p_replace_recent: false,
        p_replace_since: null,
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
  vi.useRealTimers()
})

describe('registra_treino — the field absent (WhatsApp): exactly what the tool sent before the field existed', () => {
  const sixHoursAgo = new Date(NOW.getTime() - 6 * 3600 * 1000).toISOString()

  it('a context without the field: every read, both RPCs and every argument', async () => {
    const { calls, client } = recordingClient()
    const context = whatsappContext(client)
    expect(context).not.toHaveProperty('workoutKcalLookupSlug')

    const result = await registraTreino.execute(ARGS, context)

    expect(calls).toEqual(expectedAtHead(sixHoursAgo))
    expect(result).toEqual({
      success: true,
      deduped: false,
      kcal_burned: 240,
      kcal_source: 'formula',
      formula_kcal: 240,
      image_kcal: null,
      image_discarded: false,
      total_exercise_kcal_today: 240,
    })
  })

  it('the field present but undefined is the field absent', async () => {
    const { calls, client } = recordingClient()
    await registraTreino.execute(ARGS, {
      ...whatsappContext(client),
      workoutKcalLookupSlug: undefined,
    })
    expect(calls).toEqual(expectedAtHead(sixHoursAgo))
  })

  it('an exact slug, as the model sends on WhatsApp: the lookup receives the argument itself', async () => {
    const { calls, client } = recordingClient()
    await registraTreino.execute({ ...ARGS, workout_type: 'natacao' }, whatsappContext(client))
    const lookups = calls.filter((call) => call.target === 'calc_workout_kcal')
    expect(lookups.map((call) => call.params)).toEqual([
      { p_slug: 'natacao', p_duration_min: 40, p_intensity: 'moderada', p_weight_kg: 70 },
    ])
  })
})

describe('registra_treino — the field present (app confirmation): only the kcal lookup changes', () => {
  it('the lookup receives the slug; the stored type, the idempotency and the dedup keep the typed text', async () => {
    const without = recordingClient()
    await registraTreino.execute(ARGS, whatsappContext(without.client))
    clearCalcConfigCache()
    const withField = recordingClient()
    const result = await registraTreino.execute(ARGS, {
      ...whatsappContext(withField.client),
      workoutKcalLookupSlug: 'natacao',
    })

    // natacao 10 × 40 = 400.
    expect(result).toMatchObject({ success: true, kcal_burned: 400, formula_kcal: 400 })
    const differing = withField.calls
      .map((call, index) => ({ call, before: without.calls[index] }))
      .filter(({ call, before }) => JSON.stringify(call) !== JSON.stringify(before))
    expect(withField.calls).toHaveLength(without.calls.length)
    // Two calls differ: the lookup (the slug) and the write (the kcal it
    // returned). Every read is identical.
    expect(differing.map(({ call }) => call.target)).toEqual([
      'calc_workout_kcal',
      'register_workout_atomic',
    ])
    expect(differing[0]?.call.params).toEqual({
      ...differing[0]?.before?.params,
      p_slug: 'natacao',
    })
    expect(differing[1]?.call.params).toEqual({
      ...differing[1]?.before?.params,
      p_estimated_kcal: 400,
      p_notes: '[kcal_source=formula, formula=400, image=n/a]',
    })
    expect(differing[1]?.call.params).toMatchObject({ p_workout_type: 'Natação' })
  })
})

describe('who sets the field', () => {
  it('only the mobile confirmation, the tool and the declaration mention it', () => {
    const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))
    const sources = (directory: string): string[] =>
      readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const path = join(directory, entry.name)
        if (entry.isDirectory()) return entry.name === 'node_modules' ? [] : sources(path)
        return entry.name.endsWith('.ts') && !entry.name.endsWith('.test.ts') ? [path] : []
      })
    const mentioning = [
      'packages/agent/src',
      'packages/core/src',
      'packages/inngest-functions/src',
      'apps/admin/src',
      'apps/mobile-bff/src',
      'apps/cli/src',
    ]
      .flatMap((directory) => sources(join(repoRoot, directory)))
      .filter((path) => readFileSync(path, 'utf8').includes('workoutKcalLookupSlug'))
      .map((path) => relative(repoRoot, path).split(sep).join('/'))
      .sort()

    // The WhatsApp pipeline (pipeline.ts) and its button tap
    // (interactive-handler.ts) are not in the list: they never set it.
    expect(mentioning).toEqual([
      'apps/admin/src/lib/mobile-api/registration-service.ts',
      'packages/agent/src/tools/types.ts',
      'packages/agent/src/workout-registration-preparation.ts',
    ])
  })

  it('the tool reads it in one place: the argument of the kcal lookup', () => {
    const tool = readFileSync(
      fileURLToPath(new URL('./workout-registration-preparation.ts', import.meta.url)),
      'utf8',
    )
    expect(tool.match(/workoutKcalLookupSlug/g)).toHaveLength(2)
    expect(tool).toContain('p_slug: ctx.workoutKcalLookupSlug ?? args.workout_type,')
  })
})
