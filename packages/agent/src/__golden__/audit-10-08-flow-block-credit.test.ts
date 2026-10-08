/**
 * C3: semana EXATA da audit10-04, agora com política explícita Flow.
 * Oráculos manuais: ganho598/manutenção587 no legado, crédito0 no Flow.
 * Recomposição mantém [576,676,-724,500,0,1065,832]. Nenhuma rede/banco real.
 *
 * > RC C3 — cenário bloco acumulado antes de entrar em ganho ou manutenção variante volta para a recomposição NÃO coberta nesta PR (pendência da audit 2026-10-07).
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import { closeLocalDay, closePastOpenDays } from '../day-close.js'
import { DayCloseMemoryDb, type MemoryRow } from '../testing/day-close-memory-db.js'

const USER = '0b9f6f0e-0000-4000-8000-00000000c310'
const ZONE = 'America/Sao_Paulo'
const POLICY = 'flow-recomposition-v1' as const
const DATES = [
  '2026-09-28',
  '2026-09-29',
  '2026-09-30',
  '2026-10-01',
  '2026-10-02',
  '2026-10-03',
  '2026-10-04',
]
type Protocol = 'recomposicao' | 'ganho_massa' | 'manutencao'
interface Day {
  kcal?: number
  protein?: number
  workout?: number
  message?: boolean
  xp: number
  credit: number
  block: number
}
const WEEKS: Record<Protocol, { target: number; xp: number; days: Day[] }> = {
  ganho_massa: {
    target: 2498,
    xp: 100,
    days: [
      { kcal: 2400, protein: 130, xp: 15, credit: 98, block: 98 },
      { kcal: 2600, protein: 140, workout: 300, xp: 20, credit: 198, block: 296 },
      { kcal: 3000, protein: 150, xp: 15, credit: -502, block: 0 },
      { kcal: 1000, protein: 60, xp: 10, credit: 0, block: 0 },
      { message: true, xp: 10, credit: 0, block: 0 },
      { kcal: 2498, protein: 125, workout: 400, xp: 20, credit: 400, block: 400 },
      { kcal: 2300, protein: 99, xp: 10, credit: 198, block: 598 },
    ],
  },
  manutencao: {
    target: 2379,
    xp: 105,
    days: [
      { kcal: 2379, protein: 100, xp: 15, credit: 0, block: 0 },
      { kcal: 2100, protein: 100, workout: 250, xp: 20, credit: 529, block: 529 },
      { kcal: 2700, protein: 80, xp: 10, credit: -321, block: 208 },
      { kcal: 1100, protein: 50, xp: 10, credit: 0, block: 208 },
      { workout: 300, xp: 15, credit: 0, block: 208 },
      { kcal: 2379, protein: 120, workout: 500, xp: 20, credit: 500, block: 708 },
      { kcal: 2500, protein: 110, xp: 15, credit: -121, block: 587 },
    ],
  },
  recomposicao: {
    target: 1576,
    xp: 105,
    days: [
      { kcal: 1500, protein: 110, xp: 15, credit: 576, block: 576 },
      { kcal: 1700, protein: 90, workout: 300, xp: 15, credit: 676, block: 1252 },
      { kcal: 2800, protein: 120, xp: 15, credit: -724, block: 528 },
      { kcal: 700, protein: 40, xp: 10, credit: 500, block: 1028 },
      { message: true, xp: 10, credit: 0, block: 1028 },
      { kcal: 1576, protein: 130, workout: 565, xp: 20, credit: 1065, block: 2093 },
      { kcal: 1809, protein: 100, workout: 565, xp: 20, credit: 832, block: 2925 },
    ],
  },
}
function instant(date: string, time = '12:00') {
  return new Date(`${date}T${time}:00-03:00`)
}
function account(protocol: string | null, progress?: MemoryRow) {
  const db = new DayCloseMemoryDb()
  db.addAccount({
    userId: USER,
    profile: {
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
    },
    progress,
  })
  return db
}
function register(db: DayCloseMemoryDb, date: string, day: Day, target: number) {
  if (day.kcal !== undefined)
    db.registerMeal({
      userId: USER,
      date,
      consumedAt: instant(date).toISOString(),
      kcal: day.kcal,
      proteinG: day.protein ?? 0,
      mealType: 'almoco',
      caloriesTarget: target,
      proteinTarget: 120,
    })
  if (day.workout !== undefined)
    db.registerWorkout({
      userId: USER,
      date,
      performedAt: instant(date, '18:00').toISOString(),
      kcal: day.workout,
      caloriesTarget: target,
      proteinTarget: 120,
    })
  if (day.message) db.addInboundMessage(USER, instant(date, '10:00').toISOString())
}
function input(date: string, policy: typeof POLICY | undefined = POLICY) {
  const tomorrow = new Date(`${date}T00:00:00.000Z`)
  tomorrow.setUTCDate(tomorrow.getUTCDate() + 1)
  return {
    userId: USER,
    timezone: ZONE,
    date,
    now: instant(tomorrow.toISOString().slice(0, 10), '08:00'),
    block7700Policy: policy,
  }
}
beforeEach(() => {
  vi.useFakeTimers()
  clearCalcConfigCache()
})
afterEach(() => {
  vi.useRealTimers()
})

describe.each(['00:30', '08:00'])('semana28/09–04/10 fechada às%s', (time) => {
  it.each([
    'ganho_massa',
    'manutencao',
    'recomposicao',
  ] as const)('%s mantém XP/seqüência e aplica o gate Flow em cada dia', async (protocol) => {
    const fixture = WEEKS[protocol]
    const db = account(protocol)
    let xp = 0
    for (const [index, day] of fixture.days.entries()) {
      const date = DATES[index] as string
      vi.setSystemTime(instant(date))
      register(db, date, day, fixture.target)
      const next = input(date)
      next.now = instant(next.now.toISOString().slice(0, 10), time)
      vi.setSystemTime(next.now)
      const result = await closePastOpenDays(db.client, { ...next, from: '2026-09-01' })
      xp += day.xp
      expect(result.days).toHaveLength(1)
      expect(result.days[0]).toMatchObject({
        closed: true,
        late: time === '08:00',
        detail: {
          caloriesConsumed: day.kcal ?? 0,
          exerciseCalories: day.workout ?? 0,
          caloriesTarget: fixture.target,
          proteinTarget: 120,
          dayStatus: 'complete',
          xpEarned: day.xp,
          blockCredit: protocol === 'recomposicao' ? day.credit : 0,
          progress: {
            xpTotal: xp,
            currentStreak: index + 1,
            deficitBlock: protocol === 'recomposicao' ? day.block : 0,
            blocksCompleted: 0,
          },
        },
      })
      expect(db.snapshot(USER, date)).toMatchObject({
        day_closed: true,
        day_status: 'complete',
        calories_consumed: day.kcal ?? 0,
        calories_target: fixture.target,
        exercise_calories: day.workout ?? 0,
        xp_earned: day.xp,
        current_protocol: protocol,
      })
    }
    expect(db.progress(USER)).toMatchObject({
      xp_total: fixture.xp,
      level: 2,
      current_streak: 7,
      longest_streak: 7,
      deficit_block: protocol === 'recomposicao' ? 2925 : 0,
      blocks_completed: 0,
      badges_earned: ['Primeira Semana'],
      last_active_date: '2026-10-04',
      next_reevaluation: null,
    })
    expect(db.events(USER, 'daily_closer.completed')).toHaveLength(7)
    expect(db.events(USER, 'bloco7700.block_completed')).toEqual([])
    expect(db.events(USER, 'badge.earned').map((e) => e.properties)).toEqual([
      { badges: ['Primeira Semana'], snapshot_date: '2026-10-04' },
    ])
    if (protocol !== 'recomposicao')
      expect(
        db.tables.product_events.filter((e) => String(e.event).startsWith('bloco7700.')),
      ).toEqual([])
  })
})

describe.each(['ganho_massa', 'manutencao'] as const)('saldo antigo em%s', (protocol) => {
  it.each([
    [7600, 0, [], 2600, 300],
    [300, 1, [], 2600, 300],
    [300, 1, ['Primeiro Bloco'], 3000, 0],
  ] as const)('preserva%s/%s e medalhas existentes; nenhum crédito/débito novo', async (block, completed, badges, kcal, workout) => {
    const db = account(protocol, {
      deficit_block: block,
      blocks_completed: completed,
      badges_earned: [...badges],
    })
    register(
      db,
      '2026-10-04',
      { kcal, protein: 140, workout, xp: 20, credit: 0, block },
      WEEKS[protocol].target,
    )
    const result = await closeLocalDay(db.client, input('2026-10-04'))
    expect(result.detail).toMatchObject({
      blockCredit: 0,
      newBadges: [],
      progress: { deficitBlock: block, blocksCompleted: completed, badgesEarned: [...badges] },
    })
    expect(db.events(USER, 'bloco7700.block_completed')).toEqual([])
    expect(db.events(USER, 'badge.earned')).toEqual([])
    const rpc = db.operations.find(
      (o) => o.kind === 'rpc' && o.target === 'finalize_daily_close_atomic',
    )
    expect(Object.keys(rpc?.params ?? {})).toHaveLength(12)
    expect(rpc?.params).toMatchObject({
      p_blocks_completed: completed,
      p_deficit_block: block,
      p_badges_earned: [...badges],
    })
  })
})

it.each([
  null,
  'desconhecido',
  'RECOMPOSICAO',
])('protocolo%s não autoriza bloco sem recomposição exata', async (protocol) => {
  const db = account(protocol, { deficit_block: 7600, blocks_completed: 0 })
  register(db, '2026-10-04', { kcal: 1500, protein: 110, xp: 15, credit: 0, block: 7600 }, 1576)
  const result = await closeLocalDay(db.client, input('2026-10-04'))
  expect(result.detail).toMatchObject({
    blockCredit: 0,
    xpEarned: 15,
    progress: { deficitBlock: 7600, blocksCompleted: 0, currentStreak: 1 },
  })
})

it('recomposição cruza7600+832, ganha medalha uma vez e repete sem escrever', async () => {
  const db = account('recomposicao', { deficit_block: 7600, blocks_completed: 0 })
  register(db, '2026-10-04', WEEKS.recomposicao.days[6] as Day, 1576)
  const first = await closeLocalDay(db.client, input('2026-10-04'))
  expect(first.detail).toMatchObject({
    blockCredit: 832,
    newBadges: ['Primeiro Bloco'],
    progress: { deficitBlock: 732, blocksCompleted: 1 },
  })
  const writes = db.writes.length
  expect(await closeLocalDay(db.client, input('2026-10-04'))).toMatchObject({
    closed: false,
    reason: 'already_closed',
  })
  expect(db.writes).toHaveLength(writes)
  expect(db.events(USER, 'bloco7700.block_completed')).toHaveLength(1)
})

it('ontem após troca08:01 para ganho fecha08:02 com meta1576 preservada e crédito0', async () => {
  const db = account('recomposicao', { deficit_block: 1252, blocks_completed: 0 })
  register(db, '2026-10-04', { kcal: 1500, protein: 110, xp: 15, credit: 576, block: 1828 }, 1576)
  vi.setSystemTime(instant('2026-10-05', '08:01'))
  const profile = db.tables.user_profiles[0] as MemoryRow
  profile.current_protocol = 'ganho_massa'
  const result = await closeLocalDay(db.client, {
    ...input('2026-10-04'),
    now: instant('2026-10-05', '08:02'),
  })
  expect(result.detail).toMatchObject({
    storedCaloriesTarget: 1576,
    caloriesTarget: 1576,
    blockCredit: 0,
    progress: { deficitBlock: 1252, blocksCompleted: 0 },
  })
  expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
    current_protocol: 'ganho_massa',
    calories_target: 1576,
    day_closed: true,
  })
})

it('sweep simulado e aplicado propagam política em três dias sem zerar saldo antigo', async () => {
  const db = account('manutencao', { deficit_block: 300, blocks_completed: 1 })
  for (const date of ['2026-10-02', '2026-10-03', '2026-10-04'])
    register(
      db,
      date,
      { kcal: 2100, protein: 100, workout: 250, xp: 20, credit: 529, block: 0 },
      2379,
    )
  const request = { ...input('2026-10-04'), from: '2026-10-02' }
  const dry = await closePastOpenDays(db.client, { ...request, dryRun: true })
  expect(db.writes).toEqual([])
  expect(dry.days.map((d) => d.detail?.blockCredit)).toEqual([0, 0, 0])
  const applied = await closePastOpenDays(db.client, request)
  expect(applied.days.map((d) => d.detail?.progress)).toEqual(
    dry.days.map((d) => d.detail?.progress),
  )
  expect(db.progress(USER)).toMatchObject({
    deficit_block: 300,
    blocks_completed: 1,
    xp_total: 60,
    current_streak: 3,
    badges_earned: [],
  })
})

it('dias fechados antes da política não são reabertos nem recalculados', async () => {
  const db = account('ganho_massa')
  register(db, '2026-10-04', WEEKS.ganho_massa.days[1] as Day, 2498)
  const legacy = { ...input('2026-10-04'), block7700Policy: undefined }
  expect((await closeLocalDay(db.client, legacy)).detail?.blockCredit).toBe(198)
  const progress = structuredClone(db.progress(USER))
  const writes = db.writes.length
  expect(await closeLocalDay(db.client, input('2026-10-04'))).toMatchObject({
    reason: 'already_closed',
  })
  expect(db.progress(USER)).toEqual(progress)
  expect(db.writes).toHaveLength(writes)
})

it('duas finalizações da mesma data aplicam XP uma vez com saldo histórico intacto', async () => {
  const db = account('ganho_massa', { deficit_block: 7600, blocks_completed: 0 })
  register(db, '2026-10-04', WEEKS.ganho_massa.days[1] as Day, 2498)
  let entered = () => {}
  let release = () => {}
  const reached = new Promise<void>((resolve) => {
    entered = resolve
  })
  const held = new Promise<void>((resolve) => {
    release = resolve
  })
  const slow = db.session(async (operation) => {
    if (operation.kind === 'rpc' && operation.target === 'finalize_daily_close_atomic') {
      entered()
      await held
    }
  })
  const loser = closeLocalDay(slow, input('2026-10-04'))
  await reached
  expect((await closeLocalDay(db.client, input('2026-10-04'))).closed).toBe(true)
  release()
  expect(await loser).toMatchObject({ closed: false, reason: 'closed_concurrently' })
  expect(db.progress(USER)).toMatchObject({
    deficit_block: 7600,
    blocks_completed: 0,
    xp_total: 20,
    current_streak: 1,
    badges_earned: [],
  })
  expect(db.events(USER, 'daily_closer.completed')).toHaveLength(1)
  expect(db.events(USER, 'badge.earned')).toEqual([])
})
