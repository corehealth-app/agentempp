/**
 * Physical QA A, 2026-10-01 13:59 BRT: after the 80 kg measurement at
 * 2026-10-01T16:15:33.319Z, "Resuma somente os registros de hoje, sem gerar planos."
 * returned 383 kcal / 42.2 g consumed, but targets 2980 kcal / 144 g and
 * remaining 2597 kcal / 101.8 g. Today and the existing daily snapshot still
 * held 3361 kcal / 186.1 g (2978 kcal / 143.88 g remaining).
 * C5 preserves intraday snapshots. This fixture tests the actual loadContext
 * path and projection; it does not run a model or change any formula.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import { loadContext } from '../pipeline.js'
import { consultaMetricas } from '../tools.js'

const now = new Date('2026-10-01T16:59:00.000Z')
const phrase = 'Resuma somente os registros de hoje, sem gerar planos.'
const profile = {
  sex: 'masculino',
  birth_date: '2000-01-01',
  height_cm: 185,
  weight_kg: 80,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'ganho_massa',
  goal_type: null,
  goal_value: null,
  deficit_level: null,
}
const snapshot = {
  calories_target: 3361,
  protein_target: '186.10',
  calories_consumed: 383,
  protein_g: '42.22',
  water_consumed_ml: 500,
  exercise_calories: 0,
  daily_balance: -2978,
  deficit_accumulated: 0,
  day_status: null,
}

function harness(day: Record<string, unknown> | null = snapshot) {
  const reads: Array<{ table: string; columns: string; filters: Record<string, unknown> }> = []
  const client = {
    from(table: string) {
      const read = { table, columns: '', filters: {} as Record<string, unknown> }
      reads.push(read)
      const result = () => {
        let data: unknown
        switch (table) {
          case 'users':
            data = { id: 'qa-a', timezone: 'America/Sao_Paulo', metadata: {} }
            break
          case 'user_profiles':
            data = profile
            break
          case 'user_coach_preferences':
            // This target fixture has no selected conversation style.
            data = null
            break
          case 'global_config':
            // Staging override observed on 2026-10-01, not the core default (1.5).
            data = [
              {
                key: 'calc.protein_factors',
                value: {
                  muita: 1.6,
                  pouca: 1.8,
                  moderada: 1.8,
                  training_low: 1.7,
                  optimal_mid_training: 1.9,
                  optimal_high_training: 2,
                },
              },
            ]
            break
          case 'product_events':
            data = []
            break
          case 'messages':
            data = [
              {
                direction: 'in',
                content: phrase,
                content_type: 'text',
                created_at: now.toISOString(),
                provider_message_id: 'flow-current',
              },
            ]
            break
          case 'user_progress':
            data = { xp_total: 0, level: 1, current_streak: 0 }
            break
          case 'daily_snapshots':
            data =
              read.filters.day_closed === true
                ? []
                : day &&
                  Object.fromEntries(
                    read.columns.split(',').map((key) => [key.trim(), day[key.trim()] ?? null]),
                  )
            break
          default:
            throw new Error(`Unexpected table ${table}`)
        }
        return { data, error: null }
      }
      const chain = Object.assign(Promise.resolve().then(result), {
        select(columns: string) {
          read.columns = columns
          return chain
        },
        eq(key: string, value: unknown) {
          read.filters[key] = value
          return chain
        },
        gte() {
          return chain
        },
        like() {
          return chain
        },
        order() {
          return chain
        },
        limit() {
          return chain
        },
        async single() {
          return result()
        },
        async maybeSingle() {
          return result()
        },
      })
      return chain
    },
  }
  return { client, reads }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(now)
  clearCalcConfigCache()
})
afterEach(() => {
  vi.useRealTimers()
  clearCalcConfigCache()
})

describe('audit 2026-10-01 — Flow and Today targets after physical 80 kg measurement', () => {
  it('uses the existing daily targets, without rewriting consumption or progress', async () => {
    const h = harness()
    const context = await loadContext(
      h.client as never,
      'qa-a',
      'flow-current',
      phrase,
      now,
      'mobile_flow',
    )
    expect(context.dailyTargets).toEqual({ calories_target: 3361, protein_target: 186.1 })
    expect(context.todaySnapshot).toMatchObject({ calories_consumed: 383, protein_g: 42.22 })
    expect(context.userProgress).toMatchObject({ xp_total: 0, level: 1, current_streak: 0 })
    expect(
      h.reads.find((r) => r.table === 'daily_snapshots' && r.filters.date === '2026-10-01'),
    ).toMatchObject({ filters: { user_id: 'qa-a', date: '2026-10-01' } })
    expect(snapshot.calories_target).toBe(3361)
    expect(snapshot.protein_target).toBe('186.10')
  })

  it('the allowed Flow metrics tool must agree with the intraday targets', async () => {
    const h = harness()
    const context = await loadContext(h.client as never, 'qa-a', null, phrase, now, 'mobile_flow')
    const output = await consultaMetricas.execute(
      {},
      {
        supabase: h.client as never,
        userId: 'qa-a',
        userWpp: 'qa-a',
        llm: {} as never,
        userTimezone: 'America/Sao_Paulo',
        referenceTimestamp: now,
        assistantIdentity: 'flow',
        flowDailyTargets: context.dailyTargets,
      },
    )
    expect(output).toMatchObject({ calories_target_today: 3361, protein_target_today_g: 186.1 })
  })

  it('the legacy metrics tool keeps live profile targets and makes no daily snapshot query', async () => {
    const h = harness()
    const output = await consultaMetricas.execute(
      {},
      {
        supabase: h.client as never,
        userId: 'qa-a',
        userWpp: 'qa-a',
        llm: {} as never,
        userTimezone: 'America/Sao_Paulo',
        referenceTimestamp: now,
        flowDailyTargets: { calories_target: 3361, protein_target: 186.1 },
      },
    )
    expect(output).toMatchObject({ calories_target_today: 2980, protein_target_today_g: 144 })
    expect(h.reads.some((read) => read.table === 'daily_snapshots')).toBe(false)
  })

  it.each([
    undefined,
    'whatsapp',
  ])('preserves the legacy channel %s targets and query projection', async (provider) => {
    const h = harness()
    const context = await loadContext(h.client as never, 'qa-a', null, phrase, now, provider)
    expect(context.dailyTargets).toEqual({ calories_target: 2980, protein_target: 144 })
    const dailyRead = h.reads.find((r) => r.table === 'daily_snapshots' && r.filters.date)
    expect(dailyRead?.columns).not.toContain('calories_target')
    expect(dailyRead?.columns).not.toContain('protein_target')
  })

  it.each([
    null,
    { ...snapshot, calories_target: null, protein_target: null },
    { ...snapshot, calories_target: 0, protein_target: 'invalid' },
  ])('falls back to the existing profile calculation when no valid day target exists', async (day) => {
    const h = harness(day)
    const context = await loadContext(h.client as never, 'qa-a', null, phrase, now, 'mobile_flow')
    expect(context.dailyTargets).toEqual({ calories_target: 2980, protein_target: 144 })
  })
})
