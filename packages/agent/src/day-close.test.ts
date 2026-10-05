/**
 * Mechanics of the shared day close (`closeLocalDay`, `closePastOpenDays`):
 * what is found, what is skipped, what is written and what is never written.
 * The numbers of a closed day (XP, block credit, streak, medals) are locked in
 * `__golden__/audit-10-04-app-day-close.test.ts`; the equality with the
 * production closer in the worker package (`daily-closer.parity.test.ts`).
 *
 * Every test runs the exported functions against the in-memory database of
 * `testing/day-close-memory-db.ts`, which evaluates the filters and emulates
 * the generated column and the two RPCs. No network, no real database.
 *
 * Fixture person (synthetic): homem, 80 kg, 180 cm, born 1986-01-01 (40 years
 * old on the test dates), atividade leve.
 *   BMR (Mifflin) = 10×80 + 6,25×180 − 5×40 + 5 = 1730
 *   recomposição, déficit 500: 1730 × 1,2 − 500 = 1576; proteína 80 × 1,5 = 120
 *   ganho de massa: 1730 × 1,375 × 1,05 = 2497,69 → 2498
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from './calc-config-loader.js'
import {
  closeLocalDay,
  closePastOpenDays,
  DAY_CLOSE_GRACE_MS,
  latestClosableLocalDate,
  PRODUCTION_CLOSE_LAST_LOCAL_HOUR,
} from './day-close.js'
import { DayCloseMemoryDb } from './testing/day-close-memory-db.js'

const USER = '0b9f6f0e-0000-4000-8000-00000000da01'
const SAO_PAULO = 'America/Sao_Paulo'

const PROFILE = {
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
}
const RECOMP = { ...PROFILE, current_protocol: 'recomposicao', deficit_level: 500 }
const GANHO = { ...PROFILE, current_protocol: 'ganho_massa', deficit_level: null }
const RECOMP_TARGET = 1576
const GANHO_TARGET = 2498
const PROTEIN_TARGET = 120

/** A wall-clock instant in America/Sao_Paulo (UTC−3, no daylight saving since 2019). */
function sp(date: string, time: string): Date {
  return new Date(`${date}T${time}:00-03:00`)
}

function setup(profile: Record<string, unknown> = RECOMP, progress?: Record<string, unknown>) {
  const db = new DayCloseMemoryDb()
  db.addAccount({ userId: USER, profile, progress })
  return db
}

/** One lunch at noon and, optionally, one workout at 18h, registered with the given target. */
function day(
  db: DayCloseMemoryDb,
  date: string,
  input: { kcal: number; protein?: number; workout?: number; target?: number | null },
) {
  const target = input.target === undefined ? RECOMP_TARGET : input.target
  db.registerMeal({
    userId: USER,
    date,
    consumedAt: sp(date, '12:00').toISOString(),
    kcal: input.kcal,
    proteinG: input.protein ?? 0,
    mealType: 'almoco',
    caloriesTarget: target,
    proteinTarget: target === null ? null : PROTEIN_TARGET,
  })
  if (input.workout) {
    db.registerWorkout({
      userId: USER,
      date,
      performedAt: sp(date, '18:00').toISOString(),
      kcal: input.workout,
      caloriesTarget: target,
      proteinTarget: target === null ? null : PROTEIN_TARGET,
    })
  }
}

type Operation = DayCloseMemoryDb['operations'][number]

/** The lower and upper instants of a read filtered by a time range. */
function bounds(operation: Operation): unknown[] {
  return (operation.filters ?? [])
    .filter((filter) => filter.op === 'gte' || filter.op === 'lt')
    .map((filter) => filter.value)
}

/**
 * The sweep's re-check of earlier dates: the only read of a log table that
 * has a row limit of a full page and no ordering. (The discovery reads are
 * ordered; the reads of one date have no limit, or a limit of 1.)
 */
function isReCheck(operation: Operation): boolean {
  return (
    operation.kind === 'select' &&
    ['meal_logs', 'workout_logs', 'messages'].includes(operation.target) &&
    operation.limit === 1000 &&
    operation.ordered !== true
  )
}

function reChecks(db: DayCloseMemoryDb): Operation[] {
  return db.operations.filter(isReCheck)
}

beforeEach(() => {
  vi.useFakeTimers()
  clearCalcConfigCache()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('latestClosableLocalDate — today is never closed, yesterday waits 30 minutes', () => {
  it.each([
    ['23:59 of the 4th', sp('2026-10-04', '23:59'), '2026-10-03'],
    ['00:00 of the 5th', sp('2026-10-05', '00:00'), '2026-10-03'],
    ['00:10 of the 5th', sp('2026-10-05', '00:10'), '2026-10-03'],
    ['00:29 of the 5th', sp('2026-10-05', '00:29'), '2026-10-03'],
    ['00:30 of the 5th', sp('2026-10-05', '00:30'), '2026-10-04'],
    ['00:31 of the 5th', sp('2026-10-05', '00:31'), '2026-10-04'],
    ['12:00 of the 5th', sp('2026-10-05', '12:00'), '2026-10-04'],
  ])('America/Sao_Paulo, %s', (_label, now, expected) => {
    expect(latestClosableLocalDate(SAO_PAULO, now)).toBe(expected)
  })

  it('the wait is 30 minutes', () => {
    expect(DAY_CLOSE_GRACE_MS).toBe(30 * 60 * 1000)
  })

  it('America/New_York across the start of daylight saving (2026-03-08, a 23-hour day)', () => {
    // Local midnight of the 9th is 04:00Z (EDT, UTC−4).
    expect(latestClosableLocalDate('America/New_York', new Date('2026-03-09T04:29:00Z'))).toBe(
      '2026-03-07',
    )
    expect(latestClosableLocalDate('America/New_York', new Date('2026-03-09T04:30:00Z'))).toBe(
      '2026-03-08',
    )
    // "Now minus 24 h", which the production closer uses, lands on the 7th here.
    expect(latestClosableLocalDate('America/New_York', new Date('2026-03-09T04:45:00Z'))).toBe(
      '2026-03-08',
    )
  })
})

describe('closeLocalDay — one explicit date', () => {
  it('refuses today and yesterday-inside-the-wait without a single query', async () => {
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500 })
    day(db, '2026-10-03', { kcal: 1500 })
    const operationsBefore = db.operations.length

    const today = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-04', '23:59'),
    })
    const future = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-09',
      now: sp('2026-10-04', '23:59'),
    })
    const insideWait = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '00:10'),
    })

    expect(today).toMatchObject({ closed: false, reason: 'not_closable_yet' })
    expect(future).toMatchObject({ closed: false, reason: 'not_closable_yet' })
    expect(insideWait).toMatchObject({ closed: false, reason: 'not_closable_yet' })
    expect(db.operations.length).toBe(operationsBefore)
  })

  it('rejects a malformed date and a missing time zone', async () => {
    const db = setup()
    await expect(
      closeLocalDay(db.client, { userId: USER, timezone: SAO_PAULO, date: '04/10/2026' }),
    ).rejects.toThrow('date must be YYYY-MM-DD')
    await expect(
      closeLocalDay(db.client, { userId: USER, timezone: '', date: '2026-10-03' }),
    ).rejects.toThrow('timezone is required')
    expect(db.operations).toEqual([])
  })

  it("closes yesterday exactly once (at 08:00, past production's window: a late close)", async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })

    const first = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
    })
    // balance = 1500 − 1576 − 0 = −76; credit = 500 − (−76) = 576; XP 10 + 5 (proteína ≥ 100).
    expect(first).toMatchObject({
      closed: true,
      late: true,
      detail: {
        caloriesConsumed: 1500,
        storedCaloriesTarget: RECOMP_TARGET,
        caloriesTarget: RECOMP_TARGET,
        proteinTarget: PROTEIN_TARGET,
        dayStatus: 'complete',
        xpEarned: 15,
        blockCredit: 576,
        progress: {
          xpTotal: 15,
          currentStreak: 1,
          deficitBlock: 576,
          lastActiveDate: '2026-10-04',
        },
      },
    })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      day_closed: true,
      day_status: 'complete',
      closed_at: sp('2026-10-05', '08:00').toISOString(),
      xp_earned: 15,
      current_protocol: 'recomposicao',
    })
    expect(db.events(USER).map((event) => event.event)).toEqual(['daily_closer.completed'])

    const writesAfterFirst = db.writes.length
    const second = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:05'),
    })
    expect(second).toMatchObject({ closed: false, reason: 'already_closed' })
    expect(db.writes.length).toBe(writesAfterFirst)
    expect(db.progress(USER)).toMatchObject({ xp_total: 15, deficit_block: 576 })
  })

  it('an inactive date writes nothing: no row, no event, no progress change', async () => {
    const db = setup(RECOMP, { current_streak: 4, last_active_date: '2026-10-01' })
    const result = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
    })
    expect(result).toMatchObject({ closed: false, reason: 'inactive' })
    expect(db.writes).toEqual([])
    expect(db.snapshot(USER, '2026-10-04')).toBeNull()
    expect(db.progress(USER)).toMatchObject({ current_streak: 4 })
  })

  it('a day with only an inbound message: row created, base XP, credit 0, streak counts', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    db.addInboundMessage(USER, sp('2026-10-04', '10:00').toISOString())

    const result = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
    })
    expect(result.detail).toMatchObject({
      caloriesConsumed: 0,
      storedCaloriesTarget: null,
      caloriesTarget: RECOMP_TARGET,
      xpEarned: 10,
      blockCredit: 0,
      progress: { currentStreak: 1, deficitBlock: 0 },
    })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      day_closed: true,
      calories_consumed: 0,
    })
    expect(db.events(USER, 'bloco7700.skipped_inactive_day')).toHaveLength(1)
  })

  it('does not close a date at or behind last_active_date, nor one behind a closed day', async () => {
    const db = setup(RECOMP, { current_streak: 3, last_active_date: '2026-10-03' })
    day(db, '2026-10-01', { kcal: 1500 })
    const behindProgress = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-01',
      now: sp('2026-10-05', '08:00'),
    })
    expect(behindProgress).toMatchObject({ closed: false, reason: 'behind_frontier', late: true })

    // A day closed by hand in the admin panel has no progress behind it; the
    // row still marks the frontier.
    const db2 = setup()
    day(db2, '2026-10-01', { kcal: 1500 })
    day(db2, '2026-10-03', { kcal: 1500 })
    const closedByHand = db2.tables.daily_snapshots.find((row) => row.date === '2026-10-03')
    if (!closedByHand) throw new Error('fixture row missing')
    closedByHand.day_closed = true
    const behindRow = await closeLocalDay(db2.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-01',
      now: sp('2026-10-05', '08:00'),
    })
    expect(behindRow).toMatchObject({ closed: false, reason: 'behind_frontier' })
    expect(db.writes).toEqual([])
    expect(db2.writes).toEqual([])
  })

  it('creates the progress row when the account has none', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    db.tables.user_progress.length = 0
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })

    const result = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
    })
    expect(result.closed).toBe(true)
    expect(db.progress(USER)).toMatchObject({ xp_total: 15, level: 1, current_streak: 1 })
  })
})

describe('late close — the target already stored on the day is kept', () => {
  /** Two days registered with 3355 / 185.4; the profile now gives 2498 / 120. */
  function twoDaysWithAnOlderTarget() {
    const db = setup(GANHO)
    for (const date of ['2026-10-03', '2026-10-04']) {
      db.registerMeal({
        userId: USER,
        date,
        consumedAt: sp(date, '12:00').toISOString(),
        kcal: 2683,
        proteinG: 202.5,
        caloriesTarget: 3355,
        proteinTarget: 185.4,
      })
    }
    return db
  }

  it("a date before yesterday keeps the stored targets; yesterday inside production's window takes the profile targets", async () => {
    // 04:59 local: the last minute in which the production closer runs.
    const now = sp('2026-10-05', '04:59')
    vi.setSystemTime(now)
    const db = twoDaysWithAnOlderTarget()

    const late = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-03',
      now,
    })
    // Stored 3355 kept: credit = 3355 + 0 − 2683 = 672.
    expect(late).toMatchObject({
      late: true,
      detail: {
        storedCaloriesTarget: 3355,
        caloriesTarget: 3355,
        storedProteinTarget: 185.4,
        proteinTarget: 185.4,
        blockCredit: 672,
      },
    })
    expect(db.snapshot(USER, '2026-10-03')).toMatchObject({
      calories_target: 3355,
      protein_target: 185.4,
      daily_balance: -672,
    })

    const yesterday = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now,
    })
    // As the production closer: the profile target of the closing time, 2498.
    // credit = 2498 + 0 − 2683 = −185.
    expect(yesterday).toMatchObject({
      late: false,
      detail: {
        storedCaloriesTarget: 3355,
        caloriesTarget: GANHO_TARGET,
        proteinTarget: PROTEIN_TARGET,
        blockCredit: -185,
      },
    })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ calories_target: GANHO_TARGET })
    // 672 − 185 = 487
    expect(db.progress(USER)).toMatchObject({ deficit_block: 487, current_streak: 2 })
  })

  it.each([
    // local time of the close, late?, target written, credit = target − 2683
    ['00:30', false, GANHO_TARGET, PROTEIN_TARGET, -185],
    ['04:00', false, GANHO_TARGET, PROTEIN_TARGET, -185],
    ['04:59', false, GANHO_TARGET, PROTEIN_TARGET, -185],
    ['05:00', true, 3355, 185.4, 672],
    ['08:00', true, 3355, 185.4, 672],
    ['23:59', true, 3355, 185.4, 672],
  ])('yesterday closed at %s local: late = %s, target written %d', async (time, isLate, target, protein, credit) => {
    const now = sp('2026-10-05', time)
    vi.setSystemTime(now)
    const db = twoDaysWithAnOlderTarget()
    // 03/10 is closed first so the block starts from a known value (672).
    await closeLocalDay(db.client, { userId: USER, timezone: SAO_PAULO, date: '2026-10-03', now })

    const yesterday = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now,
    })

    expect(yesterday).toMatchObject({
      closed: true,
      late: isLate,
      detail: {
        storedCaloriesTarget: 3355,
        caloriesTarget: target,
        storedProteinTarget: 185.4,
        proteinTarget: protein,
        blockCredit: credit,
      },
    })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      calories_target: target,
      protein_target: protein,
      // The protocol written is the profile's in both cases.
      current_protocol: 'ganho_massa',
    })
    expect(db.progress(USER)).toMatchObject({ deficit_block: Math.max(0, 672 + credit) })
  })

  it("the window is the production closer's: local hours 0 to 4", () => {
    expect(PRODUCTION_CLOSE_LAST_LOCAL_HOUR).toBe(4)
  })

  it('today and a future date are never reported as late', async () => {
    const db = setup()
    for (const date of ['2026-10-05', '2026-10-09']) {
      const result = await closeLocalDay(db.client, {
        userId: USER,
        timezone: SAO_PAULO,
        date,
        now: sp('2026-10-05', '08:00'),
      })
      expect(result).toMatchObject({ closed: false, reason: 'not_closable_yet', late: false })
    }
  })

  it('yesterday closed late with NO stored target (a message-only day) takes the profile targets', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup(GANHO)
    db.addInboundMessage(USER, sp('2026-10-04', '10:00').toISOString())

    const result = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now,
    })
    expect(result).toMatchObject({
      late: true,
      detail: {
        storedCaloriesTarget: null,
        caloriesTarget: GANHO_TARGET,
        storedProteinTarget: null,
        proteinTarget: PROTEIN_TARGET,
      },
    })
  })

  it('a late day falls back to the profile only for the field that is null', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup(GANHO)
    day(db, '2026-10-02', { kcal: 2000, target: null })
    const row = db.tables.daily_snapshots.find((candidate) => candidate.date === '2026-10-02')
    if (!row) throw new Error('fixture row missing')
    row.protein_target = 150

    const result = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-02',
      now: sp('2026-10-05', '08:00'),
    })
    expect(result.detail).toMatchObject({
      storedCaloriesTarget: null,
      caloriesTarget: GANHO_TARGET,
      storedProteinTarget: 150,
      proteinTarget: 150,
    })
  })

  it('a late day with both targets stored does not read the profile targets at all', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup(GANHO)
    day(db, '2026-10-02', { kcal: 2000, target: 3000 })
    await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-02',
      now: sp('2026-10-05', '08:00'),
    })
    const profileReads = db.operations.filter((operation) => operation.target === 'user_profiles')
    // One read: protocol and deficit level, for the design deficit.
    expect(profileReads).toHaveLength(1)
  })
})

describe('day status and block credit of special days', () => {
  it('under-registration (< 50% of the target): complete, credits only the design deficit', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 700, protein: 40 })
    const result = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
    })
    // 700 < 0,5 × 1576 = 788 → the observed deficit is not credited.
    expect(result.detail).toMatchObject({ dayStatus: 'complete', blockCredit: 500, xpEarned: 10 })
    expect(db.events(USER, 'bloco7700.skipped_subregistro')[0]?.properties).toEqual({
      date: '2026-10-04',
      day_status: 'complete',
      calories_consumed: 700,
      calories_target: 1576,
      pct: 44,
    })
  })

  it('user_skipped: the confirmed skip credits the observed balance, even under 50%', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 700, protein: 40 })
    db.tables.product_events.push(
      db.withDefaults('product_events', {
        user_id: USER,
        event: 'meal.user_skipped',
        properties: { local_date: '2026-10-04', meal_type: 'jantar' },
      }),
    )
    const result = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
    })
    // credit = 500 − (700 − 1576) = 1376
    expect(result.detail).toMatchObject({ dayStatus: 'user_skipped', blockCredit: 1376 })
    expect(db.events(USER, 'bloco7700.skipped_subregistro')).toEqual([])
  })

  it('incomplete_no_response needs a recorded reminder; without it the same day is complete', async () => {
    vi.setSystemTime(sp('2026-10-08', '08:00'))
    const build = (reminder: boolean) => {
      const db = setup()
      // Six earlier days with café, almoço and jantar establish the pattern.
      for (const date of [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
      ]) {
        for (const [mealType, time] of [
          ['cafe', '08:00'],
          ['almoco', '12:00'],
          ['jantar', '20:00'],
        ] as const) {
          db.registerMeal({
            userId: USER,
            date,
            consumedAt: sp(date, time).toISOString(),
            kcal: 500,
            mealType,
            caloriesTarget: RECOMP_TARGET,
            proteinTarget: PROTEIN_TARGET,
          })
        }
      }
      // The 7th has no jantar.
      for (const [mealType, time] of [
        ['cafe', '08:00'],
        ['almoco', '12:00'],
      ] as const) {
        db.registerMeal({
          userId: USER,
          date: '2026-10-07',
          consumedAt: sp('2026-10-07', time).toISOString(),
          kcal: 600,
          mealType,
          caloriesTarget: RECOMP_TARGET,
          proteinTarget: PROTEIN_TARGET,
        })
      }
      if (reminder) {
        const row = db.tables.daily_snapshots.find((candidate) => candidate.date === '2026-10-07')
        if (!row) throw new Error('fixture row missing')
        row.gap_reminder_sent_at = sp('2026-10-07', '21:30').toISOString()
      }
      return db
    }
    const input = {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-07',
      now: sp('2026-10-08', '08:00'),
    }

    const withReminder = build(true)
    const incomplete = await closeLocalDay(withReminder.client, input)
    expect(incomplete.detail).toMatchObject({ dayStatus: 'incomplete_no_response', blockCredit: 0 })
    expect(withReminder.events(USER, 'bloco7700.skipped_incomplete_day')[0]?.properties).toEqual({
      date: '2026-10-07',
      gap: ['jantar'],
      reason: 'lembrete enviado, paciente não respondeu',
    })

    const withoutReminder = build(false)
    const complete = await closeLocalDay(withoutReminder.client, input)
    // credit = 500 − (1200 − 1576) = 876
    expect(complete.detail).toMatchObject({ dayStatus: 'complete', blockCredit: 876 })
  })
})

describe('reassessment schedule — off unless asked for', () => {
  it('default: the schedule RPC is not called and next_reevaluation stays null', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500 })
    await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
    })
    expect(db.operations.filter((op) => op.kind === 'rpc').map((op) => op.target)).toEqual([
      'finalize_daily_close_atomic',
    ])
    expect(db.progress(USER)).toMatchObject({ next_reevaluation: null })
    expect(db.events(USER, 'reevaluation.due')).toEqual([])
  })

  it('advanceReevaluation: true calls it with the closed date, as the production closer does', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500 })
    await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now: sp('2026-10-05', '08:00'),
      advanceReevaluation: true,
    })
    expect(db.operations.filter((op) => op.kind === 'rpc').at(-1)).toMatchObject({
      target: 'advance_reevaluation_schedule',
      params: { p_user_id: USER, p_closing_date: '2026-10-04' },
    })
    // first day row 2026-10-04 + 14
    expect(db.progress(USER)).toMatchObject({ next_reevaluation: '2026-10-18' })
  })
})

describe('the day row is re-checked and written conditionally', () => {
  const input = {
    userId: USER,
    timezone: SAO_PAULO,
    date: '2026-10-04',
    now: sp('2026-10-05', '08:00'),
  }

  it('the write of an existing row is an update filtered on id, day_closed = false and the version read', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500 })
    const row = db.snapshot(USER, '2026-10-04')
    await closeLocalDay(db.client, input)

    const dayWrites = db.writes.filter((operation) => operation.target === 'daily_snapshots')
    expect(dayWrites).toHaveLength(1)
    expect(dayWrites[0]).toMatchObject({ kind: 'update' })
    expect(dayWrites[0]?.filters).toEqual([
      { op: 'eq', column: 'id', value: row?.id },
      { op: 'eq', column: 'day_closed', value: false },
      { op: 'eq', column: 'updated_at', value: row?.updated_at },
    ])
    // The read just before it asks for day_closed again.
    const index = db.operations.indexOf(dayWrites[0] as (typeof db.operations)[number])
    expect(db.operations[index - 1]).toMatchObject({ kind: 'select', target: 'daily_snapshots' })
  })

  it('a meal registered after the sums were read: nothing is written, the day stays open', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1000 })
    let injected = false
    db.before = (operation) => {
      // Right after the close read the logs, before it reads the profile.
      if (!injected && operation.kind === 'select' && operation.target === 'user_profiles') {
        injected = true
        db.registerMeal({
          userId: USER,
          date: '2026-10-04',
          consumedAt: sp('2026-10-04', '21:00').toISOString(),
          kcal: 500,
          caloriesTarget: RECOMP_TARGET,
          proteinTarget: PROTEIN_TARGET,
        })
      }
    }

    const first = await closeLocalDay(db.client, input)
    expect(first).toMatchObject({ closed: false, reason: 'changed_concurrently' })
    expect(db.writes).toEqual([])
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      day_closed: false,
      calories_consumed: 1500,
    })

    db.before = null
    const second = await closeLocalDay(db.client, input)
    // The next attempt sees both meals: 1500 − 1576 = −76 → credit 576.
    expect(second.detail).toMatchObject({ caloriesConsumed: 1500, blockCredit: 576 })
  })

  it('a meal registered between the re-check and the write: the conditional update changes no row', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1000 })
    db.before = (operation) => {
      if (operation.kind === 'update' && operation.target === 'daily_snapshots') {
        db.before = null
        db.registerMeal({
          userId: USER,
          date: '2026-10-04',
          consumedAt: sp('2026-10-04', '21:00').toISOString(),
          kcal: 500,
          caloriesTarget: RECOMP_TARGET,
          proteinTarget: PROTEIN_TARGET,
        })
      }
    }
    const result = await closeLocalDay(db.client, input)
    expect(result).toMatchObject({ closed: false, reason: 'changed_concurrently' })
    // The stale sum (1000) did not overwrite the row.
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      day_closed: false,
      calories_consumed: 1500,
    })
    expect(db.operations.some((operation) => operation.kind === 'rpc')).toBe(false)
  })

  it('a message-only day whose row appears meanwhile is not overwritten', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    db.addInboundMessage(USER, sp('2026-10-04', '10:00').toISOString())
    db.before = (operation) => {
      if (operation.kind === 'upsert' && operation.target === 'daily_snapshots') {
        db.before = null
        db.registerMeal({
          userId: USER,
          date: '2026-10-04',
          consumedAt: sp('2026-10-04', '21:00').toISOString(),
          kcal: 900,
          caloriesTarget: RECOMP_TARGET,
          proteinTarget: PROTEIN_TARGET,
        })
      }
    }
    const result = await closeLocalDay(db.client, input)
    expect(result).toMatchObject({ closed: false, reason: 'changed_concurrently' })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      day_closed: false,
      calories_consumed: 900,
    })
  })

  it('a day closed by another request before the write: nothing is written', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    let raced = false
    db.before = async (operation) => {
      if (!raced && operation.kind === 'select' && operation.target === 'user_profiles') {
        raced = true
        db.before = null
        await closeLocalDay(db.client, input)
      }
    }
    const loser = await closeLocalDay(db.client, input)
    expect(loser).toMatchObject({ closed: false, reason: 'closed_concurrently' })
    expect(db.progress(USER)).toMatchObject({ xp_total: 15, deficit_block: 576, current_streak: 1 })
    expect(db.events(USER, 'daily_closer.completed')).toHaveLength(1)
  })

  it('finalization answers applied = false: no event is written by the loser', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 700, protein: 40 })
    db.before = (operation) => {
      // The other request finalizes in the instant before this one's RPC.
      if (operation.kind === 'rpc' && operation.target === 'finalize_daily_close_atomic') {
        db.before = null
        const row = db.tables.daily_snapshots.find((candidate) => candidate.date === '2026-10-04')
        if (!row) throw new Error('fixture row missing')
        row.day_closed = true
      }
    }
    const result = await closeLocalDay(db.client, input)
    expect(result).toMatchObject({ closed: false, reason: 'closed_concurrently' })
    // Under-registered day: the production closer would already have written
    // its "skipped" event before the RPC. Here nothing was.
    expect(db.events(USER)).toEqual([])
    expect(db.progress(USER)).toMatchObject({ xp_total: 0, deficit_block: 0 })
  })
})

describe('closePastOpenDays — dates come from the data', () => {
  it('nothing may be closed yet (the first allowed date is today): not a single query', async () => {
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500 })
    const before = db.operations.length
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-04', '12:00'),
      from: '2026-10-04',
    })
    expect(result).toMatchObject({ days: [], complete: true, latestClosableDate: '2026-10-03' })
    expect(db.operations.length).toBe(before)
  })

  it('yesterday already closed: one query and nothing else', async () => {
    const db = setup(RECOMP, { current_streak: 2, last_active_date: '2026-10-04' })
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '09:00'),
      from: '2026-09-01',
    })
    expect(result.days).toEqual([])
    expect(db.operations).toHaveLength(1)
    expect(db.operations[0]).toMatchObject({ kind: 'select', target: 'user_progress' })
  })

  it('twelve empty dates before one registered day: closed in the FIRST call; the second call writes nothing', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    const input = {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      // 22/09 … 03/10 are twelve dates with nothing on them.
      from: '2026-09-22',
      limits: { maxDays: 3, maxMs: 4000 },
    }

    const first = await closePastOpenDays(db.client, input)
    expect(first.days.map((entry) => [entry.date, entry.closed])).toEqual([['2026-10-04', true]])
    expect(first.complete).toBe(true)
    // Only dates with data are visited: one day row read, not thirteen.
    const dayRowReads = db.operations.filter(
      (operation) =>
        operation.target === 'daily_snapshots' &&
        operation.filters?.some((filter) => filter.column === 'date' && filter.op === 'eq'),
    )
    expect(new Set(dayRowReads.map((operation) => operation.filters?.[1]?.value))).toEqual(
      new Set(['2026-10-04']),
    )

    const operationsAfterFirst = db.operations.length
    const writesAfterFirst = db.writes.length
    const second = await closePastOpenDays(db.client, input)
    expect(second.days).toEqual([])
    expect(db.writes.length).toBe(writesAfterFirst)
    expect(db.operations.length).toBe(operationsAfterFirst + 1)
    expect(db.events(USER).map((event) => event.event)).toEqual(['daily_closer.completed'])
  })

  it('an account with no data at all: reads only, and never the "skipped" event', async () => {
    const db = setup()
    const input = {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
    }
    await closePastOpenDays(db.client, input)
    await closePastOpenDays(db.client, input)
    expect(db.writes).toEqual([])
    // Progress, then the four discovery reads, per call.
    expect(db.operations).toHaveLength(10)
    expect(db.events(USER)).toEqual([])
  })

  it('finds message-only dates and workout-only dates, and ignores dates before `from`', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    db.addInboundMessage(USER, sp('2026-09-20', '10:00').toISOString())
    db.addInboundMessage(USER, sp('2026-10-01', '23:50').toISOString())
    db.registerWorkout({
      userId: USER,
      date: '2026-10-03',
      performedAt: sp('2026-10-03', '07:00').toISOString(),
      kcal: 300,
      caloriesTarget: RECOMP_TARGET,
      proteinTarget: PROTEIN_TARGET,
    })
    // An outbound message is not activity.
    db.tables.messages.push(
      db.withDefaults('messages', {
        user_id: USER,
        direction: 'out',
        created_at: sp('2026-10-02', '10:00').toISOString(),
      }),
    )

    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
    })
    expect(result.days.map((entry) => [entry.date, entry.closed])).toEqual([
      ['2026-10-01', true],
      ['2026-10-03', true],
    ])
    expect(db.snapshot(USER, '2026-09-20')).toBeNull()
    expect(db.snapshot(USER, '2026-10-02')).toBeNull()
  })

  it('an open row with water only (no meal, workout or message) is not visited: no query on it, it stays open, blocks nothing', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    db.tables.daily_snapshots.push(
      db.withDefaults('daily_snapshots', {
        user_id: USER,
        date: '2026-10-03',
        water_consumed_ml: 500,
      }),
    )
    day(db, '2026-10-04', { kcal: 1500 })
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
      limits: { maxDays: 1 },
    })
    expect(result.days.map((entry) => [entry.date, entry.closed, entry.reason])).toEqual([
      ['2026-10-04', true, undefined],
    ])
    expect(result.inactiveOpenDates).toEqual(['2026-10-03'])
    expect(result.staleOpenDates).toEqual([])
    expect(result.pendingDates).toEqual([])
    expect(result.complete).toBe(true)
    expect(db.snapshot(USER, '2026-10-03')).toMatchObject({ day_closed: false, xp_earned: 0 })
    // Not one query names 03/10.
    expect(
      db.operations.filter((operation) =>
        operation.filters?.some((filter) => filter.value === '2026-10-03'),
      ),
    ).toEqual([])
  })

  it('an open row with water only and nothing after it: five reads, no write, on every call', async () => {
    const db = setup()
    db.tables.daily_snapshots.push(
      db.withDefaults('daily_snapshots', {
        user_id: USER,
        date: '2026-10-04',
        water_consumed_ml: 500,
      }),
    )
    const input = {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
    }
    const first = await closePastOpenDays(db.client, input)
    const second = await closePastOpenDays(db.client, input)
    expect(first).toMatchObject({ days: [], inactiveOpenDates: ['2026-10-04'], complete: true })
    expect(second).toEqual(first)
    expect(db.writes).toEqual([])
    // Progress, then the four discovery reads, per call (it was eleven).
    expect(db.operations).toHaveLength(10)
  })

  it('the row is judged by the same local-day bounds closeLocalDay uses: a meal at 23:59 is of that day, one at 00:00 is not', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    for (const date of ['2026-10-02', '2026-10-03']) {
      db.tables.daily_snapshots.push(
        db.withDefaults('daily_snapshots', { user_id: USER, date, water_consumed_ml: 500 }),
      )
    }
    // A meal row whose instant is inside 02/10 (local) with no link to that
    // day row, and nothing inside 03/10: the instant decides, not the row.
    db.tables.meal_logs.push(
      db.withDefaults('meal_logs', {
        user_id: USER,
        snapshot_id: null,
        consumed_at: sp('2026-10-02', '23:59').toISOString(),
        meal_type: 'ceia',
        kcal: 200,
        protein_g: 10,
        carbs_g: 0,
        fat_g: 0,
      }),
    )
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
    })
    expect(result.days.map((entry) => [entry.date, entry.closed])).toEqual([['2026-10-02', true]])
    expect(result.inactiveOpenDates).toEqual(['2026-10-03'])
    expect(db.snapshot(USER, '2026-10-02')).toMatchObject({
      day_closed: true,
      calories_consumed: 200,
    })
  })

  it('a water-only row behind the frontier is reported as stale, as before, not as inactive', async () => {
    const db = setup(RECOMP, { current_streak: 1, last_active_date: '2026-10-03' })
    db.tables.daily_snapshots.push(
      db.withDefaults('daily_snapshots', {
        user_id: USER,
        date: '2026-10-02',
        water_consumed_ml: 500,
      }),
    )
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
    })
    expect(result.staleOpenDates).toEqual(['2026-10-02'])
    expect(result.inactiveOpenDates).toEqual([])
  })
})

describe('closePastOpenDays — a full page of rows', () => {
  it('1000 rows in one read may hide later dates: what was found is closed, inactivity waits for the next call', async () => {
    vi.setSystemTime(sp('2026-10-06', '08:00'))
    const db = setup(RECOMP, {
      current_streak: 2,
      longest_streak: 2,
      last_active_date: '2026-09-30',
    })
    // A thousand inbound messages on 01/10 fill the page of that read.
    for (let index = 0; index < 1000; index++) {
      db.addInboundMessage(USER, sp('2026-10-01', '10:00').toISOString())
    }
    // 02/10 has one message the full page did not return, and nothing else.
    db.addInboundMessage(USER, sp('2026-10-02', '10:00').toISOString())
    const input = {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-06', '08:00'),
      from: '2026-09-22',
    }

    const first = await closePastOpenDays(db.client, input)
    expect(first.days.map((entry) => [entry.date, entry.closed])).toEqual([['2026-10-01', true]])
    expect(first.complete).toBe(false)
    // 05/10 − 01/10 = 4 days, but the streak is NOT zeroed on a partial view.
    expect(first.streakReset).toBeNull()
    expect(db.progress(USER)).toMatchObject({ current_streak: 3, last_active_date: '2026-10-01' })

    // The frontier moved, so the next call reads from 02/10 on and finds it.
    const second = await closePastOpenDays(db.client, input)
    expect(second.days.map((entry) => [entry.date, entry.closed])).toEqual([['2026-10-02', true]])
    expect(second.complete).toBe(true)
    // 03/10, 04/10 and 05/10 are empty: 05/10 − 02/10 = 3.
    expect(second.streakReset).toMatchObject({ applied: true, previousStreak: 4, gapDays: 3 })
    expect(db.progress(USER)).toMatchObject({ current_streak: 0, longest_streak: 4 })
  })
})

describe('closePastOpenDays — a full page of rows (open rows with no activity seen)', () => {
  it('on a full page every open row is still visited, as before: the rows read may not be all of them', async () => {
    vi.setSystemTime(sp('2026-10-06', '08:00'))
    const db = setup()
    // A thousand inbound messages on 01/10 fill the page of that read…
    for (let index = 0; index < 1000; index++) {
      db.addInboundMessage(USER, sp('2026-10-01', '10:00').toISOString())
    }
    // …so the message of 02/10 was not returned, and its open row (water)
    // looks like a row with no activity.
    db.addInboundMessage(USER, sp('2026-10-02', '10:00').toISOString())
    db.tables.daily_snapshots.push(
      db.withDefaults('daily_snapshots', {
        user_id: USER,
        date: '2026-10-02',
        water_consumed_ml: 500,
      }),
    )
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-06', '08:00'),
      from: '2026-09-22',
    })
    expect(result.days.map((entry) => [entry.date, entry.closed])).toEqual([
      ['2026-10-01', true],
      ['2026-10-02', true],
    ])
    expect(result.inactiveOpenDates).toEqual([])
    expect(result.complete).toBe(false)
    // And the re-check of earlier dates is not asked on a partial view.
    expect(reChecks(db)).toEqual([])
  })
})

describe('closePastOpenDays — budget of one call', () => {
  function fiveDays() {
    const db = setup()
    for (const date of ['2026-09-30', '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04']) {
      day(db, date, { kcal: 1500, protein: 110 })
    }
    return db
  }
  const input = {
    userId: USER,
    timezone: SAO_PAULO,
    now: sp('2026-10-05', '08:00'),
    from: '2026-09-22',
  }

  it('maxDays counts days closed; the rest is reported and closed by the next call, in order', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = fiveDays()
    const first = await closePastOpenDays(db.client, { ...input, limits: { maxDays: 3 } })
    expect(first.days.map((entry) => entry.date)).toEqual([
      '2026-09-30',
      '2026-10-01',
      '2026-10-02',
    ])
    expect(first.pendingDates).toEqual(['2026-10-03', '2026-10-04'])
    expect(first.complete).toBe(false)
    expect(db.progress(USER)).toMatchObject({ current_streak: 3, last_active_date: '2026-10-02' })

    const second = await closePastOpenDays(db.client, { ...input, limits: { maxDays: 3 } })
    expect(second.days.map((entry) => entry.date)).toEqual(['2026-10-03', '2026-10-04'])
    expect(second.complete).toBe(true)
    // 5 × 15 XP; 5 × 576 kcal
    expect(db.progress(USER)).toMatchObject({
      current_streak: 5,
      xp_total: 75,
      deficit_block: 2880,
      last_active_date: '2026-10-04',
    })
  })

  it('maxMs is checked before each day with the elapsed time of the call', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = fiveDays()
    let elapsed = 0
    const clock = () => elapsed
    db.before = (operation) => {
      // Every finalized day "takes" 1500 ms.
      if (operation.kind === 'rpc') elapsed += 1500
    }
    const result = await closePastOpenDays(db.client, {
      ...input,
      limits: { maxDays: 10, maxMs: 4000 },
      clock,
    })
    // 0 → 1500 → 3000 → 4500: the fourth day does not start.
    expect(result.days.map((entry) => entry.date)).toEqual([
      '2026-09-30',
      '2026-10-01',
      '2026-10-02',
    ])
    expect(result.pendingDates).toEqual(['2026-10-03', '2026-10-04'])
  })

  it('a failure on the third of five days: two stay closed, the error surfaces, the next call resumes with no XP twice', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = fiveDays()
    let finalized = 0
    db.failWith = (operation) => {
      if (operation.kind !== 'rpc') return null
      finalized += 1
      return finalized === 3 ? 'database unavailable' : null
    }
    await expect(closePastOpenDays(db.client, input)).rejects.toThrow('database unavailable')
    expect(db.progress(USER)).toMatchObject({
      xp_total: 30,
      current_streak: 2,
      last_active_date: '2026-10-01',
    })
    expect(db.snapshot(USER, '2026-10-02')).toMatchObject({ day_closed: false })

    db.failWith = null
    const resumed = await closePastOpenDays(db.client, input)
    expect(resumed.days.map((entry) => entry.date)).toEqual([
      '2026-10-02',
      '2026-10-03',
      '2026-10-04',
    ])
    expect(db.progress(USER)).toMatchObject({
      xp_total: 75,
      current_streak: 5,
      deficit_block: 2880,
    })
    expect(db.events(USER, 'daily_closer.completed')).toHaveLength(5)
  })
})

describe('closePastOpenDays — strictly in order: a date that changed while it was being closed stops the sweep', () => {
  // Review of 2026-10-05 (both lenses, HIGH): the sweep went on to the later
  // dates, the later day closed, the frontier passed the earlier one and it
  // never closed again.
  const limits = { maxDays: 3, maxMs: 4000 }

  it("the reviewer's reproduction: a meal saved on the OLDER of two open days during its close", async () => {
    const now = sp('2026-10-04', '08:00')
    vi.setSystemTime(now)
    const db = setup()
    day(db, '2026-10-02', { kcal: 1500, protein: 110 })
    day(db, '2026-10-03', { kcal: 1500, protein: 110 })
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-22', limits }
    let injected = false
    db.before = (operation) => {
      // During the close of 02/10, after its logs were read.
      if (!injected && operation.kind === 'select' && operation.target === 'user_profiles') {
        injected = true
        db.registerMeal({
          userId: USER,
          date: '2026-10-02',
          consumedAt: sp('2026-10-02', '20:00').toISOString(),
          kcal: 300,
          proteinG: 20,
          mealType: 'jantar',
          caloriesTarget: RECOMP_TARGET,
          proteinTarget: PROTEIN_TARGET,
        })
      }
    }

    const first = await closePastOpenDays(db.client, input)
    db.before = null

    expect(injected).toBe(true)
    // 03/10 was NOT attempted.
    expect(first.days.map((entry) => [entry.date, entry.closed, entry.reason])).toEqual([
      ['2026-10-02', false, 'changed_concurrently'],
    ])
    expect(first.pendingDates).toEqual(['2026-10-02', '2026-10-03'])
    expect(first.complete).toBe(false)
    expect(first.streakReset).toBeNull()
    expect(db.writes).toEqual([])
    expect(db.progress(USER)).toMatchObject({ xp_total: 0, last_active_date: null })
    expect(db.snapshot(USER, '2026-10-03')).toMatchObject({ day_closed: false })

    const second = await closePastOpenDays(db.client, input)
    expect(second.days.map((entry) => [entry.date, entry.closed])).toEqual([
      ['2026-10-02', true],
      ['2026-10-03', true],
    ])
    expect(second.staleOpenDates).toEqual([])
    expect(second.complete).toBe(true)
    // 02/10 with the dinner: 1800 − 1576 = +224 → 500 − 224 = 276; 130 g → XP 15.
    // 03/10: 1500 − 1576 = −76 → 576; 110 g → XP 15.
    expect(db.snapshot(USER, '2026-10-02')).toMatchObject({
      day_closed: true,
      calories_consumed: 1800,
    })
    expect(db.progress(USER)).toMatchObject({
      xp_total: 30,
      current_streak: 2,
      deficit_block: 852,
      last_active_date: '2026-10-03',
    })
  })

  it('a message-only day whose row appears during its close: the later day waits too', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup()
    db.addInboundMessage(USER, sp('2026-10-03', '10:00').toISOString())
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-22', limits }
    db.before = (operation) => {
      if (operation.kind === 'upsert' && operation.target === 'daily_snapshots') {
        db.before = null
        day(db, '2026-10-03', { kcal: 900, protein: 50 })
      }
    }

    const first = await closePastOpenDays(db.client, input)
    expect(first.days.map((entry) => [entry.date, entry.reason])).toEqual([
      ['2026-10-03', 'changed_concurrently'],
    ])
    expect(first.pendingDates).toEqual(['2026-10-03', '2026-10-04'])
    expect(db.operations.some((operation) => operation.kind === 'rpc')).toBe(false)

    const second = await closePastOpenDays(db.client, input)
    // 03/10: 900 − 1576 = −676 → 1176 (900 ≥ 788); XP 10. 04/10: 576; XP 15.
    expect(second.days.map((entry) => [entry.date, entry.detail?.blockCredit])).toEqual([
      ['2026-10-03', 1176],
      ['2026-10-04', 576],
    ])
    expect(db.progress(USER)).toMatchObject({
      xp_total: 25,
      current_streak: 2,
      deficit_block: 1752,
    })
  })

  it('the stop is not the budget: with an unlimited budget the later dates still wait', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup(RECOMP, { current_streak: 4, last_active_date: '2026-09-29' })
    for (const date of ['2026-10-01', '2026-10-02', '2026-10-03']) day(db, date, { kcal: 1500 })
    db.before = (operation) => {
      const row = db.snapshot(USER, '2026-10-02')
      if (
        operation.kind === 'update' &&
        operation.target === 'daily_snapshots' &&
        operation.filters?.some((filter) => filter.value === row?.id)
      ) {
        db.before = null
        day(db, '2026-10-02', { kcal: 200 })
      }
    }

    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now,
      from: '2026-09-22',
    })
    expect(result.days.map((entry) => [entry.date, entry.closed, entry.reason])).toEqual([
      ['2026-10-01', true, undefined],
      ['2026-10-02', false, 'changed_concurrently'],
    ])
    expect(result.pendingDates).toEqual(['2026-10-02', '2026-10-03'])
    expect(result.complete).toBe(false)
    // 30/09 is empty, so 01/10 restarts at 1; and with a date still waiting
    // the streak is not zeroed (04/10 − 01/10 = 3 days would zero it).
    expect(result.streakReset).toBeNull()
    expect(db.progress(USER)).toMatchObject({ current_streak: 1, last_active_date: '2026-10-01' })
  })

  it('a day another request finalized meanwhile does NOT stop the sweep: that date is resolved', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup()
    day(db, '2026-10-03', { kcal: 1500, protein: 110 })
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    let raced = false
    db.before = async (operation) => {
      // Another request closes 03/10 whole while this one is inside it.
      if (!raced && operation.kind === 'select' && operation.target === 'user_profiles') {
        raced = true
        const saved = db.before
        db.before = null
        await closeLocalDay(db.client, {
          userId: USER,
          timezone: SAO_PAULO,
          date: '2026-10-03',
          now,
        })
        db.before = saved
      }
    }

    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now,
      from: '2026-09-22',
    })
    expect(result.days.map((entry) => [entry.date, entry.closed, entry.reason])).toEqual([
      ['2026-10-03', false, 'closed_concurrently'],
      ['2026-10-04', true, undefined],
    ])
    expect(result.pendingDates).toEqual([])
    expect(result.complete).toBe(true)
    expect(db.progress(USER)).toMatchObject({
      xp_total: 30,
      current_streak: 2,
      deficit_block: 1152,
      last_active_date: '2026-10-04',
    })
    expect(db.events(USER, 'daily_closer.completed')).toHaveLength(2)
  })
})

describe('closePastOpenDays — a record that appears on an earlier open date stops the sweep before the finalization', () => {
  // Review of 2026-10-05 (LOW): the dates are fixed by the sweep's first
  // read. A FIRST record landing meanwhile on an earlier date that had none
  // was not among them; the later day closed, the frontier passed the earlier
  // one and it stayed open for good. The reviewer's exact case, with its
  // numbers, is in the golden file.
  const limits = { maxDays: 3, maxMs: 4000 }
  const dinner = (db: DayCloseMemoryDb, date: string) =>
    db.registerMeal({
      userId: USER,
      date,
      consumedAt: sp(date, '21:00').toISOString(),
      kcal: 500,
      proteinG: 50,
      mealType: 'jantar',
      caloriesTarget: RECOMP_TARGET,
      proteinTarget: PROTEIN_TARGET,
    })

  it('the date right after the frontier has nothing in between: the re-check costs no query', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup(RECOMP, { current_streak: 1, last_active_date: '2026-10-03' })
    day(db, '2026-10-04', { kcal: 1500 })
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
      limits,
    })
    expect(result.days.map((entry) => [entry.date, entry.closed])).toEqual([['2026-10-04', true]])
    expect(reChecks(db)).toEqual([])
  })

  it('consecutive days closed by one call: no re-check either (each is the day after the one just closed)', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup(RECOMP, { current_streak: 1, last_active_date: '2026-10-01' })
    for (const date of ['2026-10-02', '2026-10-03', '2026-10-04']) day(db, date, { kcal: 1500 })
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
      limits,
    })
    expect(result.days.filter((entry) => entry.closed)).toHaveLength(3)
    expect(reChecks(db)).toEqual([])
  })

  it('empty dates between the frontier and the day: three reads, bounded by those dates, right before the finalization', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup(RECOMP, { current_streak: 1, last_active_date: '2026-10-01' })
    day(db, '2026-10-04', { kcal: 1500 })
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
      limits,
    })
    expect(result.days.map((entry) => [entry.date, entry.closed])).toEqual([['2026-10-04', true]])
    // From the start of 02/10 (the day after the frontier) to the start of 04/10.
    const since = sp('2026-10-02', '00:00').toISOString()
    const until = sp('2026-10-04', '00:00').toISOString()
    expect(reChecks(db).map((operation) => [operation.target, bounds(operation)])).toEqual([
      ['meal_logs', [since, until]],
      ['workout_logs', [since, until]],
      ['messages', [since, until]],
    ])
    // They travel with the last progress read: only the RPC comes after them.
    const targets = db.operations.map((operation) => operation.target)
    const finalize = targets.indexOf('finalize_daily_close_atomic')
    expect(targets.slice(finalize - 4, finalize)).toEqual([
      'user_progress',
      'meal_logs',
      'workout_logs',
      'messages',
    ])
  })

  it('a record the first read already returned, on an earlier date that stays open, does not stop the sweep (Africa/Cairo, the night the clocks go forward)', async () => {
    // "Appeared" means an instant the first read did not return, not "any
    // record on an earlier open date". The one known case of a seen record
    // that stays on an open date is the declared daylight-saving one: a meal
    // at 23:30 of 23/04 is of 23/04 by the calendar and of 24/04 by the
    // day-bounds helper, so 23/04 is inactive and 24/04 is not a candidate.
    // Asking "is there any record before 25/04" would hold 25/04 back on
    // every request, for good.
    const now = new Date('2026-04-26T05:00:00.000Z') // 08:00 in Cairo (UTC+3)
    vi.setSystemTime(now)
    const db = setup()
    db.registerMeal({
      userId: USER,
      date: '2026-04-23',
      consumedAt: '2026-04-23T21:30:00.000Z', // 23:30 in Cairo (UTC+2)
      kcal: 400,
      proteinG: 20,
      mealType: 'ceia',
      caloriesTarget: RECOMP_TARGET,
      proteinTarget: PROTEIN_TARGET,
    })
    db.registerMeal({
      userId: USER,
      date: '2026-04-25',
      consumedAt: '2026-04-25T09:00:00.000Z', // 12:00 in Cairo
      kcal: 1500,
      proteinG: 110,
      mealType: 'almoco',
      caloriesTarget: RECOMP_TARGET,
      proteinTarget: PROTEIN_TARGET,
    })
    const input = { userId: USER, timezone: 'Africa/Cairo', now, from: '2026-04-20', limits }

    const first = await closePastOpenDays(db.client, input)

    expect(first.days.map((entry) => [entry.date, entry.closed, entry.reason])).toEqual([
      ['2026-04-23', false, 'inactive'],
      ['2026-04-25', true, undefined],
    ])
    expect(first.complete).toBe(true)
    // The re-check was asked for 25/04 and returned the 23:30 meal.
    expect(reChecks(db)).toHaveLength(3)
    expect(db.progress(USER)).toMatchObject({ last_active_date: '2026-04-25' })
  })

  it('a first dinner on an earlier EMPTY date while the later day is being closed: nothing is finalized, the next call closes both in order', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup()
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-22', limits }
    let injected = false
    db.before = (operation) => {
      // After the day row of 04/10 was written, before its finalization.
      if (!injected && operation.kind === 'select' && operation.target === 'product_events') {
        injected = true
        dinner(db, '2026-10-02')
      }
    }

    const first = await closePastOpenDays(db.client, input)
    db.before = null

    expect(injected).toBe(true)
    expect(first.days.map((entry) => [entry.date, entry.closed, entry.reason])).toEqual([
      ['2026-10-04', false, 'earlier_date_changed'],
    ])
    expect(first.pendingDates).toEqual(['2026-10-04'])
    expect(first.complete).toBe(false)
    expect(first.streakReset).toBeNull()
    // The day row was written (as when a finalization loses a race); no RPC, no event.
    expect(db.writes.map((operation) => [operation.kind, operation.target])).toEqual([
      ['update', 'daily_snapshots'],
    ])
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: false })
    expect(db.progress(USER)).toMatchObject({ xp_total: 0, last_active_date: null })
    expect(db.events(USER)).toEqual([])

    const second = await closePastOpenDays(db.client, input)
    expect(second.days.map((entry) => [entry.date, entry.closed])).toEqual([
      ['2026-10-02', true],
      ['2026-10-04', true],
    ])
    expect(second.complete).toBe(true)
    expect(second.staleOpenDates).toEqual([])
    expect(db.progress(USER)).toMatchObject({ last_active_date: '2026-10-04' })
  })

  it('the same on an earlier open row that had water only', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup()
    db.tables.daily_snapshots.push(
      db.withDefaults('daily_snapshots', {
        user_id: USER,
        date: '2026-10-02',
        water_consumed_ml: 500,
      }),
    )
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-22', limits }
    let injected = false
    db.before = (operation) => {
      if (!injected && operation.kind === 'select' && operation.target === 'product_events') {
        injected = true
        dinner(db, '2026-10-02')
      }
    }
    const first = await closePastOpenDays(db.client, input)
    db.before = null
    expect(first.inactiveOpenDates).toEqual(['2026-10-02'])
    expect(first.days.map((entry) => [entry.date, entry.reason])).toEqual([
      ['2026-10-04', 'earlier_date_changed'],
    ])
    const second = await closePastOpenDays(db.client, input)
    expect(second.days.map((entry) => [entry.date, entry.closed])).toEqual([
      ['2026-10-02', true],
      ['2026-10-04', true],
    ])
  })

  it('a record on a date this call already closed, or on the date being closed, is not "earlier and open"', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup()
    day(db, '2026-10-01', { kcal: 1500, protein: 110 })
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-22', limits }
    let finalized = 0
    db.before = (operation) => {
      // Right after 01/10 was finalized: a late dinner on 01/10 (closed now).
      if (operation.kind === 'rpc' && operation.target === 'finalize_daily_close_atomic') {
        finalized += 1
      } else if (finalized === 1) {
        finalized = 99
        dinner(db, '2026-10-01')
      }
    }
    const result = await closePastOpenDays(db.client, input)
    db.before = null
    expect(result.days.map((entry) => [entry.date, entry.closed])).toEqual([
      ['2026-10-01', true],
      ['2026-10-04', true],
    ])
    expect(result.complete).toBe(true)
  })

  it('a failed re-check surfaces like any failed read, and nothing is finalized', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup(RECOMP, { current_streak: 1, last_active_date: '2026-10-01' })
    day(db, '2026-10-04', { kcal: 1500 })
    db.failWith = (operation) =>
      operation.target === 'workout_logs' && isReCheck(operation) ? 'statement timeout' : null
    await expect(
      closePastOpenDays(db.client, { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-22' }),
    ).rejects.toThrow('statement timeout')
    expect(db.operations.some((operation) => operation.kind === 'rpc')).toBe(false)
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: false })
  })

  it('a dry run never asks, and neither does closeLocalDay on one explicit date', async () => {
    const now = sp('2026-10-05', '08:00')
    vi.setSystemTime(now)
    const db = setup(RECOMP, { current_streak: 1, last_active_date: '2026-10-01' })
    day(db, '2026-10-04', { kcal: 1500 })
    await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now,
      from: '2026-09-22',
      dryRun: true,
    })
    expect(reChecks(db)).toEqual([])
    const single = await closeLocalDay(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      date: '2026-10-04',
      now,
    })
    expect(single.closed).toBe(true)
    expect(reChecks(db)).toEqual([])
  })
})

describe('closePastOpenDays — inactivity, once per call', () => {
  const input = {
    userId: USER,
    timezone: SAO_PAULO,
    now: sp('2026-10-05', '08:00'),
    from: '2026-09-22',
  }

  it('one day without activity is tolerated; the second zeroes the streak, once', async () => {
    const tolerated = setup(RECOMP, { current_streak: 4, last_active_date: '2026-10-03' })
    const kept = await closePastOpenDays(tolerated.client, input)
    expect(kept.streakReset).toBeNull()
    expect(tolerated.writes).toEqual([])

    const db = setup(RECOMP, {
      current_streak: 4,
      longest_streak: 6,
      last_active_date: '2026-10-02',
    })
    const first = await closePastOpenDays(db.client, input)
    expect(first.streakReset).toEqual({
      applied: true,
      previousStreak: 4,
      lastActiveDate: '2026-10-02',
      gapDays: 2,
    })
    expect(db.progress(USER)).toMatchObject({ current_streak: 0, longest_streak: 6 })
    expect(db.events(USER)).toHaveLength(1)
    expect(db.events(USER, 'streak.reset_inactive')[0]?.properties).toEqual({
      previous_streak: 4,
      last_active_date: '2026-10-02',
      gap_days: 2,
      yesterday: '2026-10-04',
    })
    // The update names the values that were read.
    expect(db.writes[0]).toMatchObject({ kind: 'update', target: 'user_progress' })
    expect(db.writes[0]?.filters).toEqual([
      { op: 'eq', column: 'user_id', value: USER },
      { op: 'eq', column: 'current_streak', value: 4 },
      { op: 'eq', column: 'last_active_date', value: '2026-10-02' },
    ])

    const writes = db.writes.length
    const second = await closePastOpenDays(db.client, input)
    expect(second.streakReset).toBeNull()
    expect(db.writes.length).toBe(writes)
  })

  it('the row changed between the read and the reset: no row is updated and no event is written', async () => {
    const db = setup(RECOMP, { current_streak: 4, last_active_date: '2026-10-02' })
    db.before = (operation) => {
      if (operation.kind === 'update' && operation.target === 'user_progress') {
        db.before = null
        const row = db.tables.user_progress[0]
        if (!row) throw new Error('fixture row missing')
        // Another request finalized 04/10 in between.
        row.current_streak = 1
        row.last_active_date = '2026-10-04'
      }
    }
    const result = await closePastOpenDays(db.client, input)
    expect(result.streakReset).toMatchObject({ applied: false })
    expect(db.progress(USER)).toMatchObject({ current_streak: 1, last_active_date: '2026-10-04' })
    expect(db.events(USER)).toEqual([])
  })

  it('while a date with data is still waiting (budget), the streak is not zeroed', async () => {
    vi.setSystemTime(sp('2026-10-06', '08:00'))
    const db = setup(RECOMP, { current_streak: 4, last_active_date: '2026-10-01' })
    day(db, '2026-10-02', { kcal: 1500 })
    day(db, '2026-10-03', { kcal: 1500 })
    const now = sp('2026-10-06', '08:00')
    const first = await closePastOpenDays(db.client, { ...input, now, limits: { maxDays: 1 } })
    expect(first.pendingDates).toEqual(['2026-10-03'])
    expect(first.streakReset).toBeNull()
    expect(db.progress(USER)).toMatchObject({ current_streak: 5 })

    // 03/10 continues the streak (6); only then do 04/10 and 05/10 count as two empty days.
    const second = await closePastOpenDays(db.client, { ...input, now, limits: { maxDays: 1 } })
    expect(second.days.map((entry) => entry.date)).toEqual(['2026-10-03'])
    expect(second.streakReset).toMatchObject({ applied: true, previousStreak: 6, gapDays: 2 })
    expect(db.progress(USER)).toMatchObject({ current_streak: 0, longest_streak: 6 })
  })
})

describe('closePastOpenDays — monotonic frontier', () => {
  it('an older open date with data is reported and left open; a later one is closed', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup(RECOMP, {
      current_streak: 3,
      longest_streak: 3,
      xp_total: 45,
      last_active_date: '2026-10-03',
    })
    // 01/10 was never closed and receives a meal only now.
    day(db, '2026-10-01', { kcal: 1500 })
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })

    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
    })
    expect(result.staleOpenDates).toEqual(['2026-10-01'])
    expect(result.days.map((entry) => entry.date)).toEqual(['2026-10-04'])
    expect(db.snapshot(USER, '2026-10-01')).toMatchObject({ day_closed: false, xp_earned: 0 })
    expect(db.progress(USER)).toMatchObject({
      current_streak: 4,
      xp_total: 60,
      last_active_date: '2026-10-04',
    })
  })
})

describe('dry run', () => {
  it('writes nothing and carries the simulated progress from one day to the next', async () => {
    vi.setSystemTime(sp('2026-10-05', '08:00'))
    const db = setup()
    day(db, '2026-10-02', { kcal: 1500, protein: 110 })
    day(db, '2026-10-03', { kcal: 1500, protein: 110 })
    day(db, '2026-10-04', { kcal: 1500, protein: 110 })
    const input = {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
    }

    const simulated = await closePastOpenDays(db.client, { ...input, dryRun: true })
    expect(db.writes).toEqual([])
    expect(simulated.days.map((entry) => entry.detail?.progress.currentStreak)).toEqual([1, 2, 3])
    expect(simulated.days.map((entry) => entry.detail?.progress.deficitBlock)).toEqual([
      576, 1152, 1728,
    ])
    expect(simulated.days.every((entry) => entry.dryRun && entry.closed)).toBe(true)

    // The real run then writes exactly what the simulation announced.
    const applied = await closePastOpenDays(db.client, input)
    expect(applied.days.map((entry) => entry.detail)).toEqual(
      simulated.days.map((entry) => entry.detail),
    )
    expect(db.progress(USER)).toMatchObject({
      current_streak: 3,
      deficit_block: 1728,
      xp_total: 45,
    })
  })

  it('announces the streak reset without applying it', async () => {
    const db = setup(RECOMP, { current_streak: 4, last_active_date: '2026-10-02' })
    const result = await closePastOpenDays(db.client, {
      userId: USER,
      timezone: SAO_PAULO,
      now: sp('2026-10-05', '08:00'),
      from: '2026-09-22',
      dryRun: true,
    })
    expect(result.streakReset).toEqual({
      applied: false,
      previousStreak: 4,
      lastActiveDate: '2026-10-02',
      gapDays: 2,
    })
    expect(db.writes).toEqual([])
  })
})
