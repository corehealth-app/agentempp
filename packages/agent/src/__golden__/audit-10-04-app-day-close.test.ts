/**
 * Audit 2026-10-04 — the day never closes for an app account on the test
 * environment (docs/CALCULO-MPP.md §3a).
 *
 * THE REPORT. On staging the worker serves media processing only, by design,
 * so that no WhatsApp reminder can leave it. Nothing there ever closed a day:
 * read on 2026-10-04 (read-only, counts and day totals, no identifier), 13 day
 * rows and 0 closed, 11 progress rows all zero. After a week of real use the
 * app still showed "Sequência: 0 dias", 0 XP, nível 1, no medal and the 7.700
 * block at 0, and the Flow's weekly summary saw no days.
 *
 * WHAT WAS BUILT. `closeLocalDay` / `closePastOpenDays`
 * (packages/agent/src/day-close.ts): the production closer's script for one
 * explicit local date, calling the SAME functions and the SAME RPC, and a
 * sweep that closes the past open days of one account in order. Used by the
 * mobile API behind a switch that is off by default
 * (apps/admin/src/lib/mobile-api/day-close-on-request.ts) and by the operator
 * script (scripts/close-open-days.ts). The production closer is untouched.
 *
 * REVIEW OF 2026-10-05 (two adversarial lenses), both HIGH findings reproduced
 * below with the reviewers' own inputs:
 *  - the sweep went on to the later dates after one date answered
 *    `changed_concurrently`; the later day closed, the frontier passed the
 *    earlier one and it never closed again. Now the sweep stops at that date
 *    (blocks "a retroactive dinner confirmed on the MIDDLE day" and "GET
 *    /today and GET /progress at the same time");
 *  - yesterday was closed at any hour with the profile of that moment, so a
 *    weigh-in of this morning rewrote yesterday's stored target. Now a close
 *    of yesterday at local hour 5 or later is a late close and keeps the
 *    stored target (block "yesterday closed after 05:00 local").
 *
 * EVERY NUMBER BELOW IS COMPUTED BY THE REAL FUNCTIONS (`loadDailyTargets`,
 * `calcDailyXP`, `creditDayToBloco`, `computeProgress`,
 * `resolveClosedDayStatus`, through `closePastOpenDays`) and checked against a
 * hand calculation written next to it. The database is the in-memory one of
 * `testing/day-close-memory-db.ts`, which emulates the generated column
 * `daily_balance` and `finalize_daily_close_atomic` from the migrations.
 *
 * READ FROM STAGING on 2026-10-04 (last block): for the three accounts that
 * have anything to close, per local date, the stored targets and the day
 * totals (kcal, protein, exercise, number of workouts, inbound messages); the
 * protocol of each account; `calc.xp_rules` (base 10, treino +5, proteína
 * ≥ 100 g +5 — equal to the code default). ASSUMED, declared: one meal row
 * per day carrying the day total (the real days have 2 to 18 rows; the close
 * sums them), meal and workout times, the user ids and every profile field
 * other than the protocol (none was read; no number asserted in that block
 * depends on them, because every day in it is a late close with a stored
 * target or has no meal).
 *
 * Fixture person of the synthetic blocks: homem, 80 kg, 180 cm, born
 * 1986-01-01 (40 years old), atividade leve.
 *   BMR (Mifflin) = 10×80 + 6,25×180 − 5×40 + 5 = 1730          (docs §1)
 *   recomposição, déficit 500: 1730 × 1,2 − 500        = 1576
 *   ganho de massa:            1730 × 1,375 × 1,05     = 2497,69 → 2498
 *   manutenção:                1730 × 1,375            = 2378,75 → 2379
 *   proteína: recomposição 80 × 1,5 = 120 (§1b); the others 80 × 1,5 = 120
 *   (code default of `protein_factors`).
 *   XP (legacy rule, the one stored on staging): 10 + 5 with a workout + 5
 *   with protein ≥ 100 g.
 *
 * Declared pendencies (CLAUDE.md criterion 2); every line is in
 * docs/CALCULO-MPP.md §3a, identical (the last test of this file compares).
 *
 * > RC F — cenário gráfico "Bloco 7.700 acumulado" do app (lê `daily_snapshots.deficit_accumulated`, coluna que o fechamento não grava) NÃO coberto nesta PR (pendência da audit 2026-10-04). Continua em zero com os dias fechados, em qualquer ambiente.
 * > RC F — cenário crédito do bloco em ganho de massa e manutenção (o fechamento credita meta + exercício − consumido; o cliente escreveu em 08/05/2026 que nesses protocolos o bloco de 7.700 "é substituido pelo bloco acumaldo de Kcal em 14 dias") NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado, e agora visível no app de avaliação: comer abaixo da meta enche o bloco. Travado abaixo como está.
 * > RC F — cenário agenda de reavaliação de 14 dias (`advance_reevaluation_schedule`) no caminho sob demanda NÃO coberto nesta PR (pendência da audit 2026-10-04). Desligada por padrão: o contexto de reavaliação do Flow nunca foi exercitado no app. `next_reevaluation` fica nulo em conta fechada só por este caminho.
 * > RC F — cenário convergência dos dois roteiros (o worker de produção passar a chamar `closeLocalDay`) NÃO coberto nesta PR (pendência da audit 2026-10-04). `daily-closer.ts` não foi tocado; a igualdade entre os dois é travada pelo teste de paridade.
 * > RC F — cenário dia antigo aberto que recebe registro depois de um dia posterior já ter fechado NÃO coberto nesta PR (pendência da audit 2026-10-04). Fica aberto, como em produção: não entra em sequência, XP nem bloco; a varredura só o relata.
 * > RC F — cenário refeição ou treino registrado num dia JÁ fechado NÃO coberto nesta PR (pendência da audit 2026-10-04). Igual à produção: o dia não é recreditado e `calories_consumed` passa a divergir do que foi creditado.
 * > RC F — cenário dia só com água, peso, suplemento ou medicamento (sem refeição, treino nem mensagem recebida) NÃO coberto nesta PR (pendência da audit 2026-10-04). Conta como dia inativo, como em produção: a linha fica aberta e a sequência quebra.
 * > RC F — cenário status `incomplete_no_response` num fechamento atrasado (o padrão de refeições é o dos 14 dias anteriores a AGORA, não à data fechada) NÃO coberto nesta PR (pendência da audit 2026-10-04). Só alcança dia com lembrete de lacuna gravado, que conta do app em staging não tem.
 * > RC F — cenário fechamento atrasado (data anterior a ontem, ou ontem a partir das 05:00 locais) depois de troca de protocolo ou de `deficit_level` NÃO coberto nesta PR (pendência da audit 2026-10-04). A meta gravada no dia é mantida; o déficit programado do crédito e o `current_protocol` gravado são os do perfil na hora do fechamento. Travado abaixo como está: recomposição trocada para ganho de massa às 08:01, ontem (1500 kcal, meta gravada 1576) fecha às 08:02 com meta 1576, protocolo `ganho_massa` e crédito 76; o fechador de produção teria gravado `recomposicao` e 576.
 * > RC F — cenário perfil alterado no PRÓPRIO dia depois do primeiro registro (pesagem ao meio-dia) e dia fechado atrasado NÃO coberto nesta PR (pendência da audit 2026-10-04). O fechamento atrasado mantém a meta gravada na linha, que é a do primeiro registro do dia (a pesagem não regrava a linha); o fechador de produção, às 00:30, regravaria com a meta do perfil. Travado abaixo como está: 80 → 82 kg às 13:00 de ontem, 1500 kcal: fechado às 08:00 fica meta 1576 e crédito 576; fechado às 00:30 fica meta 1600 e crédito 600.
 * > RC F — cenário duas varreduras simultâneas que enxergam datas diferentes (um registro retroativo entra entre as duas leituras) NÃO coberto nesta PR (pendência da audit 2026-10-04). A finalização grava valores absolutos: o progresso de um dos dois dias pode ser sobrescrito. Resolver exige a RPC conferir a versão anterior (migration).
 * > RC F — cenário registro confirmado entre a gravação da linha do dia e a finalização NÃO coberto nesta PR (pendência da audit 2026-10-04). Mesma janela da produção, com uma ida ao banco de largura.
 * > RC F — cenário eventos de telemetria intermediários (`streak.reset_inactive` de cada intervalo antigo e `daily_closer.skipped`) NÃO coberto nesta PR (pendência da audit 2026-10-04). O caminho sob demanda grava um zeramento por varredura e nunca grava "skipped"; o `user_progress` final é o mesmo.
 * > RC F — cenário fechador de PRODUÇÃO em fuso de meia hora e em dia de troca de horário de verão NÃO coberto nesta PR (pendência da audit 2026-10-04). Não foi tocado: usa "agora − 24 h" e ticks no minuto 30 UTC. O caminho sob demanda usa a data do calendário e espera 30 min depois da meia-noite local (travado abaixo em America/Sao_Paulo e Asia/Kolkata), com a exceção da linha seguinte.
 * > RC F — cenário fuso de offset positivo cuja troca de horário de verão cai à meia-noite (Africa/Cairo em 24/04/2026, Asia/Beirut em 29/03/2026) NÃO coberto nesta PR (pendência da audit 2026-10-04). `localMidnightUtc` (auxiliar antigo, usado também pelo fechador de produção e não tocado) devolve o início desse dia uma hora adiantado: a última hora da véspera é contada no dia da troca e, nesse dia, ontem fica fechável já no primeiro instante, sem a espera de 30 min. Hoje nunca fecha. Travado abaixo como está.
 * > RC F — cenário botão "Fechar dia" do painel admin (marca o dia como fechado sem aplicar progresso) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado. Um dia fechado assim vira fronteira: os dias abertos anteriores a ele não fecham mais.
 * > RC F — cenário banco real (cliente supabase-js contra o Postgres de staging: filtro por `updated_at`, `upsert` com `ignoreDuplicates`, a RPC e a coluna gerada de verdade) NÃO coberto nesta PR (pendência da audit 2026-10-04). Toda a suíte usa banco em memória; nada foi executado contra banco algum. O cliente supabase-js real foi conferido à mão em 2026-10-05 com `fetch` falso, sem rede e sem banco: a escrita da linha existente sai como `PATCH daily_snapshots?id=eq…&day_closed=eq.false&updated_at=eq…`, a criação como `upsert` com `resolution=ignore-duplicates`, e zero linhas devolvidas encerram a tentativa sem finalizar.
 * > RC F — cenário dias abertos de staging fechados de fato NÃO coberto nesta PR (pendência da audit 2026-10-04). Nenhuma escrita foi feita e a simulação não foi rodada contra o banco; os números esperados vêm de SELECTs de 2026-10-04 e do último bloco deste arquivo.
 * > RC F — cenário app no aparelho (Progresso, bloco e resumo semanal do Flow depois de um fechamento) NÃO coberto nesta PR (pendência da audit 2026-10-04). Nada foi executado no aparelho, no simulador nem no BFF publicado.
 */
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache, loadCalcConfig } from '../calc-config-loader.js'
import { loadDailyTargets } from '../calc-targets.js'
import { closePastOpenDays, latestClosableLocalDate } from '../day-close.js'
import {
  DayCloseMemoryDb,
  type MemoryOperation,
  type MemoryRow,
} from '../testing/day-close-memory-db.js'
import { getLocalDateString, getLocalDayUtcBounds } from '../timezone-utils.js'

const USER = '0b9f6f0e-0000-4000-8000-00000000f104'
const SAO_PAULO = 'America/Sao_Paulo'

type Protocol = 'recomposicao' | 'ganho_massa' | 'manutencao'

const TARGET: Record<Protocol, number> = {
  recomposicao: 1576,
  ganho_massa: 2498,
  manutencao: 2379,
}
const PROTEIN_TARGET = 120

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

/** A wall-clock instant in America/Sao_Paulo (UTC−3, no daylight saving since 2019). */
function sp(date: string, time: string): Date {
  return new Date(`${date}T${time}:00-03:00`)
}

function nextDay(date: string): string {
  const parsed = new Date(`${date}T00:00:00.000Z`)
  parsed.setUTCDate(parsed.getUTCDate() + 1)
  return parsed.toISOString().slice(0, 10)
}

interface DayInput {
  kcal?: number
  protein?: number
  workout?: number
  message?: boolean
  /** Target stored on the day row at registration; default = the protocol's. */
  storedTarget?: number
  storedProtein?: number
}

function register(db: DayCloseMemoryDb, protocol: Protocol, date: string, input: DayInput) {
  const caloriesTarget = input.storedTarget ?? TARGET[protocol]
  const proteinTarget = input.storedProtein ?? PROTEIN_TARGET
  if (input.kcal !== undefined) {
    db.registerMeal({
      userId: USER,
      date,
      consumedAt: sp(date, '12:00').toISOString(),
      kcal: input.kcal,
      proteinG: input.protein ?? 0,
      mealType: 'almoco',
      caloriesTarget,
      proteinTarget,
    })
  }
  if (input.workout !== undefined) {
    db.registerWorkout({
      userId: USER,
      date,
      performedAt: sp(date, '18:00').toISOString(),
      kcal: input.workout,
      caloriesTarget,
      proteinTarget,
    })
  }
  if (input.message) db.addInboundMessage(USER, sp(date, '10:00').toISOString())
}

function account(protocol: Protocol, progress?: MemoryRow) {
  const db = new DayCloseMemoryDb()
  db.addAccount({ userId: USER, profile: profile(protocol), progress })
  return db
}

function sweep(db: DayCloseMemoryDb, now: Date, extra: { maxDays?: number } = {}) {
  vi.setSystemTime(now)
  return closePastOpenDays(db.client, {
    userId: USER,
    timezone: SAO_PAULO,
    now,
    from: '2026-09-01',
    ...(extra.maxDays ? { limits: { maxDays: extra.maxDays, maxMs: 4000 } } : {}),
  })
}

beforeEach(() => {
  vi.useFakeTimers()
  clearCalcConfigCache()
})

afterEach(() => {
  vi.useRealTimers()
})

// ───────────────────────────────────────────────────────────────────────────
// 1. A week, closed day by day (the sweep of each following morning)
// ───────────────────────────────────────────────────────────────────────────

interface WeekDay extends DayInput {
  date: string
  /** Expected: XP of the day, block credit of the day, then the running state. */
  xp: number
  credit: number
  block: number
  status?: string
}

const WEEK_DATES = [
  '2026-09-28',
  '2026-09-29',
  '2026-09-30',
  '2026-10-01',
  '2026-10-02',
  '2026-10-03',
  '2026-10-04',
] as const

function week(rows: Array<Omit<WeekDay, 'date'>>): WeekDay[] {
  return rows.map((row, index) => ({ ...row, date: WEEK_DATES[index] as string }))
}

/**
 * RECOMPOSIÇÃO — meta 1576, déficit programado 500 (docs §3:
 * crédito = déficit programado − daily_balance; daily_balance = consumido −
 * meta − exercício, §2b).
 *
 * Worked day, 04/10 — the client's own example of 20/05/2026 ("500 − 233 =
 * 267 + 565 = 832", docs §2b): consumed 1809 = 233 over 1576; workout 565.
 *   daily_balance = 1809 − 1576 − 565 = −332
 *   crédito       = 500 − (−332)      = 832
 *   XP            = 10 + 5 (treino) + 5 (100 g ≥ 100) = 20
 */
const RECOMPOSICAO_WEEK = week([
  // 1500 − 1576 = −76 → 500 + 76 = 576
  { kcal: 1500, protein: 110, xp: 15, credit: 576, block: 576 },
  // 1700 − 1576 − 300 = −176 → 676 (protein 90 < 100: no bonus)
  { kcal: 1700, protein: 90, workout: 300, xp: 15, credit: 676, block: 1252 },
  // 2800 − 1576 = +1224 → 500 − 1224 = −724 (a bad day takes from the block)
  { kcal: 2800, protein: 120, xp: 15, credit: -724, block: 528 },
  // 700 < 0,5 × 1576 = 788 → under-registration: only the programmed 500
  { kcal: 700, protein: 40, xp: 10, credit: 500, block: 1028 },
  // only a message in the Flow: the day counts for the streak, credit 0
  { message: true, xp: 10, credit: 0, block: 1028 },
  // 1576 − 1576 − 565 = −565 → 1065
  { kcal: 1576, protein: 130, workout: 565, xp: 20, credit: 1065, block: 2093 },
  // the worked day above
  { kcal: 1809, protein: 100, workout: 565, xp: 20, credit: 832, block: 2925 },
])

/**
 * GANHO DE MASSA — meta 2498, no programmed deficit, so the close credits
 * −daily_balance = meta + exercício − consumido (docs §3, "Fora da
 * recomposição"; declared pending, RC F above — locked as it is).
 *
 * Worked day, 29/09: consumed 2600, workout 300.
 *   daily_balance = 2600 − 2498 − 300 = −198
 *   crédito       = 0 − (−198)        = 198
 *   XP            = 10 + 5 (treino) + 5 (140 g ≥ 100) = 20
 */
const GANHO_WEEK = week([
  // 2498 − 2400 = 98
  { kcal: 2400, protein: 130, xp: 15, credit: 98, block: 98 },
  // the worked day above
  { kcal: 2600, protein: 140, workout: 300, xp: 20, credit: 198, block: 296 },
  // 2498 − 3000 = −502 → 296 − 502 < 0 → the block floors at 0
  { kcal: 3000, protein: 150, xp: 15, credit: -502, block: 0 },
  // 1000 < 1249 → under-registration: programmed deficit is 0 here
  { kcal: 1000, protein: 60, xp: 10, credit: 0, block: 0 },
  { message: true, xp: 10, credit: 0, block: 0 },
  // 2498 + 400 − 2498 = 400
  { kcal: 2498, protein: 125, workout: 400, xp: 20, credit: 400, block: 400 },
  // 2498 − 2300 = 198 (protein 99 < 100)
  { kcal: 2300, protein: 99, xp: 10, credit: 198, block: 598 },
])

/**
 * MANUTENÇÃO — meta 2379, same credit expression as ganho de massa.
 *
 * Worked day, 29/09: consumed 2100, workout 250.
 *   daily_balance = 2100 − 2379 − 250 = −529
 *   crédito       = 0 − (−529)        = 529
 *   XP            = 10 + 5 (treino) + 5 (100 g ≥ 100) = 20
 */
const MANUTENCAO_WEEK = week([
  // on target: 0
  { kcal: 2379, protein: 100, xp: 15, credit: 0, block: 0 },
  // the worked day above
  { kcal: 2100, protein: 100, workout: 250, xp: 20, credit: 529, block: 529 },
  // 2379 − 2700 = −321
  { kcal: 2700, protein: 80, xp: 10, credit: -321, block: 208 },
  // 1100 < 1189,5 → under-registration → 0
  { kcal: 1100, protein: 50, xp: 10, credit: 0, block: 208 },
  // a workout and no meal: activity, but 0 kcal < 50% of the target → 0
  { workout: 300, xp: 15, credit: 0, block: 208 },
  // 2379 + 500 − 2379 = 500
  { kcal: 2379, protein: 120, workout: 500, xp: 20, credit: 500, block: 708 },
  // 2379 − 2500 = −121
  { kcal: 2500, protein: 110, xp: 15, credit: -121, block: 587 },
])

describe.each([
  // Inside the production closer's window (local hours 0 to 4): yesterday is
  // closed exactly as production closes it, with the profile's target.
  ['00:30', false],
  // The first request of the morning, where production never closes: a late
  // close, which keeps the target stored on the day row. The same numbers
  // here, because the profile did not change during the week.
  ['08:00', true],
] as const)('a week of an app account, each day closed at %s of the following day (late: %s)', (closingTime, late) => {
  it.each([
    ['recomposicao', RECOMPOSICAO_WEEK, 105],
    ['ganho_massa', GANHO_WEEK, 100],
    ['manutencao', MANUTENCAO_WEEK, 105],
  ] as const)('%s', async (protocol, days, totalXp) => {
    const db = account(protocol)
    let xpTotal = 0

    for (const [index, day] of days.entries()) {
      vi.setSystemTime(sp(day.date, '12:00'))
      register(db, protocol, day.date, day)

      const result = await sweep(db, sp(nextDay(day.date), closingTime))

      xpTotal += day.xp
      const streak = index + 1
      expect(result.days, day.date).toHaveLength(1)
      expect(result.days[0], day.date).toMatchObject({
        date: day.date,
        closed: true,
        late,
        detail: {
          caloriesConsumed: day.kcal ?? 0,
          exerciseCalories: day.workout ?? 0,
          caloriesTarget: TARGET[protocol],
          proteinTarget: PROTEIN_TARGET,
          dayStatus: 'complete',
          xpEarned: day.xp,
          blockCredit: day.credit,
          newBadges: streak === 7 ? ['Primeira Semana'] : [],
          progress: {
            xpTotal,
            level: xpTotal >= 100 ? 2 : 1,
            currentStreak: streak,
            longestStreak: streak,
            blocksCompleted: 0,
            deficitBlock: day.block,
            lastActiveDate: day.date,
          },
        },
      })
      expect(db.snapshot(USER, day.date), day.date).toMatchObject({
        day_closed: true,
        day_status: 'complete',
        calories_consumed: day.kcal ?? 0,
        calories_target: TARGET[protocol],
        exercise_calories: day.workout ?? 0,
        xp_earned: day.xp,
        current_protocol: protocol,
      })
    }

    expect(db.progress(USER)).toMatchObject({
      xp_total: totalXp,
      level: 2,
      current_streak: 7,
      longest_streak: 7,
      blocks_completed: 0,
      deficit_block: days[6]?.block,
      badges_earned: ['Primeira Semana'],
      last_active_date: '2026-10-04',
      // The on-demand path does not advance the reassessment schedule.
      next_reevaluation: null,
    })
    expect(db.events(USER, 'daily_closer.completed')).toHaveLength(7)
    expect(db.events(USER, 'badge.earned').map((event) => event.properties)).toEqual([
      { badges: ['Primeira Semana'], snapshot_date: '2026-10-04' },
    ])
    expect(db.events(USER, 'daily_closer.skipped')).toEqual([])
    expect(db.events(USER, 'reevaluation.due')).toEqual([])
  })
})

// ───────────────────────────────────────────────────────────────────────────
// 2. Days opened late
// ───────────────────────────────────────────────────────────────────────────

describe('three days never closed, closed by one sweep', () => {
  it('in order, with streak 1 → 2 → 3, each keeping the target stored on its row', async () => {
    const db = account('recomposicao')
    // The profile gave 1700 when these days were registered; it gives 1576 now.
    for (const date of ['2026-10-01', '2026-10-02', '2026-10-03']) {
      vi.setSystemTime(sp(date, '12:00'))
      register(db, 'recomposicao', date, { kcal: 1500, protein: 110, storedTarget: 1700 })
    }

    // First request on the 5th: yesterday (the 4th) has nothing; the three
    // days are all before yesterday.
    const result = await sweep(db, sp('2026-10-05', '08:00'))

    // Each: daily_balance = 1500 − 1700 = −200 → crédito 500 + 200 = 700
    // (rewritten with today's 1576 it would be 576).
    expect(
      result.days.map((day) => [
        day.date,
        day.late,
        day.detail?.storedCaloriesTarget,
        day.detail?.caloriesTarget,
        day.detail?.blockCredit,
        day.detail?.progress.currentStreak,
        day.detail?.progress.deficitBlock,
      ]),
    ).toEqual([
      ['2026-10-01', true, 1700, 1700, 700, 1, 700],
      ['2026-10-02', true, 1700, 1700, 700, 2, 1400],
      ['2026-10-03', true, 1700, 1700, 700, 3, 2100],
    ])
    expect(result.complete).toBe(true)
    // One empty day (the 4th) is tolerated.
    expect(result.streakReset).toBeNull()
    expect(db.progress(USER)).toMatchObject({
      xp_total: 45,
      current_streak: 3,
      longest_streak: 3,
      deficit_block: 2100,
      last_active_date: '2026-10-03',
    })
    for (const date of ['2026-10-01', '2026-10-02', '2026-10-03']) {
      expect(db.snapshot(USER, date)).toMatchObject({
        day_closed: true,
        calories_target: 1700,
        daily_balance: -200,
      })
    }
  })
})

describe('a retroactive meal on an old day that never closed', () => {
  it('changes neither the streak nor last_active_date; the old day stays open and is reported', async () => {
    const db = account('recomposicao')
    // D1–D6 active, D7 (27/09) without any record, D8–D10 active.
    const active = [
      '2026-09-21',
      '2026-09-22',
      '2026-09-23',
      '2026-09-24',
      '2026-09-25',
      '2026-09-26',
      '2026-09-28',
      '2026-09-29',
      '2026-09-30',
    ]
    for (const date of active) {
      vi.setSystemTime(sp(date, '12:00'))
      register(db, 'recomposicao', date, { kcal: 1500, protein: 110 })
      await sweep(db, sp(nextDay(date), '08:00'))
    }
    expect(db.progress(USER)).toMatchObject({
      current_streak: 3,
      longest_streak: 6,
      last_active_date: '2026-09-30',
      xp_total: 135,
    })

    // D11 (01/10): an ordinary day, and the person also logs the forgotten
    // lunch of the 27th.
    vi.setSystemTime(sp('2026-10-01', '12:00'))
    register(db, 'recomposicao', '2026-10-01', { kcal: 1500, protein: 110 })
    register(db, 'recomposicao', '2026-09-27', { kcal: 1500, protein: 110 })

    const result = await sweep(db, sp('2026-10-02', '08:00'))

    expect(result.staleOpenDates).toEqual(['2026-09-27'])
    expect(result.days.map((day) => [day.date, day.closed])).toEqual([['2026-10-01', true]])
    // 30/09 → 01/10 continues: 4. Closing the 27th first would have made it 1.
    expect(db.progress(USER)).toMatchObject({
      current_streak: 4,
      longest_streak: 6,
      last_active_date: '2026-10-01',
      xp_total: 150,
    })
    expect(db.snapshot(USER, '2026-09-27')).toMatchObject({ day_closed: false, xp_earned: 0 })

    // And it stays that way on every later request, with nothing written.
    const writes = db.writes.length
    const again = await sweep(db, sp('2026-10-02', '09:00'))
    expect(again.days).toEqual([])
    expect(db.writes.length).toBe(writes)
  })
})

describe('three inactive days in a row', () => {
  it('zero the streak once, and do not hold back the day that follows them', async () => {
    const db = account('recomposicao')
    vi.setSystemTime(sp('2026-09-28', '12:00'))
    register(db, 'recomposicao', '2026-09-28', { kcal: 1500, protein: 110 })
    await sweep(db, sp('2026-09-29', '08:00'), { maxDays: 3 })
    expect(db.progress(USER)).toMatchObject({ current_streak: 1, last_active_date: '2026-09-28' })

    // 29/09, 30/09 and 01/10: nothing. A request on the morning of 01/10 sees
    // two empty days behind it (29 and 30).
    const friday = await sweep(db, sp('2026-10-01', '08:00'), { maxDays: 3 })
    expect(friday.days).toEqual([])
    expect(friday.streakReset).toEqual({
      applied: true,
      previousStreak: 1,
      lastActiveDate: '2026-09-28',
      gapDays: 2,
    })
    expect(db.progress(USER)).toMatchObject({ current_streak: 0, longest_streak: 1 })

    // 02/10 is registered; the next request is on 03/10, with a budget of 3
    // days per request. The three empty dates use none of it.
    vi.setSystemTime(sp('2026-10-02', '12:00'))
    register(db, 'recomposicao', '2026-10-02', { kcal: 1500, protein: 110 })
    const monday = await sweep(db, sp('2026-10-03', '08:00'), { maxDays: 3 })

    expect(monday.days.map((day) => [day.date, day.closed])).toEqual([['2026-10-02', true]])
    expect(monday.streakReset).toBeNull()
    expect(db.progress(USER)).toMatchObject({
      current_streak: 1,
      longest_streak: 1,
      xp_total: 30,
      // 576 + 576
      deficit_block: 1152,
      last_active_date: '2026-10-02',
    })
    expect(db.events(USER, 'streak.reset_inactive')).toHaveLength(1)
    expect(db.events(USER, 'daily_closer.skipped')).toEqual([])
  })
})

// ───────────────────────────────────────────────────────────────────────────
// 2b. Yesterday closed outside the production closer's window
// ───────────────────────────────────────────────────────────────────────────

/**
 * Review of 2026-10-05 (calculation lens, HIGH). Production closes yesterday
 * only while the local hour is 0 to 4. The on-demand path closed yesterday at
 * ANY hour with the profile read at that moment, so a profile change of this
 * morning rewrote yesterday's stored target and credited a block value the
 * production closer would not have written.
 *
 * Rule now (docs §3a, rule 4): a close is late when the date is before
 * yesterday OR the local hour is 5 or later; a late close keeps the target
 * stored on the day row.
 *
 *   80 kg: BMR 1730 → 1730 × 1,2 − 500 = 1576
 *   82 kg: BMR 10×82 + 6,25×180 − 5×40 + 5 = 1750 → 1750 × 1,2 − 500 = 1600
 *   95 kg: BMR 10×95 + 6,25×180 − 5×40 + 5 = 1880 → 1880 × 1,2 − 500 = 1756
 */
describe('yesterday closed after 05:00 local keeps the target stored on its row', () => {
  const limits = { maxDays: 3, maxMs: 4000 }
  const FOUR_DAYS = ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04']

  function fourDaysAway() {
    const db = account('recomposicao')
    for (const date of FOUR_DAYS) {
      vi.setSystemTime(sp(date, '12:00'))
      register(db, 'recomposicao', date, { kcal: 1500, protein: 110 })
    }
    return db
  }
  function weighIn(db: DayCloseMemoryDb, weightKg: number) {
    // What `record_weight_atomic` does to the calculation: the profile weight.
    const row = db.tables.user_profiles[0]
    if (!row) throw new Error('fixture profile missing')
    row.weight_kg = weightKg
  }
  async function profileTargetNow(db: DayCloseMemoryDb) {
    const targets = await loadDailyTargets(db.client, USER, await loadCalcConfig(db.client))
    return targets.calories_target
  }
  const input = (now: Date) => ({ userId: USER, timezone: SAO_PAULO, now, from: '2026-09-01' })

  it("the reviewer's case: four days away, a weigh-in (80 → 82 kg) at 08:01 between the two requests of the morning", async () => {
    // Reference: every night closed at 00:30, as the production closer would
    // have, with the profile of that moment (80 kg).
    const reference = fourDaysAway()
    for (const date of ['2026-10-02', '2026-10-03', '2026-10-04', '2026-10-05']) {
      const night = sp(date, '00:30')
      vi.setSystemTime(night)
      await closePastOpenDays(reference.client, input(night))
    }

    const db = fourDaysAway()
    // 08:00 — GET /today: the budget of 3 closes 01, 02 and 03/10.
    const first = sp('2026-10-05', '08:00')
    vi.setSystemTime(first)
    const one = await closePastOpenDays(db.client, { ...input(first), limits })
    expect(one.days.map((day) => day.date)).toEqual(['2026-10-01', '2026-10-02', '2026-10-03'])
    expect(one.pendingDates).toEqual(['2026-10-04'])

    // 08:01 — the weight is registered.
    weighIn(db, 82)
    clearCalcConfigCache()
    expect(await profileTargetNow(db)).toBe(1600)

    // 08:02 — the next GET /today closes yesterday.
    const second = sp('2026-10-05', '08:02')
    vi.setSystemTime(second)
    const two = await closePastOpenDays(db.client, { ...input(second), limits })

    expect(
      two.days.map((day) => [
        day.date,
        day.late,
        day.detail?.storedCaloriesTarget,
        day.detail?.caloriesTarget,
        day.detail?.blockCredit,
      ]),
      // 1500 − 1576 = −76 → 500 + 76 = 576 (with 1600 it was 600).
    ).toEqual([['2026-10-04', true, 1576, 1576, 576]])
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      day_closed: true,
      calories_target: 1576,
      daily_balance: -76,
    })
    // 4 × 576 = 2304 (2328 when yesterday was rewritten with 1600).
    expect(db.progress(USER)).toMatchObject({
      xp_total: 60,
      current_streak: 4,
      deficit_block: 2304,
      last_active_date: '2026-10-04',
    })
    expect(reference.snapshot(USER, '2026-10-04')).toMatchObject({ calories_target: 1576 })
    expect(db.progress(USER)?.deficit_block).toBe(reference.progress(USER)?.deficit_block)
    expect(FOUR_DAYS.map((date) => db.snapshot(USER, date)?.calories_target)).toEqual(
      FOUR_DAYS.map((date) => reference.snapshot(USER, date)?.calories_target),
    )
  })

  it("the reviewer's direct variant: profile at 95 kg, yesterday closed at 22:00", async () => {
    const yesterday = () => {
      const db = account('recomposicao')
      vi.setSystemTime(sp('2026-10-04', '12:00'))
      register(db, 'recomposicao', '2026-10-04', { kcal: 1500, protein: 110 })
      return db
    }
    const early = yesterday()
    const night = sp('2026-10-05', '00:30')
    vi.setSystemTime(night)
    await closePastOpenDays(early.client, input(night))

    const lateDb = yesterday()
    weighIn(lateDb, 95)
    const evening = sp('2026-10-05', '22:00')
    vi.setSystemTime(evening)
    expect(await profileTargetNow(lateDb)).toBe(1756)
    const result = await closePastOpenDays(lateDb.client, input(evening))

    expect(result.days.map((day) => [day.date, day.closed, day.late])).toEqual([
      ['2026-10-04', true, true],
    ])
    // The same as the 00:30 close (with 1756 it was credit 756).
    for (const db of [early, lateDb]) {
      expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ calories_target: 1576 })
      expect(db.progress(USER)).toMatchObject({ deficit_block: 576, xp_total: 15 })
    }
  })

  it("inside production's window (04:59) yesterday still takes the profile's target, as the production closer does", async () => {
    const db = account('recomposicao')
    vi.setSystemTime(sp('2026-10-04', '12:00'))
    register(db, 'recomposicao', '2026-10-04', { kcal: 1500, protein: 110 })
    // A weigh-in right after midnight, before the closer's tick.
    weighIn(db, 82)
    const night = sp('2026-10-05', '04:59')
    vi.setSystemTime(night)

    const result = await closePastOpenDays(db.client, input(night))

    // 1500 − 1600 = −100 → 600.
    expect(
      result.days.map((day) => [
        day.date,
        day.late,
        day.detail?.storedCaloriesTarget,
        day.detail?.caloriesTarget,
        day.detail?.blockCredit,
      ]),
    ).toEqual([['2026-10-04', false, 1576, 1600, 600]])
  })

  it('declared pendency, locked as it is: the protocol is switched at 08:01 and yesterday closes at 08:02', async () => {
    const db = account('recomposicao')
    vi.setSystemTime(sp('2026-10-04', '12:00'))
    register(db, 'recomposicao', '2026-10-04', { kcal: 1500, protein: 110 })
    const row = db.tables.user_profiles[0]
    if (!row) throw new Error('fixture profile missing')
    row.current_protocol = 'ganho_massa'
    row.deficit_level = null
    const now = sp('2026-10-05', '08:02')
    vi.setSystemTime(now)

    const result = await closePastOpenDays(db.client, input(now))

    // The stored target is kept (1576), but the programmed deficit comes from
    // the profile of now (0): credit = −(1500 − 1576) = 76. The production
    // closer, at 00:30 with the profile still in recomposição, would have
    // written `recomposicao` and credited 500 + 76 = 576.
    expect(result.days[0]).toMatchObject({
      date: '2026-10-04',
      late: true,
      detail: { storedCaloriesTarget: 1576, caloriesTarget: 1576, blockCredit: 76 },
    })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      calories_target: 1576,
      current_protocol: 'ganho_massa',
    })
    expect(db.progress(USER)).toMatchObject({ deficit_block: 76 })
  })

  it('declared pendency, locked as it is: a weigh-in at 13:00 of the day itself, after its first record', async () => {
    const yesterday = () => {
      const db = account('recomposicao')
      // 12:00 — lunch: the row is created with the target of that moment.
      vi.setSystemTime(sp('2026-10-04', '12:00'))
      register(db, 'recomposicao', '2026-10-04', { kcal: 1500, protein: 110 })
      // 13:00 — weigh-in: the profile changes, the day row does not.
      weighIn(db, 82)
      return db
    }

    const lateDb = yesterday()
    const morning = sp('2026-10-05', '08:00')
    vi.setSystemTime(morning)
    const late = await closePastOpenDays(lateDb.client, input(morning))
    expect(late.days[0]).toMatchObject({
      late: true,
      detail: { storedCaloriesTarget: 1576, caloriesTarget: 1576, blockCredit: 576 },
    })

    // What the production closer writes for the same day (and this path too,
    // inside the window): the profile's target at 00:30.
    const windowDb = yesterday()
    const night = sp('2026-10-05', '00:30')
    vi.setSystemTime(night)
    clearCalcConfigCache()
    const inWindow = await closePastOpenDays(windowDb.client, input(night))
    expect(inWindow.days[0]).toMatchObject({
      late: false,
      detail: { storedCaloriesTarget: 1576, caloriesTarget: 1600, blockCredit: 600 },
    })
  })
})

// ───────────────────────────────────────────────────────────────────────────
// 3. Concurrency
// ───────────────────────────────────────────────────────────────────────────

describe('two interleaved sweeps and a registration that lands in the middle', () => {
  function threeOpenDays() {
    const db = account('recomposicao')
    for (const date of ['2026-10-02', '2026-10-03', '2026-10-04']) {
      vi.setSystemTime(sp(date, '12:00'))
      register(db, 'recomposicao', date, { kcal: 1000, protein: 60 })
    }
    return db
  }
  function lateDinner(db: DayCloseMemoryDb) {
    db.registerMeal({
      userId: USER,
      date: '2026-10-04',
      consumedAt: sp('2026-10-04', '22:30').toISOString(),
      kcal: 500,
      proteinG: 50,
      mealType: 'jantar',
      caloriesTarget: TARGET.recomposicao,
      proteinTarget: PROTEIN_TARGET,
    })
  }
  function dayState(db: DayCloseMemoryDb) {
    return ['2026-10-02', '2026-10-03', '2026-10-04'].map((date) => {
      const row = db.snapshot(USER, date)
      return [
        date,
        row?.day_closed,
        row?.calories_consumed,
        row?.protein_g,
        row?.calories_target,
        row?.xp_earned,
        row?.daily_balance,
      ]
    })
  }
  function progressState(db: DayCloseMemoryDb) {
    const { updated_at: _updated, ...rest } = db.progress(USER) ?? {}
    return rest
  }

  it('every day is finalized once, and the result equals a single sweep that saw the dinner', async () => {
    const now = sp('2026-10-05', '08:00')

    // Reference: the dinner was there before anything ran; one sweep.
    const serial = threeOpenDays()
    lateDinner(serial)
    await sweep(serial, now)

    // The app opens: GET /today and GET /progress start one sweep each. While
    // they run, the person confirms last night's dinner (a registration for
    // yesterday), exactly when the first sweep is about to write that day.
    const db = threeOpenDays()
    vi.setSystemTime(now)
    let dinnerLogged = false
    db.before = (operation) => {
      const writesYesterday =
        operation.kind === 'update' &&
        operation.target === 'daily_snapshots' &&
        operation.filters?.some((filter) => filter.value === db.snapshot(USER, '2026-10-04')?.id)
      if (!dinnerLogged && writesYesterday) {
        dinnerLogged = true
        lateDinner(db)
      }
    }
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-01' }
    const [first, second] = await Promise.all([
      closePastOpenDays(db.client, input),
      closePastOpenDays(db.client, input),
    ])
    expect(dinnerLogged).toBe(true)

    // Nothing was applied twice, whatever each sweep managed to close.
    const closedBy = (result: typeof first) =>
      result.days.filter((day) => day.closed).map((day) => day.date)
    const closedOnce = [...closedBy(first), ...closedBy(second)].sort()
    expect(new Set(closedOnce).size).toBe(closedOnce.length)
    // The stale sum (1000 kcal) never overwrote yesterday's row.
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ calories_consumed: 1500 })

    // The next request finishes whatever was left open by the collision.
    await closePastOpenDays(db.client, input)

    expect(dayState(db)).toEqual(dayState(serial))
    expect(progressState(db)).toEqual(progressState(serial))
    // 02/10 and 03/10: 1000 − 1576 = −576 → 1076 each, late, protein 60 → XP 10.
    // 04/10: 1500 − 1576 = −76 → 576; protein 110 → XP 15.
    expect(dayState(db)).toEqual([
      ['2026-10-02', true, 1000, 60, 1576, 10, -576],
      ['2026-10-03', true, 1000, 60, 1576, 10, -576],
      ['2026-10-04', true, 1500, 110, 1576, 15, -76],
    ])
    expect(progressState(db)).toMatchObject({
      xp_total: 35,
      current_streak: 3,
      longest_streak: 3,
      deficit_block: 2728,
      last_active_date: '2026-10-04',
    })
    expect(
      db.events(USER, 'daily_closer.completed').map((event) => {
        const properties = event.properties as MemoryRow
        return [properties.snapshot_date, properties.calories_consumed]
      }),
    ).toEqual([
      ['2026-10-02', 1000],
      ['2026-10-03', 1000],
      ['2026-10-04', 1500],
    ])
  })

  /**
   * Review of 2026-10-05 (both lenses, HIGH), exact reproduction: the dinner
   * lands on the MIDDLE day. Before the fix the sweep answered
   * `changed_concurrently` for 03/10, went on and closed 04/10; the frontier
   * passed 03/10 and it never closed again (final xp 20, sequência 1, bloco
   * 2152 instead of 35 / 3 / 2728).
   */
  it('a retroactive dinner confirmed on the MIDDLE day while the sweep handles it: the sweep stops there and the next request closes both', async () => {
    const now = sp('2026-10-05', '08:00')
    const middleDinner = (db: DayCloseMemoryDb) =>
      db.registerMeal({
        userId: USER,
        date: '2026-10-03',
        consumedAt: sp('2026-10-03', '21:00').toISOString(),
        kcal: 500,
        proteinG: 50,
        mealType: 'almoco',
        caloriesTarget: TARGET.recomposicao,
        proteinTarget: PROTEIN_TARGET,
      })

    // Reference: one sweep that saw the dinner.
    const serial = threeOpenDays()
    middleDinner(serial)
    await sweep(serial, now)

    const db = threeOpenDays()
    vi.setSystemTime(now)
    let dinnerLogged = false
    db.before = (operation) => {
      // Between the re-read of 03/10 and its conditional update.
      const writesMiddleDay =
        operation.kind === 'update' &&
        operation.target === 'daily_snapshots' &&
        operation.filters?.some((filter) => filter.value === db.snapshot(USER, '2026-10-03')?.id)
      if (!dinnerLogged && writesMiddleDay) {
        dinnerLogged = true
        middleDinner(db)
      }
    }
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-01' }

    const first = await closePastOpenDays(db.client, input)

    expect(dinnerLogged).toBe(true)
    // 04/10 is not attempted: it waits behind 03/10.
    expect(
      first.days.map((day) => [
        day.date,
        day.closed,
        day.reason,
        day.detail?.progress.currentStreak,
      ]),
    ).toEqual([
      ['2026-10-02', true, undefined, 1],
      ['2026-10-03', false, 'changed_concurrently', undefined],
    ])
    expect(first.pendingDates).toEqual(['2026-10-03', '2026-10-04'])
    expect(first.complete).toBe(false)
    expect(first.streakReset).toBeNull()
    expect(dayState(db)).toEqual([
      ['2026-10-02', true, 1000, 60, 1576, 10, -576],
      // The stale sum (1000) did not overwrite the row, and nothing was earned yet.
      ['2026-10-03', false, 1500, 110, 1576, 0, -76],
      ['2026-10-04', false, 1000, 60, 1576, 0, -576],
    ])
    expect(progressState(db)).toMatchObject({
      xp_total: 10,
      current_streak: 1,
      deficit_block: 1076,
      last_active_date: '2026-10-02',
    })

    // The next request starts again from 03/10.
    const second = await closePastOpenDays(db.client, input)

    expect(second.days.map((day) => [day.date, day.closed])).toEqual([
      ['2026-10-03', true],
      ['2026-10-04', true],
    ])
    expect(second.staleOpenDates).toEqual([])
    expect(second.complete).toBe(true)
    expect(dayState(db)).toEqual(dayState(serial))
    expect(progressState(db)).toEqual(progressState(serial))
    // 02/10: 1000 − 1576 = −576 → 1076; 60 g → XP 10.
    // 03/10: 1500 − 1576 = −76 → 576; 110 g → XP 15.
    // 04/10: 1076; XP 10.            1076 + 576 + 1076 = 2728; 10 + 15 + 10 = 35.
    expect(dayState(db)).toEqual([
      ['2026-10-02', true, 1000, 60, 1576, 10, -576],
      ['2026-10-03', true, 1500, 110, 1576, 15, -76],
      ['2026-10-04', true, 1000, 60, 1576, 10, -576],
    ])
    expect(progressState(db)).toMatchObject({
      xp_total: 35,
      current_streak: 3,
      longest_streak: 3,
      deficit_block: 2728,
      last_active_date: '2026-10-04',
    })
    expect(
      db.events(USER, 'daily_closer.completed').map((event) => {
        const properties = event.properties as MemoryRow
        return [properties.snapshot_date, properties.calories_consumed]
      }),
    ).toEqual([
      ['2026-10-02', 1000],
      ['2026-10-03', 1500],
      ['2026-10-04', 1000],
    ])
    // And nothing is left to do.
    const writes = db.writes.length
    const third = await closePastOpenDays(db.client, input)
    expect(third.days).toEqual([])
    expect(db.writes.length).toBe(writes)
  })

  it('three sweeps at once, no registration: the same totals as one', async () => {
    const now = sp('2026-10-05', '08:00')
    const serial = threeOpenDays()
    await sweep(serial, now)

    const db = threeOpenDays()
    vi.setSystemTime(now)
    const input = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-01' }
    await Promise.all([
      closePastOpenDays(db.client, input),
      closePastOpenDays(db.client, input),
      closePastOpenDays(db.client, input),
    ])
    await closePastOpenDays(db.client, input)

    expect(dayState(db)).toEqual(dayState(serial))
    expect(progressState(db)).toEqual(progressState(serial))
    // 3 × 1076 = 3228; 3 × 10 XP
    expect(progressState(db)).toMatchObject({
      xp_total: 30,
      deficit_block: 3228,
      current_streak: 3,
    })
    expect(db.events(USER, 'daily_closer.completed')).toHaveLength(3)
  })
})

/**
 * Review of 2026-10-05 (both lenses, HIGH), second reproduction: no
 * registration at all. The app opens and GET /today and GET /progress each
 * start a sweep. The account has the shape of staging's conta-11: a day with
 * only an inbound message (no day row), then a day with a meal. Both requests
 * read "no row" for the first day; one creates it, the other's
 * `ignoreDuplicates` insert comes back empty (`changed_concurrently`). Before
 * the fix the loser went on, closed the later day, and the first day either
 * never closed (frontier passed) or its late finalization overwrote the
 * progress with absolute values.
 *
 * 27/09: message only → target from the profile (1576), XP 10, credit 0.
 * 30/09: 1500 kcal, 110 g → 1500 − 1576 = −76 → 576, XP 15. 28 and 29/09 are
 * empty, so the streak restarts at 1; 01 to 04/10 are empty, so one complete
 * sweep zeroes it (04/10 − 30/09 = 4 days).
 */
describe('GET /today and GET /progress at the same time, a message-only day then a day with a meal (the shape of staging)', () => {
  const now = sp('2026-10-05', '08:00')
  const input = {
    userId: USER,
    timezone: SAO_PAULO,
    now,
    from: '2026-09-17',
    // The budget of one request of the mobile API.
    limits: { maxDays: 3, maxMs: 4000 },
  }

  function stagingShaped() {
    const db = account('recomposicao')
    db.addInboundMessage(USER, sp('2026-09-27', '10:00').toISOString())
    vi.setSystemTime(sp('2026-09-30', '12:00'))
    register(db, 'recomposicao', '2026-09-30', { kcal: 1500, protein: 110 })
    vi.setSystemTime(now)
    return db
  }
  function state(db: DayCloseMemoryDb) {
    const { updated_at: _updated, ...progress } = db.progress(USER) ?? {}
    return {
      progress,
      days: ['2026-09-27', '2026-09-30'].map((date) => {
        const row = db.snapshot(USER, date)
        return [date, row?.day_closed, row?.calories_consumed, row?.calories_target, row?.xp_earned]
      }),
      closes: db
        .events(USER, 'daily_closer.completed')
        .map((event) => (event.properties as MemoryRow).snapshot_date),
      resets: db.events(USER, 'streak.reset_inactive').length,
    }
  }
  function deferred() {
    let open: () => void = () => undefined
    const wait = new Promise<void>((resolvePromise) => {
      open = resolvePromise
    })
    return { wait, open }
  }
  const SERIAL = {
    progress: {
      user_id: USER,
      xp_total: 25,
      level: 1,
      current_streak: 0,
      longest_streak: 1,
      blocks_completed: 0,
      deficit_block: 576,
      badges_earned: [],
      last_active_date: '2026-09-30',
      next_reevaluation: null,
      current_weight: null,
      current_bf_percent: null,
    },
    days: [
      ['2026-09-27', true, 0, 1576, 10],
      ['2026-09-30', true, 1500, 1576, 15],
    ],
    closes: ['2026-09-27', '2026-09-30'],
    resets: 1,
  }

  it('one request alone (the serial sweep): 25 XP, bloco 576, both days closed', async () => {
    const serial = stagingShaped()
    const result = await closePastOpenDays(serial.client, input)
    expect(result.days.map((day) => [day.date, day.closed])).toEqual([
      ['2026-09-27', true],
      ['2026-09-30', true],
    ])
    expect(state(serial)).toEqual(SERIAL)
  })

  it('request A stalls right after creating the row of 27/09; request B runs whole meanwhile: both end as the serial sweep', async () => {
    const db = stagingShaped()

    // A: a slow round trip between its insert of the day row and its read of
    // the progress.
    const aInserted = deferred()
    const aResume = deferred()
    let aJustInserted = false
    const requestA = closePastOpenDays(
      db.session(async (operation: MemoryOperation) => {
        if (aJustInserted && operation.kind === 'select' && operation.target === 'user_progress') {
          aJustInserted = false
          aInserted.open()
          await aResume.wait
        }
        if (operation.kind === 'upsert' && operation.target === 'daily_snapshots') {
          aJustInserted = true
        }
      }),
      input,
    )
    // B: read "no row for 27/09" at the same time as A; its insert arrives
    // after A's.
    let bHeld = false
    const requestB = closePastOpenDays(
      db.session(async (operation: MemoryOperation) => {
        if (!bHeld && operation.kind === 'upsert' && operation.target === 'daily_snapshots') {
          bHeld = true
          await aInserted.wait
        }
      }),
      input,
    )

    const b = await requestB
    // B lost 27/09 and stopped there: 30/09 was not attempted by it.
    expect(b.days.map((day) => [day.date, day.closed, day.reason])).toEqual([
      ['2026-09-27', false, 'changed_concurrently'],
    ])
    expect(b.pendingDates).toEqual(['2026-09-27', '2026-09-30'])
    expect(b.complete).toBe(false)
    expect(b.streakReset).toBeNull()
    expect(db.snapshot(USER, '2026-09-30')).toMatchObject({ day_closed: false })
    expect(db.progress(USER)).toMatchObject({ xp_total: 0, last_active_date: null })

    aResume.open()
    const a = await requestA
    expect(a.days.map((day) => [day.date, day.closed])).toEqual([
      ['2026-09-27', true],
      ['2026-09-30', true],
    ])
    expect(a.staleOpenDates).toEqual([])
    expect(state(db)).toEqual(SERIAL)

    // The next request finds nothing open and nothing behind the frontier.
    const writes = db.writes.length
    const later = await closePastOpenDays(db.client, input)
    expect(later.days).toEqual([])
    expect(later.staleOpenDates).toEqual([])
    expect(db.writes.length).toBe(writes)
  })

  it('both in step, the finalization of 27/09 by the request that created its row is slow: both end as the serial sweep', async () => {
    const db = stagingShaped()
    let delayed = false
    db.before = async (operation) => {
      const first = db.snapshot(USER, '2026-09-27')
      if (
        !delayed &&
        operation.kind === 'rpc' &&
        operation.target === 'finalize_daily_close_atomic' &&
        first !== null &&
        operation.params?.p_snapshot_id === first.id
      ) {
        delayed = true
        // Long enough for the other request to run to its end.
        for (let turn = 0; turn < 400; turn++) await Promise.resolve()
      }
    }

    const [a, b] = await Promise.all([
      closePastOpenDays(db.client, input),
      closePastOpenDays(db.client, input),
    ])

    expect(delayed).toBe(true)
    const outcomes = [a, b].map((result) =>
      result.days.map((day) => `${day.date}:${day.closed ? 'closed' : day.reason}`),
    )
    expect(outcomes).toContainEqual(['2026-09-27:closed', '2026-09-30:closed'])
    expect(outcomes).toContainEqual(['2026-09-27:changed_concurrently'])
    expect(state(db)).toEqual(SERIAL)
  })

  it("the reviewer's own numbers (meal, message-only day, meal; the slow finalization): 30 XP, sequência 3, bloco 2152", async () => {
    const build = () => {
      const db = account('recomposicao')
      vi.setSystemTime(sp('2026-10-02', '12:00'))
      register(db, 'recomposicao', '2026-10-02', { kcal: 1000, protein: 60 })
      db.addInboundMessage(USER, sp('2026-10-03', '10:00').toISOString())
      vi.setSystemTime(sp('2026-10-04', '12:00'))
      register(db, 'recomposicao', '2026-10-04', { kcal: 1000, protein: 60 })
      vi.setSystemTime(now)
      return db
    }
    const unlimited = { userId: USER, timezone: SAO_PAULO, now, from: '2026-09-01' }
    const progressOf = (db: DayCloseMemoryDb) => {
      const { updated_at: _updated, ...rest } = db.progress(USER) ?? {}
      return rest
    }
    const serial = build()
    await closePastOpenDays(serial.client, unlimited)

    const db = build()
    let delayed = false
    db.before = async (operation) => {
      const middle = db.snapshot(USER, '2026-10-03')
      if (
        !delayed &&
        operation.kind === 'rpc' &&
        operation.target === 'finalize_daily_close_atomic' &&
        middle !== null &&
        operation.params?.p_snapshot_id === middle.id
      ) {
        delayed = true
        for (let turn = 0; turn < 400; turn++) await Promise.resolve()
      }
    }
    await Promise.all([
      closePastOpenDays(db.client, unlimited),
      closePastOpenDays(db.client, unlimited),
    ])
    expect(delayed).toBe(true)
    // Whatever the collision left pending is closed by the next request.
    db.before = null
    await closePastOpenDays(db.client, unlimited)

    expect(progressOf(db)).toEqual(progressOf(serial))
    // 02/10 and 04/10: 1076 each, XP 10; 03/10: XP 10, credit 0.
    expect(progressOf(db)).toMatchObject({
      xp_total: 30,
      current_streak: 3,
      deficit_block: 2152,
      last_active_date: '2026-10-04',
    })
    expect(db.events(USER, 'daily_closer.completed')).toHaveLength(3)
  })
})

// ───────────────────────────────────────────────────────────────────────────
// 4. The 30 minutes after midnight
// ───────────────────────────────────────────────────────────────────────────

describe('yesterday becomes closable 30 minutes after local midnight; today never does', () => {
  it('America/Sao_Paulo (UTC−3)', async () => {
    const db = account('recomposicao')
    vi.setSystemTime(sp('2026-10-04', '12:00'))
    register(db, 'recomposicao', '2026-10-04', { kcal: 1500, protein: 110 })
    const at = (now: Date) => {
      vi.setSystemTime(now)
      return closePastOpenDays(db.client, {
        userId: USER,
        timezone: SAO_PAULO,
        now,
        from: '2026-09-01',
      })
    }

    for (const now of [
      sp('2026-10-04', '23:59'),
      sp('2026-10-05', '00:00'),
      sp('2026-10-05', '00:10'),
      sp('2026-10-05', '00:29'),
    ]) {
      const early = await at(now)
      expect(early.latestClosableDate, now.toISOString()).toBe('2026-10-03')
      expect(early.days, now.toISOString()).toEqual([])
    }
    expect(db.writes).toEqual([])
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: false })

    const onTime = await at(sp('2026-10-05', '00:30'))
    expect(onTime.latestClosableDate).toBe('2026-10-04')
    expect(onTime.days.map((day) => [day.date, day.closed, day.late])).toEqual([
      ['2026-10-04', true, false],
    ])
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({
      day_closed: true,
      closed_at: '2026-10-05T03:30:00.000Z',
    })
  })

  it('Asia/Kolkata (UTC+5:30): the day is cut at the half hour, and the wait still is 30 minutes', async () => {
    const KOLKATA = 'Asia/Kolkata'
    const db = new DayCloseMemoryDb()
    db.addAccount({ userId: USER, timezone: KOLKATA, profile: profile('recomposicao') })
    // Local midnight of 2026-10-04 is 2026-10-03T18:30Z.
    //   23:45 local of the 3rd = 18:15Z of the 3rd → belongs to the 3rd
    //   00:15 local of the 4th = 18:45Z of the 3rd → belongs to the 4th
    vi.setSystemTime(new Date('2026-10-03T18:15:00.000Z'))
    db.registerMeal({
      userId: USER,
      date: '2026-10-03',
      consumedAt: '2026-10-03T18:15:00.000Z',
      kcal: 900,
      proteinG: 50,
      caloriesTarget: 1576,
      proteinTarget: PROTEIN_TARGET,
    })
    vi.setSystemTime(new Date('2026-10-03T18:45:00.000Z'))
    db.registerMeal({
      userId: USER,
      date: '2026-10-04',
      consumedAt: '2026-10-03T18:45:00.000Z',
      kcal: 1500,
      proteinG: 110,
      caloriesTarget: 1576,
      proteinTarget: PROTEIN_TARGET,
    })
    const at = (now: Date) => {
      vi.setSystemTime(now)
      return closePastOpenDays(db.client, {
        userId: USER,
        timezone: KOLKATA,
        now,
        from: '2026-09-01',
      })
    }

    // 00:29 local of the 5th = 18:59Z of the 4th: only the 3rd may be closed.
    const before = await at(new Date('2026-10-04T18:59:00.000Z'))
    expect(before.latestClosableDate).toBe('2026-10-03')
    expect(before.days.map((day) => [day.date, day.closed, day.late])).toEqual([
      ['2026-10-03', true, true],
    ])
    // 900 − 1576 = −676 → 1176 (900 ≥ 788, not under-registered)
    expect(before.days[0]?.detail).toMatchObject({ caloriesConsumed: 900, blockCredit: 1176 })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: false })

    // 00:30 local of the 5th = 19:00Z of the 4th.
    const after = await at(new Date('2026-10-04T19:00:00.000Z'))
    expect(after.latestClosableDate).toBe('2026-10-04')
    expect(after.days.map((day) => [day.date, day.closed, day.late])).toEqual([
      ['2026-10-04', true, false],
    ])
    // 1500 − 1576 = −76 → 576; the 00:15 meal was not counted on the 3rd.
    expect(after.days[0]?.detail).toMatchObject({
      caloriesConsumed: 1500,
      blockCredit: 576,
      progress: { currentStreak: 2, deficitBlock: 1752, xpTotal: 25 },
    })
  })
})

/**
 * Declared pendency, locked as it is (review of 2026-10-05, LOW). The older
 * helper `localMidnightUtc` (timezone-utils.ts, also used by the production
 * closer; not changed) answers the start of a local day one hour EARLY when
 * the zone has a positive offset and its clocks go forward exactly at
 * midnight: that day has no 00:00, it starts at 01:00. Found by walking every
 * day of 2026 in 20 zones: only these two days.
 */
describe('characterization: a zone whose daylight saving starts at midnight (positive offset)', () => {
  it.each([
    // zone, the day the clocks go forward, its real first instant (01:00 local), what the helper answers
    ['Africa/Cairo', '2026-04-24', '2026-04-23T22:00:00.000Z', '2026-04-23T21:00:00.000Z'],
    ['Asia/Beirut', '2026-03-29', '2026-03-28T22:00:00.000Z', '2026-03-28T21:00:00.000Z'],
  ])('%s, %s: the day starts one hour early and yesterday is closable in its first instant', (zone, date, realStart, helperStart) => {
    const previous = getLocalDateString(zone, new Date(Date.parse(realStart) - 1))
    const dayBefore = getLocalDateString(zone, new Date(Date.parse(realStart) - 25 * 3_600_000))
    // The calendar: `realStart` is the first instant of `date`.
    expect(getLocalDateString(zone, new Date(realStart))).toBe(date)
    expect(previous < date).toBe(true)

    // The helper: one hour early, so the last hour of the previous day is
    // counted on this one. The two days still share one boundary (no hour is
    // counted twice or lost).
    expect(getLocalDayUtcBounds(zone, date).startIso).toBe(helperStart)
    expect(getLocalDayUtcBounds(zone, previous).endExclusiveIso).toBe(helperStart)
    expect(getLocalDateString(zone, new Date(helperStart))).toBe(previous)

    // The 30-minute wait does not hold on this day: at its first instant the
    // previous day is already closable (it should still be the day before).
    expect(latestClosableLocalDate(zone, new Date(realStart))).toBe(previous)
    expect(latestClosableLocalDate(zone, new Date(Date.parse(realStart) - 1))).toBe(dayBefore)
    // Today is never closable, here either.
    for (const minutes of [0, 15, 29, 30, 600]) {
      const at = new Date(Date.parse(realStart) + minutes * 60_000)
      expect(latestClosableLocalDate(zone, at) < getLocalDateString(zone, at)).toBe(true)
    }

    // The next midnight is an ordinary one again: the wait holds.
    const nextStart = Date.parse(getLocalDayUtcBounds(zone, date).endExclusiveIso)
    expect(getLocalDateString(zone, new Date(nextStart - 1))).toBe(date)
    expect(latestClosableLocalDate(zone, new Date(nextStart + 29 * 60_000))).toBe(previous)
    expect(latestClosableLocalDate(zone, new Date(nextStart + 30 * 60_000))).toBe(date)
  })
})

// ───────────────────────────────────────────────────────────────────────────
// 5. The open days of staging, as read on 2026-10-04
// ───────────────────────────────────────────────────────────────────────────

/**
 * Conta "conta-10" (ganho de massa): the 11 past days that have a row, read on
 * 2026-10-04. [date, kcal, protein g, exercise kcal (0 = no workout), stored
 * calories target, stored protein target, XP, credit, block after, streak].
 * credit = stored target + exercise − consumed (late close keeps the stored
 * target; no day is under 50% of it). 25/09 has no record.
 */
const CONTA_10: Array<
  [string, number, number, number, number, number, number, number, number, number]
> = [
  // 2980 + 380 − 3060 = 300
  ['2026-09-22', 3060, 224.1, 380, 2980, 144, 20, 300, 300, 1],
  // 2980 − 2846 = 134
  ['2026-09-23', 2846, 208.5, 0, 2980, 144, 15, 134, 434, 2],
  // 2980 + 360 − 3305 = 35
  ['2026-09-24', 3305, 242.0, 360, 2980, 144, 20, 35, 469, 3],
  // 25/09 empty: the streak restarts. 2980 + 380 − 2968 = 392
  ['2026-09-26', 2968, 217.7, 380, 2980, 144, 20, 392, 861, 1],
  // 3355 − 2683 = 672 (with the profile's 2988 of today it would be 305)
  ['2026-09-27', 2683, 202.5, 0, 3355, 185.4, 15, 672, 1533, 2],
  // 3361 + 380 − 2810 = 931 (558 with 2988)
  ['2026-09-28', 2810, 202.9, 380, 3361, 186.1, 20, 931, 2464, 3],
  // 2980 + 360 − 3121 = 219
  ['2026-09-29', 3121, 228.5, 360, 2980, 144, 20, 219, 2683, 4],
  // 2980 − 2166 = 814
  ['2026-09-30', 2166, 168.4, 0, 2980, 144, 15, 814, 3497, 5],
  // 3361 + 380 − 2259 = 1482 (1109 with 2988)
  ['2026-10-01', 2259, 154.6, 380, 3361, 186.1, 20, 1482, 4979, 6],
  // 2980 − 3427 = −447
  ['2026-10-02', 3427, 251.3, 0, 2980, 144, 15, -447, 4532, 7],
  // 2980 + 380 − 2007 = 1353
  ['2026-10-03', 2007, 142.9, 380, 2980, 144, 20, 1353, 5885, 8],
]

describe('the open days of staging (read on 2026-10-04): what the simulation must print', () => {
  // 00:10 of 05/10: the 4th (still being registered when read) is not
  // closable yet, and every day up to the 3rd is a late close.
  const NOW = sp('2026-10-05', '00:10')
  const input = { userId: USER, timezone: SAO_PAULO, now: NOW, from: '2026-09-17' }

  function conta10() {
    const db = account('ganho_massa')
    for (const [date, kcal, protein, exercise, storedTarget, storedProtein] of CONTA_10) {
      vi.setSystemTime(sp(date, '12:00'))
      register(db, 'ganho_massa', date, {
        kcal,
        protein,
        ...(exercise > 0 ? { workout: exercise } : {}),
        storedTarget,
        storedProtein,
      })
    }
    vi.setSystemTime(NOW)
    return db
  }

  it('conta-10: 11 days, 200 XP, nível 2, sequência 8, bloco 5.885, "Primeira Semana" on 02/10', async () => {
    const db = conta10()

    const simulated = await closePastOpenDays(db.client, { ...input, dryRun: true })
    expect(db.writes).toEqual([])
    expect(
      simulated.days.map((day) => [
        day.date,
        day.detail?.caloriesConsumed,
        day.detail?.proteinTarget === day.detail?.storedProteinTarget,
        day.detail?.exerciseCalories,
        day.detail?.storedCaloriesTarget,
        day.detail?.caloriesTarget,
        day.detail?.xpEarned,
        day.detail?.blockCredit,
        day.detail?.progress.deficitBlock,
        day.detail?.progress.currentStreak,
      ]),
    ).toEqual(
      CONTA_10.map(([date, kcal, , exercise, storedTarget, , xp, credit, block, streak]) => [
        date,
        kcal,
        true,
        exercise,
        storedTarget,
        // Late close: the stored target is the one written.
        storedTarget,
        xp,
        credit,
        block,
        streak,
      ]),
    )
    expect(simulated.days.every((day) => day.late && day.detail?.dayStatus === 'complete')).toBe(
      true,
    )
    expect(simulated.days.find((day) => day.date === '2026-10-02')?.detail?.newBadges).toEqual([
      'Primeira Semana',
    ])
    // 20+15+20+20+15+20 = 110 on 28/09: nível 2 from that day on.
    expect(simulated.days.map((day) => day.detail?.progress.level)).toEqual([
      1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2,
    ])
    expect(simulated.streakReset).toBeNull()

    const applied = await closePastOpenDays(db.client, input)
    expect(applied.days.map((day) => day.detail)).toEqual(simulated.days.map((day) => day.detail))
    expect(db.progress(USER)).toMatchObject({
      xp_total: 200,
      level: 2,
      current_streak: 8,
      longest_streak: 8,
      blocks_completed: 0,
      deficit_block: 5885,
      badges_earned: ['Primeira Semana'],
      last_active_date: '2026-10-03',
      next_reevaluation: null,
    })
    // The three days whose stored target is not today's keep it.
    expect(
      ['2026-09-27', '2026-09-28', '2026-10-01'].map(
        (date) => db.snapshot(USER, date)?.calories_target,
      ),
    ).toEqual([3355, 3361, 3361])
  })

  /**
   * The 12th day of conta-10. On 2026-10-04 it was still in progress: 1018
   * kcal, a workout of 322 kcal, stored target 2980 (read; the protein of that
   * day was not kept in this file — the previous readout gave XP 20, which
   * needs ≥ 100 g, so 100 g is ASSUMED here and the XP is not what this test
   * is about). What the review of 2026-10-05 changed is the TARGET written
   * when it closes as "yesterday" on 05/10:
   *   00:30–04:59 → the profile's target (2988 on staging; 2498 with the
   *                 synthetic profile of this file), as the production closer;
   *   05:00 on    → the stored 2980 (before the review: the profile's, at any
   *                 hour of 05/10).
   * The credit is 0 either way: 1018 < 50% of the target, under-registered,
   * and the programmed deficit outside recomposição is 0.
   */
  it.each([
    ['2026-10-05', '00:30', false, TARGET.ganho_massa],
    ['2026-10-05', '04:59', false, TARGET.ganho_massa],
    ['2026-10-05', '05:00', true, 2980],
    ['2026-10-05', '09:00', true, 2980],
    ['2026-10-06', '09:00', true, 2980],
  ] as const)('conta-10, the day of 04/10 closed on %s at %s: late = %s, target written %d, credit 0, sequência 9, bloco 5.885', async (date, time, late, target) => {
    const db = conta10()
    vi.setSystemTime(sp('2026-10-04', '12:00'))
    register(db, 'ganho_massa', '2026-10-04', {
      kcal: 1018,
      protein: 100,
      workout: 322,
      storedTarget: 2980,
      storedProtein: 144,
    })
    const now = sp(date, time)
    vi.setSystemTime(now)

    const result = await closePastOpenDays(db.client, { ...input, now })

    expect(result.days).toHaveLength(12)
    expect(result.days.at(-1)).toMatchObject({
      date: '2026-10-04',
      closed: true,
      late,
      detail: {
        caloriesConsumed: 1018,
        exerciseCalories: 322,
        storedCaloriesTarget: 2980,
        caloriesTarget: target,
        blockCredit: 0,
        progress: { currentStreak: 9, deficitBlock: 5885, xpTotal: 220 },
      },
    })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ calories_target: target })
    // The eleven earlier days are late at any of these instants: unchanged.
    expect(
      result.days.slice(0, 11).map((day) => [day.date, day.late, day.detail?.blockCredit]),
    ).toEqual(CONTA_10.map(([day, , , , , , , credit]) => [day, true, credit]))
  })

  it('conta-11 (ganho de massa): a message-only day and an under-registered day → 20 XP, sequência 0 (maior 1), bloco 0', async () => {
    const db = account('ganho_massa')
    // 27/09: one inbound Flow message, no day row.
    db.addInboundMessage(USER, sp('2026-09-27', '10:00').toISOString())
    // 30/09: 383 kcal, 42,2 g, stored target 2214 / 111,6.
    vi.setSystemTime(sp('2026-09-30', '12:00'))
    register(db, 'ganho_massa', '2026-09-30', {
      kcal: 383,
      protein: 42.2,
      storedTarget: 2214,
      storedProtein: 111.6,
    })
    vi.setSystemTime(NOW)

    const result = await closePastOpenDays(db.client, input)

    expect(
      result.days.map((day) => [
        day.date,
        day.detail?.caloriesConsumed,
        day.detail?.storedCaloriesTarget,
        day.detail?.xpEarned,
        day.detail?.blockCredit,
        day.detail?.progress.currentStreak,
      ]),
    ).toEqual([
      // No row: the target written comes from the profile (not asserted: the
      // profile here is synthetic; on staging it gives 2214 / 111,6).
      ['2026-09-27', 0, null, 10, 0, 1],
      // 383 < 0,5 × 2214 = 1107 → under-registered → credits the programmed
      // deficit, which is 0 outside recomposição. 28 and 29/09 are empty, so
      // the streak restarts at 1.
      ['2026-09-30', 383, 2214, 10, 0, 1],
    ])
    expect(db.snapshot(USER, '2026-09-30')).toMatchObject({ calories_target: 2214 })
    // 01/10, 02/10 and 03/10 are empty: 03/10 − 30/09 = 3 days.
    expect(result.streakReset).toEqual({
      applied: true,
      previousStreak: 1,
      lastActiveDate: '2026-09-30',
      gapDays: 3,
    })
    expect(db.progress(USER)).toMatchObject({
      xp_total: 20,
      level: 1,
      current_streak: 0,
      longest_streak: 1,
      deficit_block: 0,
      last_active_date: '2026-09-30',
    })
  })

  it('conta-09 (recomposição): one message-only day → 10 XP, sequência 0 (maior 1), bloco 0', async () => {
    const db = account('recomposicao')
    db.addInboundMessage(USER, sp('2026-09-17', '10:00').toISOString())
    vi.setSystemTime(NOW)

    const result = await closePastOpenDays(db.client, input)

    expect(
      result.days.map((day) => [day.date, day.detail?.xpEarned, day.detail?.blockCredit]),
    ).toEqual([['2026-09-17', 10, 0]])
    expect(result.streakReset).toMatchObject({ applied: true, previousStreak: 1, gapDays: 16 })
    expect(db.progress(USER)).toMatchObject({
      xp_total: 10,
      current_streak: 0,
      longest_streak: 1,
      deficit_block: 0,
    })
  })

  it('with the first allowed date after those days (MOBILE_DAY_CLOSE_FROM = 2026-10-05) none of them is touched', async () => {
    const db = conta10()
    const writes = db.writes.length
    const result = await closePastOpenDays(db.client, {
      ...input,
      now: sp('2026-10-06', '08:00'),
      from: '2026-10-05',
    })
    expect(result.days).toEqual([])
    expect(db.writes.length).toBe(writes)
    expect(db.progress(USER)).toMatchObject({ xp_total: 0, last_active_date: null })
  })
})

// ───────────────────────────────────────────────────────────────────────────
// 6. The declared pendencies are the same in the doc
// ───────────────────────────────────────────────────────────────────────────

describe('declared pendencies', () => {
  it('every "RC F" line of this header is in docs/CALCULO-MPP.md, identical', () => {
    const here = dirname(fileURLToPath(import.meta.url))
    const header = readFileSync(fileURLToPath(import.meta.url), 'utf8')
    const doc = readFileSync(resolve(here, '../../../../docs/CALCULO-MPP.md'), 'utf8')
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC F — .*)$/gm), (match) => match[1])
    const fromDoc = Array.from(doc.matchAll(/^(> RC F — .*)$/gm), (match) => match[1])
    expect(fromHeader.length).toBeGreaterThanOrEqual(15)
    expect(fromDoc).toEqual(fromHeader)
  })
})
