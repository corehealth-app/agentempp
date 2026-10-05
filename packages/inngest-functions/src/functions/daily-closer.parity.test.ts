/**
 * Parity between the production closer (`dailyCloserFn`, this package) and the
 * shared close function of `@mpp/agent` (`closeLocalDay`), which the mobile
 * API and the operator script use on the test environment.
 *
 * WHY. The mobile API may not import this package, so the closer's script of
 * reads and writes exists twice. The RULES do not (both call `calcDailyXP`,
 * `creditDayToBloco`, `computeProgress`, `resolveClosedDayStatus`,
 * `getGapForDate`, `loadDailyTargets` and the same RPC), but the twelve
 * parameters handed to `finalize_daily_close_atomic` and the fields written
 * on the day row are mapped in two places. This file fails when the two
 * mappings disagree.
 *
 * HOW. For each fixture day two identical in-memory databases are built. The
 * production handler runs against one, exactly as registered (its real
 * handler, with only the dependency factory of `lib/env` replaced so it
 * receives the in-memory client); `closeLocalDay` runs against the other for
 * the same local date, at the same frozen instant: 00:30 in America/Sao_Paulo,
 * production's first tick of the night, which is also the first instant the
 * shared function accepts yesterday. Then, LITERALLY equal:
 *  - the parameters of the `finalize_daily_close_atomic` call;
 *  - the fields written on the day row, and the row as it ends;
 *  - `user_progress` as it ends;
 *  - the telemetry events (compared as a set: the shared function writes them
 *    after the finalization, the closer partly before).
 *
 * Only "yesterday" INSIDE THE PRODUCTION WINDOW is compared: production
 * closes no other date, and closes yesterday only while the local hour is 0
 * to 4. The shared function treats a close of yesterday at local hour 5 or
 * later as a LATE close (it keeps the target stored on the day row,
 * docs/CALCULO-MPP.md §3a rule 4), so a comparison made at 08:00 would
 * compare it with a closer that does not run. Every comparison below is
 * therefore made at 00:30 or at 04:59 local, the two ends of the window, and
 * the last block locks the boundary: at 05:00 the production closer skips the
 * account and the shared function closes late. The late close, the sweep, the
 * frontier and the conditional writes have no production counterpart; they
 * are locked in packages/agent (day-close.test.ts and
 * __golden__/audit-10-04-app-day-close.test.ts).
 *
 * ONE DECLARED DIVERGENCE INSIDE THE WINDOW (last block; RC F in
 * docs/CALCULO-MPP.md §3a, "mais de 50 mensagens"): the production closer
 * reads up to 50 messages of the day with no direction filter and no
 * ordering and looks for an inbound one among them; the shared function asks
 * for one inbound message. They disagree on a day with no meal and no
 * workout whose 50 returned messages are all outbound. Locked as it is, not
 * fixed: the production read is not copied.
 *
 * Fixture person (synthetic): homem, 80 kg, 180 cm, born 1986-01-01,
 * atividade leve → BMR 1730. Targets: recomposição 1576, ganho de massa 2498,
 * manutenção 2379.
 */
import {
  clearCalcConfigCache,
  closeLocalDay,
  closePastOpenDays,
  getLocalHour,
  PRODUCTION_CLOSE_LAST_LOCAL_HOUR,
} from '@mpp/agent'
import { DayCloseMemoryDb, type MemoryRow } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const holder = vi.hoisted(() => ({ client: null as unknown }))

vi.mock('../lib/env.js', () => ({
  // The closer destructures `llm` and never uses it.
  createWorkerDeps: () => ({ supabase: holder.client, llm: {}, embeddings: {} }),
}))

const { dailyCloserFn } = await import('./daily-closer.js')

const USER = '0b9f6f0e-0000-4000-8000-00000000c105'
const TIMEZONE = 'America/Sao_Paulo'
const YESTERDAY = '2026-10-04'
/** 00:30 of 2026-10-05 in America/Sao_Paulo (UTC−3). */
const CLOSING_INSTANT = new Date('2026-10-05T03:30:00.000Z')
/** 04:59 of 2026-10-05: the last minute in which the production closer runs. */
const LAST_MINUTE_OF_THE_WINDOW = new Date('2026-10-05T07:59:00.000Z')
/** 05:00 of 2026-10-05: the production closer skips the account from here on. */
const FIRST_MINUTE_AFTER_THE_WINDOW = new Date('2026-10-05T08:00:00.000Z')

type Protocol = 'recomposicao' | 'ganho_massa' | 'manutencao'

const TARGETS: Record<Protocol, number> = {
  recomposicao: 1576,
  ganho_massa: 2498,
  manutencao: 2379,
}

function profile(protocol: Protocol): MemoryRow {
  return {
    sex: 'masculino',
    birth_date: '1986-01-01',
    height_cm: 180,
    weight_kg: 80,
    body_fat_percent: null,
    activity_level: 'leve',
    training_frequency: 3,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    goal_type: null,
    goal_value: null,
    current_protocol: protocol,
    deficit_level: protocol === 'recomposicao' ? 500 : null,
  }
}

function local(date: string, time: string): string {
  return new Date(`${date}T${time}:00-03:00`).toISOString()
}

interface Fixture {
  protocol: Protocol
  progress?: MemoryRow
  seed: (db: DayCloseMemoryDb) => void
}

function build(fixture: Fixture): DayCloseMemoryDb {
  const db = new DayCloseMemoryDb()
  db.addAccount({ userId: USER, profile: profile(fixture.protocol), progress: fixture.progress })
  fixture.seed(db)
  return db
}

function meal(
  db: DayCloseMemoryDb,
  protocol: Protocol,
  input: { kcal: number; protein: number; time?: string; mealType?: string; storedTarget?: number },
) {
  db.registerMeal({
    userId: USER,
    date: YESTERDAY,
    consumedAt: local(YESTERDAY, input.time ?? '12:00'),
    kcal: input.kcal,
    proteinG: input.protein,
    carbsG: 180.4,
    fatG: 55.7,
    mealType: input.mealType ?? 'almoco',
    caloriesTarget: input.storedTarget ?? TARGETS[protocol],
    proteinTarget: 120,
  })
}

function workout(db: DayCloseMemoryDb, protocol: Protocol, kcal: number) {
  db.registerWorkout({
    userId: USER,
    date: YESTERDAY,
    performedAt: local(YESTERDAY, '18:00'),
    kcal,
    caloriesTarget: TARGETS[protocol],
    proteinTarget: 120,
  })
}

async function runProductionCloser(db: DayCloseMemoryDb, firedAt: Date = CLOSING_INSTANT) {
  holder.client = db.client
  const errors: unknown[] = []
  const handler = (
    dailyCloserFn as unknown as { fn: (context: unknown) => Promise<Record<string, number>> }
  ).fn
  const summary = await handler({
    event: { data: { hour: firedAt.getUTCHours(), fired_at: firedAt.toISOString() } },
    step: { run: (_id: string, run: () => unknown) => run() },
    logger: { info: () => undefined, error: (...args: unknown[]) => errors.push(args) },
  })
  expect(errors).toEqual([])
  return summary
}

function finalizeCalls(db: DayCloseMemoryDb) {
  return db.operations
    .filter((op) => op.kind === 'rpc' && op.target === 'finalize_daily_close_atomic')
    .map((op) => op.params)
}

/** The fields each path wrote on the day row, with the keys the closer's upsert carries. */
function dayRowWrite(db: DayCloseMemoryDb) {
  const writes = db.operations.filter(
    (op) => op.target === 'daily_snapshots' && (op.kind === 'upsert' || op.kind === 'update'),
  )
  expect(writes).toHaveLength(1)
  return { user_id: USER, date: YESTERDAY, ...(writes[0]?.values as MemoryRow) }
}

function withoutClock(row: MemoryRow | null) {
  if (!row) return row
  // `created_at` / `updated_at` carry the in-memory database's own counter.
  const { created_at: _created, updated_at: _updated, ...rest } = row
  return rest
}

function eventSet(db: DayCloseMemoryDb) {
  return db
    .events(USER)
    .map((event) => JSON.stringify({ event: event.event, properties: event.properties }))
    .sort()
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(CLOSING_INSTANT)
  clearCalcConfigCache()
})

afterEach(() => {
  vi.useRealTimers()
  holder.client = null
})

const SCENARIOS: Array<{ name: string; fixture: Fixture; credit: number; xp: number }> = [
  {
    // balance = 1809 − 1576 − 0 = +233; credit = 500 − 233 = 267
    name: 'recomposição, no workout (233 kcal over the target)',
    fixture: {
      protocol: 'recomposicao',
      seed: (db) => meal(db, 'recomposicao', { kcal: 1809, protein: 110 }),
    },
    credit: 267,
    xp: 15,
  },
  {
    // The client's own example (docs §2b): 500 − 233 + 565 = 832
    name: 'recomposição, with a workout (500 − 233 + 565 = 832)',
    fixture: {
      protocol: 'recomposicao',
      seed: (db) => {
        meal(db, 'recomposicao', { kcal: 1809, protein: 110 })
        workout(db, 'recomposicao', 565)
      },
    },
    credit: 832,
    xp: 20,
  },
  {
    // credit = meta + exercício − consumido = 2498 + 0 − 2400 = 98
    name: 'ganho de massa, no workout',
    fixture: {
      protocol: 'ganho_massa',
      seed: (db) => meal(db, 'ganho_massa', { kcal: 2400, protein: 95.5 }),
    },
    credit: 98,
    xp: 10,
  },
  {
    // 2498 + 300 − 2600 = 198
    name: 'ganho de massa, with a workout',
    fixture: {
      protocol: 'ganho_massa',
      seed: (db) => {
        meal(db, 'ganho_massa', { kcal: 2600, protein: 130 })
        workout(db, 'ganho_massa', 300)
      },
    },
    credit: 198,
    xp: 20,
  },
  {
    // 2379 + 0 − 2500 = −121 (a surplus day takes from the block; floor at 0)
    name: 'manutenção, no workout (surplus)',
    fixture: {
      protocol: 'manutencao',
      // A longest streak above the current one, so the two are told apart.
      progress: {
        deficit_block: 400,
        xp_total: 90,
        current_streak: 2,
        longest_streak: 12,
        last_active_date: '2026-10-03',
      },
      seed: (db) => meal(db, 'manutencao', { kcal: 2500, protein: 101 }),
    },
    credit: -121,
    xp: 15,
  },
  {
    // 2379 + 420 − 2379 = 420
    name: 'manutenção, with a workout',
    fixture: {
      protocol: 'manutencao',
      seed: (db) => {
        meal(db, 'manutencao', { kcal: 2379, protein: 99.9 })
        workout(db, 'manutencao', 420)
      },
    },
    credit: 420,
    xp: 15,
  },
  {
    // The day row was created with 3355; the profile gives 2498 at closing
    // time. For YESTERDAY both paths write the profile's target.
    name: 'ganho de massa, target stored during the day differs from the profile at closing time',
    fixture: {
      protocol: 'ganho_massa',
      seed: (db) => meal(db, 'ganho_massa', { kcal: 2683, protein: 202.5, storedTarget: 3355 }),
    },
    credit: -185,
    xp: 15,
  },
  {
    // 700 < 0,5 × 1576: only the programmed deficit is credited
    name: 'recomposição, under-registration (< 50% of the target)',
    fixture: {
      protocol: 'recomposicao',
      seed: (db) => meal(db, 'recomposicao', { kcal: 700, protein: 40 }),
    },
    credit: 500,
    xp: 10,
  },
  {
    // credit = 500 − (700 − 1576) = 1376
    name: 'recomposição, a meal confirmed as skipped',
    fixture: {
      protocol: 'recomposicao',
      seed: (db) => {
        meal(db, 'recomposicao', { kcal: 700, protein: 40 })
        db.tables.product_events.push(
          db.withDefaults('product_events', {
            user_id: USER,
            event: 'meal.user_skipped',
            properties: { local_date: YESTERDAY, meal_type: 'jantar' },
          }),
        )
      },
    },
    credit: 1376,
    xp: 10,
  },
  {
    // No meal and no workout: row created, base XP, no credit
    name: 'a day with only an inbound message',
    fixture: {
      protocol: 'recomposicao',
      seed: (db) => db.addInboundMessage(USER, local(YESTERDAY, '10:00')),
    },
    credit: 0,
    xp: 10,
  },
  {
    // 7600 + 576 = 8176 → one block (7700) + 476; streak 6 → 7 earns the medal
    name: 'a day that completes a block and a 7-day streak',
    fixture: {
      protocol: 'recomposicao',
      progress: {
        deficit_block: 7600,
        xp_total: 90,
        current_streak: 6,
        longest_streak: 6,
        last_active_date: '2026-10-03',
      },
      seed: (db) => meal(db, 'recomposicao', { kcal: 1500, protein: 110 }),
    },
    credit: 576,
    xp: 15,
  },
]

describe.each([
  ['00:30 local, the first tick of the night', CLOSING_INSTANT],
  ['04:59 local, the last minute of the window', LAST_MINUTE_OF_THE_WINDOW],
])('yesterday at %s: the production closer and closeLocalDay write the same', (_label, instant) => {
  beforeEach(() => {
    vi.setSystemTime(instant)
  })

  it('the instant is inside the window in which the production closer runs', () => {
    expect(getLocalHour(TIMEZONE, instant)).toBeLessThanOrEqual(PRODUCTION_CLOSE_LAST_LOCAL_HOUR)
  })

  it.each(SCENARIOS)('$name', async ({ fixture, credit, xp }) => {
    const production = build(fixture)
    const shared = build(fixture)

    const summary = await runProductionCloser(production, instant)
    expect(summary).toMatchObject({ processed: 1, skipped: 0, failed: 0 })

    const result = await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
      // The production closer always advances the reassessment schedule.
      advanceReevaluation: true,
    })
    expect(result).toMatchObject({ closed: true, late: false })
    // The number is the hand calculation in the scenario's comment.
    expect(result.detail).toMatchObject({ blockCredit: credit, xpEarned: xp })

    const productionCalls = finalizeCalls(production)
    expect(productionCalls).toHaveLength(1)
    expect(finalizeCalls(shared)).toEqual(productionCalls)
    expect(Object.keys(productionCalls[0] ?? {}).sort()).toEqual([
      'p_badges_earned',
      'p_blocks_completed',
      'p_closed_at',
      'p_current_streak',
      'p_day_status',
      'p_deficit_block',
      'p_last_active_date',
      'p_level',
      'p_longest_streak',
      'p_snapshot_id',
      'p_user_id',
      'p_xp_total',
    ])

    expect(dayRowWrite(shared)).toEqual(dayRowWrite(production))
    expect(withoutClock(shared.snapshot(USER, YESTERDAY))).toEqual(
      withoutClock(production.snapshot(USER, YESTERDAY)),
    )
    expect(withoutClock(shared.progress(USER))).toEqual(withoutClock(production.progress(USER)))
    expect(eventSet(shared)).toEqual(eventSet(production))
  })
})

describe('yesterday at 00:30 local: the values, the day status and the reassessment schedule', () => {
  it('the block-and-streak day: the values both paths handed to the finalization', async () => {
    const fixture = SCENARIOS.at(-1)?.fixture
    if (!fixture) throw new Error('scenario missing')
    const production = build(fixture)
    await runProductionCloser(production)
    expect(finalizeCalls(production)[0]).toMatchObject({
      p_user_id: USER,
      p_day_status: 'complete',
      p_xp_total: 105,
      p_level: 2,
      p_current_streak: 7,
      p_longest_streak: 7,
      p_blocks_completed: 1,
      p_deficit_block: 476,
      p_badges_earned: ['Primeira Semana', 'Primeiro Bloco'],
      p_last_active_date: YESTERDAY,
      p_closed_at: CLOSING_INSTANT.toISOString(),
    })
    expect(eventSet(production).map((entry) => JSON.parse(entry).event)).toEqual([
      'badge.earned',
      'bloco7700.block_completed',
      'daily_closer.completed',
    ])
  })

  it('incomplete_no_response (reminder recorded, expected meal missing): same status, same zero credit', async () => {
    const fixture: Fixture = {
      protocol: 'recomposicao',
      seed: (db) => {
        // Six earlier days with café, almoço and jantar establish the pattern.
        for (const date of [
          '2026-09-28',
          '2026-09-29',
          '2026-09-30',
          '2026-10-01',
          '2026-10-02',
          '2026-10-03',
        ]) {
          for (const [mealType, time] of [
            ['cafe', '08:00'],
            ['almoco', '12:00'],
            ['jantar', '20:00'],
          ] as const) {
            db.registerMeal({
              userId: USER,
              date,
              consumedAt: local(date, time),
              kcal: 500,
              mealType,
              caloriesTarget: 1576,
              proteinTarget: 120,
            })
          }
        }
        meal(db, 'recomposicao', { kcal: 600, protein: 30, time: '08:00', mealType: 'cafe' })
        meal(db, 'recomposicao', { kcal: 600, protein: 30, time: '12:00', mealType: 'almoco' })
        const row = db.tables.daily_snapshots.find((candidate) => candidate.date === YESTERDAY)
        if (!row) throw new Error('fixture row missing')
        row.gap_reminder_sent_at = local(YESTERDAY, '21:30')
      },
    }
    const production = build(fixture)
    const shared = build(fixture)
    await runProductionCloser(production)
    const result = await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
      advanceReevaluation: true,
    })

    expect(result.detail).toMatchObject({ dayStatus: 'incomplete_no_response', blockCredit: 0 })
    expect(finalizeCalls(shared)).toEqual(finalizeCalls(production))
    expect(finalizeCalls(production)[0]).toMatchObject({ p_day_status: 'incomplete_no_response' })
    expect(withoutClock(shared.snapshot(USER, YESTERDAY))).toEqual(
      withoutClock(production.snapshot(USER, YESTERDAY)),
    )
    expect(eventSet(shared)).toEqual(eventSet(production))
  })

  it('without advanceReevaluation (the default of the on-demand path) the ONLY difference is the reassessment schedule', async () => {
    const fixture = SCENARIOS[1]?.fixture
    if (!fixture) throw new Error('scenario missing')
    const production = build(fixture)
    const shared = build(fixture)
    await runProductionCloser(production)
    await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
    })

    expect(finalizeCalls(shared)).toEqual(finalizeCalls(production))
    expect(dayRowWrite(shared)).toEqual(dayRowWrite(production))
    // first day row 2026-10-04 + 14
    expect(production.progress(USER)).toMatchObject({ next_reevaluation: '2026-10-18' })
    expect(shared.progress(USER)).toMatchObject({ next_reevaluation: null })
    expect({ ...withoutClock(shared.progress(USER)), next_reevaluation: '2026-10-18' }).toEqual(
      withoutClock(production.progress(USER)),
    )
    expect(shared.operations.some((op) => op.target === 'advance_reevaluation_schedule')).toBe(
      false,
    )
  })
})

describe('the end of the window: 05:00 local', () => {
  // The day row was created with 3355; the profile gives 2498 at closing time.
  const fixture: Fixture = {
    protocol: 'ganho_massa',
    seed: (db) => meal(db, 'ganho_massa', { kcal: 2683, protein: 202.5, storedTarget: 3355 }),
  }

  it('at 04:59 both write the profile target (2498, credit −185)', async () => {
    vi.setSystemTime(LAST_MINUTE_OF_THE_WINDOW)
    const production = build(fixture)
    const shared = build(fixture)
    await runProductionCloser(production, LAST_MINUTE_OF_THE_WINDOW)
    const result = await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
      advanceReevaluation: true,
    })

    // 2498 + 0 − 2683 = −185
    expect(result).toMatchObject({
      late: false,
      detail: { caloriesTarget: 2498, blockCredit: -185 },
    })
    expect(production.snapshot(USER, YESTERDAY)).toMatchObject({
      day_closed: true,
      calories_target: 2498,
    })
    expect(withoutClock(shared.snapshot(USER, YESTERDAY))).toEqual(
      withoutClock(production.snapshot(USER, YESTERDAY)),
    )
  })

  it('at 05:00 the production closer skips the account; closeLocalDay closes LATE and keeps the stored target (3355, credit 672)', async () => {
    vi.setSystemTime(FIRST_MINUTE_AFTER_THE_WINDOW)
    const production = build(fixture)
    const shared = build(fixture)

    const summary = await runProductionCloser(production, FIRST_MINUTE_AFTER_THE_WINDOW)
    expect(summary).toMatchObject({ processed: 0, skipped: 1, failed: 0 })
    expect(production.writes).toEqual([])
    expect(production.snapshot(USER, YESTERDAY)).toMatchObject({
      day_closed: false,
      calories_target: 3355,
    })

    const result = await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
    })
    // 3355 + 0 − 2683 = 672
    expect(result).toMatchObject({
      closed: true,
      late: true,
      detail: { storedCaloriesTarget: 3355, caloriesTarget: 3355, blockCredit: 672 },
    })
    expect(shared.snapshot(USER, YESTERDAY)).toMatchObject({
      day_closed: true,
      calories_target: 3355,
    })
  })
})

describe('a day with no record', () => {
  it('neither path finalizes or creates a day row; only the production closer writes its "skipped" event', async () => {
    const fixture: Fixture = { protocol: 'recomposicao', seed: () => undefined }
    const production = build(fixture)
    const shared = build(fixture)

    const summary = await runProductionCloser(production)
    expect(summary).toMatchObject({ processed: 0, skipped: 1, failed: 0 })
    const result = await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
    })

    expect(result).toMatchObject({ closed: false, reason: 'inactive' })
    expect(finalizeCalls(production)).toEqual([])
    expect(finalizeCalls(shared)).toEqual([])
    expect(production.snapshot(USER, YESTERDAY)).toBeNull()
    expect(shared.snapshot(USER, YESTERDAY)).toBeNull()
    expect(withoutClock(shared.progress(USER))).toEqual(withoutClock(production.progress(USER)))
    // Declared difference: production writes this on every tick of the night
    // for every inactive account; the on-demand path never does.
    expect(production.events(USER).map((event) => event.event)).toEqual(['daily_closer.skipped'])
    expect(shared.writes).toEqual([])
  })

  it('second inactive day in a row: the sweep zeroes the streak to the same value, with the same event', async () => {
    const fixture: Fixture = {
      protocol: 'recomposicao',
      progress: {
        current_streak: 5,
        longest_streak: 5,
        xp_total: 75,
        last_active_date: '2026-10-02',
      },
      seed: () => undefined,
    }
    const production = build(fixture)
    const shared = build(fixture)

    await runProductionCloser(production)
    const sweep = await closePastOpenDays(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      now: new Date(),
      from: '2026-09-01',
    })

    expect(sweep.streakReset).toMatchObject({ applied: true, previousStreak: 5, gapDays: 2 })
    expect(production.progress(USER)).toMatchObject({ current_streak: 0, longest_streak: 5 })
    expect(withoutClock(shared.progress(USER))).toEqual(withoutClock(production.progress(USER)))
    const reset = (db: DayCloseMemoryDb) => db.events(USER, 'streak.reset_inactive')[0]?.properties
    expect(reset(shared)).toEqual(reset(production))
    expect(reset(production)).toEqual({
      previous_streak: 5,
      last_active_date: '2026-10-02',
      gap_days: 2,
      yesterday: YESTERDAY,
    })
  })

  it('first inactive day: both tolerate it and leave the streak', async () => {
    const fixture: Fixture = {
      protocol: 'recomposicao',
      progress: { current_streak: 5, longest_streak: 5, last_active_date: '2026-10-03' },
      seed: () => undefined,
    }
    const production = build(fixture)
    const shared = build(fixture)
    await runProductionCloser(production)
    await closePastOpenDays(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      now: new Date(),
      from: '2026-09-01',
    })
    expect(production.progress(USER)).toMatchObject({ current_streak: 5 })
    expect(shared.progress(USER)).toMatchObject({ current_streak: 5 })
    expect(shared.writes).toEqual([])
  })
})

describe('declared divergence inside the window (RC F): a message-only day with more than 50 messages', () => {
  // Review of 2026-10-05 (LOW), the reviewer's exact case: 04/10 with 50
  // outbound messages followed by 3 inbound ones, no meal and no workout,
  // closed at 00:30 of 05/10 in America/Sao_Paulo. The in-memory database
  // returns rows in insertion order, so the 50 the production closer reads are
  // the 50 outbound ones (Postgres promises no order for that read).
  function messages(db: DayCloseMemoryDb, outboundFirst: number, inboundAfter: number) {
    for (let index = 0; index < outboundFirst + inboundAfter; index++) {
      const createdAt = `${YESTERDAY}T15:${String(index).padStart(2, '0')}:00.000Z`
      db.addInboundMessage(USER, createdAt)
      if (index < outboundFirst) (db.tables.messages[index] as MemoryRow).direction = 'out'
    }
  }

  it('50 outbound then 3 inbound: production sees an inactive day and writes only "skipped"; the shared function closes it', async () => {
    const fixture: Fixture = { protocol: 'recomposicao', seed: (db) => messages(db, 50, 3) }
    const production = build(fixture)
    const shared = build(fixture)

    const summary = await runProductionCloser(production)
    const result = await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
    })

    // Production: inactive. Nothing but its "skipped" event.
    expect(summary).toMatchObject({ processed: 0, skipped: 1, failed: 0 })
    expect(finalizeCalls(production)).toEqual([])
    expect(production.snapshot(USER, YESTERDAY)).toBeNull()
    expect(production.progress(USER)).toMatchObject({
      xp_total: 0,
      current_streak: 0,
      last_active_date: null,
    })
    expect(production.events(USER).map((event) => event.event)).toEqual(['daily_closer.skipped'])

    // The shared function: a message-only day, inside the window (not late).
    expect(result).toMatchObject({
      closed: true,
      late: false,
      detail: { xpEarned: 10, blockCredit: 0 },
    })
    expect(shared.snapshot(USER, YESTERDAY)).toMatchObject({ day_closed: true, xp_earned: 10 })
    expect(shared.progress(USER)).toMatchObject({
      xp_total: 10,
      current_streak: 1,
      last_active_date: YESTERDAY,
    })
  })

  it('49 outbound then 1 inbound (the inbound one is among the 50 read): the two agree again', async () => {
    const fixture: Fixture = { protocol: 'recomposicao', seed: (db) => messages(db, 49, 1) }
    const production = build(fixture)
    const shared = build(fixture)

    const summary = await runProductionCloser(production)
    clearCalcConfigCache()
    await closeLocalDay(shared.client, {
      userId: USER,
      timezone: TIMEZONE,
      date: YESTERDAY,
      now: new Date(),
      // As the production closer does (the other parity blocks ask for it too).
      advanceReevaluation: true,
    })

    expect(summary).toMatchObject({ processed: 1, skipped: 0, failed: 0 })
    // Each database numbers its own rows: the snapshot id is left out.
    const withoutSnapshotId = (db: DayCloseMemoryDb) =>
      finalizeCalls(db).map((params) => ({ ...params, p_snapshot_id: undefined }))
    expect(withoutSnapshotId(shared)).toHaveLength(1)
    expect(withoutSnapshotId(shared)).toEqual(withoutSnapshotId(production))
    expect(withoutClock(shared.progress(USER))).toEqual(withoutClock(production.progress(USER)))
    expect(shared.progress(USER)).toMatchObject({ xp_total: 10, current_streak: 1 })
  })
})
