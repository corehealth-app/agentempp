/**
 * Golden — protein target of recomposição: 1.5 g per kg, fixed (rule M1).
 * Audit of the client's WhatsApp group, 2026-10-04. Rule and worked numbers:
 * docs/CALCULO-MPP.md §1b.
 *
 * STATUS OF THE RULE (never a new decision of the client):
 *  dito pelo cliente em 15/04/2026 e em 15/05/2026 (texto no grupo);
 *  implementado em 2026-10-04 a pedido do Eduardo; confirmação do cliente
 *  pendente. Interruptor (um só, desfaz a meta E devolve o `protein_factor` da
 *  view ao retorno de `cadastra_dados_iniciais`): linha
 *  `calc.recomp_protein_g_per_kg` = 0 em `global_config` (sem deploy; o SQL
 *  exato está em docs/CALCULO-MPP.md §1b) ou `RECOMP_PROTEIN_G_PER_KG` = null
 *  em `packages/core/src/calc-config.ts`.
 *
 * REVIEW OF 2026-10-04 (adversarial, protein and balance lenses) — the inputs
 * below are the reviewers', run here through the production code:
 *  - "perfil ganho_massa 80 kg, fome moderada, 4 treinos, global_config com a
 *    cascata do staging + linha calc.recomp_protein_g_per_kg = null
 *    (interruptor DESLIGADO), view devolvendo protein_factor 1.8. HEAD:
 *    metrics = {..., imc: 23.37, protein_factor: 1.8}, protein_target_today_g
 *    144 ... (2980 kcal / 144 g)". The first version of M1 dropped the key in
 *    every protocol and the switch did not bring it back.
 *  - "recomposição 100 kg, fome pouca, 5 treinos, cascata do staging: linha =
 *    99 → protein_target 9900 g; linha = 1e9 → 100000000000 g; linha = "1.5"
 *    (texto) → 200 g (cascata), sem erro nem log, em vez de 150 g. null e 0 →
 *    200 g (interruptor); 1.2 → 120 g".
 *
 * READ FROM THE GROUP (not invented):
 *  - C5-17, 15/04/2026 12:40:41, Roberto, over the agent's print of 11:37:
 *    "Roberto, plano inicial do MPP organizado: • Meta calórica diária: 1914
 *    kcal • Meta de proteína: 180 g • Meta de ingestão de água: 3.5 L/dia •
 *    Meta de sono: 8 h/noite • Estratégia de treino: musculação 5x/sem + 8500
 *    passos/dia". Typed by the client: "A meta de proteina eu tinha pedido pra
 *    deixar fixa de 1,5 g de proteina por quilo de peso pra o protocolo de
 *    recomposição". Weight 100 kg.
 *  - 15/05/2026 08:19, typed: "poderiamos ajustar a meta de proteina do
 *    protocolo de recomposição corporal pra 1,5 g de proteina por kg de peso
 *    do usuario". 08:40, Eduardo: "A — Flat 1,5 pra todos (simples) / B —
 *    Cascata 1,3 a 1,7 (mantém quem treina mais com mais proteína). Qual dos
 *    dois?". 08:41, Roberto: "Mantém 1,5 para todos".
 *  - C3-38, 23/02/2026 21:25:52, over the print of 7:23 PM: "Resumo do seu
 *    protocolo de Recomposição Corporal: / Meta calórica diária: 1.806 kcal /
 *    Meta de proteína: 160 g (2,0 g/kg)". Typed by the client: "Agora ele
 *    mandou a meta de proteína de 160 g, mas tá errada pq ele colocou q fez
 *    2g/kg e meu peso informado foi de 100 kg". Test profile of that day:
 *    musculação 5x, fome pouca, 100 kg.
 *  - C3-37, 23/02/2026 21:22:12, print of 7:20 PM: "• Meta calórica diária:
 *    1806 kcal • Meta de proteína: 0 g".
 *  - Cards and messages after 15/05/2026, the client at 99 kg: "💪 Proteína:
 *    38 / 148g (26%)" (15/05 08:52), "148,5 gramas de proteína" (18/05),
 *    "🎯 Nova meta: 1.946 kcal | 148.5 g de proteína" (04/06).
 *  - Staging `global_config` (read-only, 2026-10-04 ~14:20 BRT): the ten
 *    `calc.*` rows of STAGING_CALC_ROWS; no `calc.recomp_protein_g_per_kg`.
 *  - The view `v_user_metrics` (supabase/migrations/20260501120100_users_core.sql)
 *    maps hunger to `protein_factor` pouca 1.6 / moderada 1.8 / muita 2.0.
 *
 * ASSUMED — declared:
 *  - None of the prints carries height, birth date or activity level. The
 *    profile uses 187 cm, born 1982-01-01, activity 'moderado'. The calorie
 *    numbers of the prints (1914, 1806) are therefore NOT asserted; this file
 *    only asserts that this change does not move the calorie target.
 *  - The hunger level of C5-17 is not in the print. 'moderada' is the level
 *    that reproduces "180 g" for 100 kg and 5 trainings under the staging
 *    cascade, so it is the fixture; every other level is covered next to it.
 *  - C3-38: deficit 600 is today's mapping for 'pouca' (the February mapping is
 *    not in the print). The view rows are fixtures written by hand from the
 *    view's SQL for these profiles.
 *  - Ids are synthetic. The database is an in-memory fake of the statements
 *    the two tools send; any other table or filter fails the test.
 *
 * Declared pendencies (CLAUDE.md criterion 2; same lines in docs/CALCULO-MPP.md §1b):
 *
 * > RC M1 — cenário ganho_massa e manutenção ("Mantém 1,5 para todos", 15/05/2026: o cliente nunca disse se "todos" inclui os outros protocolos) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterados: seguem `calc.protein_factors` (staging 1,6 a 2,0). Travado abaixo e nos goldens audit-10-01-flow-weight-day-target e audit-10-04-whatsapp-context-lock (144 g e 144,9 g), que não foram editados.
 * > RC M1 — cenário protocolo ainda não definido durante o cadastro pelo WhatsApp (cadastra_dados_iniciais antes de define_protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: usa `calc.protein_factors` e o retorno traz o `protein_factor` da view, como no HEAD. Em staging o modelo recebe 200 g com `protein_factor` 1,6 e, depois de escolher recomposição, 150 g (caracterizado abaixo). O 1,6 recebido antes da escolha continua no histórico do turno: o resumo da recomposição escrito em seguida ainda pode citá-lo.
 * > RC M1 — cenário coluna `protein_factor` da view `v_user_metrics` (pouca 1,6 / moderada 1,8 / muita 2,0) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A coluna continua no banco e continua sendo entregue ao modelo em ganho de massa, manutenção, perfil sem protocolo e recomposição com o interruptor desligado, mesmo quando não é o fator da conta (ex.: ganho de massa, fome pouca, 5 treinos: view 1,6, cascata do staging 2,0). Só deixou de ser entregue na recomposição com o fator fixo ligado. Sem migration.
 * > RC M1 — cenário XP do fechamento (`calcDailyXP` recebe a meta de proteína nova: onde `calc.xp_rules` tem a tabela MPP, o bônus "bateu proteína" passa a ser pago em dias em que não era) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O closer não foi tocado e nenhum teste desta PR o exercita. Em staging `calc.xp_rules` é a fórmula antiga (compara com `protein_threshold_g` = 100, não com a meta): sem mudança. Produção não foi lida.
 * > RC M1 — cenário interruptor executado num banco real (o upsert de `calc.recomp_protein_g_per_kg` = 0 em `global_config`) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nenhum banco foi tocado. Aqui só se prova que a linha, uma vez lida pelo carregador real, desliga a regra.
 * > RC M1 — cenário valor de `calc.protein_factors` em PRODUÇÃO NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Não foi lido. Se não estiver em 1,5, a meta de quem está em recomposição muda no deploy.
 * > RC M1 — cenário histórico (metas de proteína já gravadas em `daily_snapshots`, inclusive a do dia da troca) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Sem backfill: card, tela Hoje e Flow seguem a meta já gravada no dia; o número novo vale a partir do primeiro registro de um dia sem meta gravada.
 * > RC M1 — cenário conversa real (o modelo citar um g/kg tirado do roteiro ou das regras gravadas no banco) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Os roteiros ficam no banco; aqui só se prova que nenhuma ferramenta entrega um fator.
 * > RC M1 — cenário altura, idade, atividade e fome reais dos prints C5-17 e C3-38 (e as metas calóricas 1914 e 1806) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Os prints não trazem esses dados.
 */
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache, loadCalcConfig } from '../calc-config-loader.js'
import { loadDailyTargets } from '../calc-targets.js'
import type { PipelineDeps } from '../pipeline.js'
import { processAuthenticatedMessage, processMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import { cadastraDadosIniciais, defineProtocolo, type ToolContext } from '../tools.js'

type Row = Record<string, unknown>
type ConfigRow = { key: string; value: unknown }

const USER_ID = '0b9f6f0e-0000-4000-8000-0000000000a1'
const NOW = new Date('2026-10-04T18:00:00.000Z')

/** `public.global_config` of staging, `calc.*`, as read on 2026-10-04. */
const STAGING_CALC_ROWS: ConfigRow[] = [
  {
    key: 'calc.activity_factors',
    value: { sedentario: 1.2, leve: 1.375, moderado: 1.55, alto: 1.725, atleta: 1.9 },
  },
  {
    key: 'calc.bf_goal_rules',
    value: [
      { above: 30, subtract: 10 },
      { above: 20, target: 20 },
      { above: 18, target: 18 },
      { above: 15, target: 15 },
      { above: 0, target: 10 },
    ],
  },
  {
    key: 'calc.bf_limits',
    value: { feminino: { gain: 27, recomp: 28 }, masculino: { gain: 19, recomp: 20 } },
  },
  { key: 'calc.imc_goal_steps', value: [30, 25, 23, 22, 21] },
  { key: 'calc.imc_limit_recomp', value: 25 },
  { key: 'calc.kcal_block', value: 7700 },
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
  { key: 'calc.sleep_min_hours', value: 6.5 },
  { key: 'calc.training_min', value: 3 },
  {
    key: 'calc.xp_rules',
    value: { base: 10, protein_bonus: 5, training_bonus: 5, protein_threshold_g: 100 },
  },
]

/** The revert switch of M1, as a database row. */
const SWITCH_OFF: ConfigRow = { key: 'calc.recomp_protein_g_per_kg', value: null }
/** The same row with any value, as the loader would read it. */
const switchRow = (value: unknown): ConfigRow => ({ key: 'calc.recomp_protein_g_per_kg', value })
/** The switch as docs/CALCULO-MPP.md §1b recommends writing it: 0. */
const SWITCH_OFF_ZERO = switchRow(0)

// ── In-memory database for cadastra_dados_iniciais and define_protocolo ─────

class FakeDb {
  readonly writes: Array<{ kind: 'upsert' | 'update'; patch: Row }> = []
  profile: Row

  constructor(
    profile: Row,
    private readonly configRows: ConfigRow[] = STAGING_CALC_ROWS,
    /** What `v_user_metrics` returns for this user (a fixture, see header). */
    private readonly viewRow: Row | null = null,
  ) {
    this.profile = { user_id: USER_ID, ...profile }
  }

  from(table: string) {
    if (table === 'global_config') {
      return {
        select: () => ({
          like: async (column: string, pattern: string) => {
            if (column !== 'key' || pattern !== 'calc.%') {
              throw new Error(`unexpected global_config filter ${column} like ${pattern}`)
            }
            return { data: this.configRows, error: null }
          },
        }),
      }
    }
    if (table === 'user_profiles') {
      return {
        select: (columns: string) => ({
          eq: (column: string, value: unknown) => ({
            maybeSingle: async () => {
              if (column !== 'user_id') throw new Error(`unexpected filter ${column}`)
              if (value !== this.profile.user_id) return { data: null, error: null }
              const picked = Object.fromEntries(
                columns.split(',').map((c) => [c.trim(), this.profile[c.trim()] ?? null]),
              )
              return { data: picked, error: null }
            },
          }),
        }),
        upsert: async (values: Row, options: { onConflict: string }) => {
          if (options.onConflict !== 'user_id' || values.user_id !== this.profile.user_id) {
            throw new Error('unexpected upsert target')
          }
          this.writes.push({ kind: 'upsert', patch: values })
          this.profile = { ...this.profile, ...values }
          return { error: null }
        },
        update: (patch: Row) => ({
          eq: async (column: string, value: unknown) => {
            if (column !== 'user_id' || value !== this.profile.user_id) {
              throw new Error(`unexpected update filter ${column}`)
            }
            this.writes.push({ kind: 'update', patch })
            this.profile = { ...this.profile, ...patch }
            return { error: null }
          },
        }),
      }
    }
    if (table === 'v_user_metrics') {
      return {
        select: (columns: string) => ({
          eq: (column: string, value: unknown) => ({
            maybeSingle: async () => {
              if (columns !== '*' || column !== 'user_id' || value !== this.profile.user_id) {
                throw new Error('unexpected v_user_metrics read')
              }
              return { data: this.viewRow, error: null }
            },
          }),
        }),
      }
    }
    throw new Error(`unexpected table ${table}`)
  }
}

function ctxFor(db: FakeDb): ToolContext {
  return {
    supabase: db as unknown as ServiceClient,
    userId: USER_ID,
    userWpp: '5511999990001',
    userTimezone: 'America/Sao_Paulo',
    referenceTimestamp: NOW,
  }
}

/** Runs the tool as the pipeline does: the schema first, then execute. */
function cadastra(db: FakeDb, args: Row) {
  return cadastraDadosIniciais.execute(cadastraDadosIniciais.parameters.parse(args), ctxFor(db))
}
function protocolo(db: FakeDb, args: Row) {
  return defineProtocolo.execute(defineProtocolo.parameters.parse(args), ctxFor(db))
}

/** The real loader + the real target loader, as every tool and surface calls them. */
async function targetsOf(profile: Row, rows: ConfigRow[] = STAGING_CALC_ROWS) {
  clearCalcConfigCache()
  const db = new FakeDb(profile, rows)
  const config = await loadCalcConfig(db)
  return loadDailyTargets(db, USER_ID, config)
}

/** C5-17: 100 kg, recomposição, musculação 5x. Height, birth, activity and hunger: assumed. */
const C5_17: Row = {
  sex: 'masculino',
  birth_date: '1982-01-01',
  height_cm: 187,
  weight_kg: 100,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 5,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'recomposicao',
  goal_type: null,
  goal_value: null,
  deficit_level: 500,
}

/** C3-38: 100 kg, fome pouca, musculação 5x, recomposição. */
const C3_38: Row = { ...C5_17, hunger_level: 'pouca', deficit_level: 600 }

/** What the SQL view returns for C3_38 on 2026-10-04 (hand-written fixture). */
const C3_38_VIEW_ROW: Row = {
  user_id: USER_ID,
  age: 44,
  // Mifflin-St Jeor: 10×100 + 6.25×187 − 5×44 + 5.
  bmr: 1953.75,
  activity_factor: 1.55,
  lbm: 100,
  imc: 28.596757127741714,
  // CASE hunger_level WHEN 'pouca' THEN 1.6 — not the factor of the target.
  protein_factor: 1.6,
}

/** Every number-looking token of a tool result, to prove no factor leaks. */
function numbersIn(value: unknown): number[] {
  const found: number[] = []
  const walk = (v: unknown) => {
    if (typeof v === 'number') found.push(v)
    else if (typeof v === 'string') {
      for (const m of v.match(/\d+(?:[.,]\d+)?/g) ?? []) found.push(Number(m.replace(',', '.')))
    } else if (Array.isArray(v)) v.forEach(walk)
    else if (v && typeof v === 'object') Object.values(v).forEach(walk)
  }
  walk(value)
  return found
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})
afterEach(() => {
  vi.useRealTimers()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})

// ── The configuration the runtime really loads ──────────────────────────────

describe('audit 2026-10-04 — M1: a config do banco de staging', () => {
  it('o loader entrega a cascata 1,6 a 2,0 em protein_factors e 1,5 fixo para a recomposição', async () => {
    const config = await loadCalcConfig(new FakeDb({}))
    expect(config.protein_factors).toEqual({
      muita: 1.6,
      pouca: 1.8,
      moderada: 1.8,
      training_low: 1.7,
      optimal_mid_training: 1.9,
      optimal_high_training: 2,
    })
    expect(config.recomp_protein_g_per_kg).toBe(1.5)
  })
})

// ── C5-17 ───────────────────────────────────────────────────────────────────

describe('audit 2026-10-04 — M1 / C5-17: 100 kg em recomposição, "Meta de proteína: 180 g"', () => {
  it('a meta é 150 g, não 180 g', async () => {
    expect((await targetsOf(C5_17)).protein_target).toBe(150)
  })

  it('a regra anterior (interruptor desligado no banco) reproduz o print: 180 g', async () => {
    const before = await targetsOf(C5_17, [...STAGING_CALC_ROWS, SWITCH_OFF])
    expect(before.protein_target).toBe(180)
    // The calorie target is the same with the switch on or off.
    const after = await targetsOf(C5_17)
    expect(after.calories_target).toBe(before.calories_target)
    // Mifflin-St Jeor 1953.75 × 1.2 − 500 = 1844.5.
    expect(after.calories_target).toBe(1845)
  })

  it('a fome do print não está registrada: com qualquer fome e qualquer treino a meta é 150 g', async () => {
    for (const hunger of ['pouca', 'moderada', 'muita', null]) {
      for (const training of [null, 0, 2, 3, 4, 5, 7]) {
        const targets = await targetsOf({
          ...C5_17,
          hunger_level: hunger,
          training_frequency: training,
        })
        expect(targets.protein_target, `fome ${hunger}, treino ${training}`).toBe(150)
      }
    }
  })

  it('define_protocolo devolve protein_target_today_g = 150 ao escolher recomposição', async () => {
    const db = new FakeDb({ ...C5_17, current_protocol: null, deficit_level: null })
    const result = await protocolo(db, { protocol: 'recomposicao', deficit_level: 500 })

    expect(result).toEqual({
      success: true,
      protocol: 'recomposicao',
      calories_target_today: 1845,
      protein_target_today_g: 150,
      formula_used: 'BMR × 1.2 − 500 kcal (déficit)',
    })
    expect(numbersIn(result)).not.toContain(180)
    expect(db.profile.current_protocol).toBe('recomposicao')
  })

  it('cadastra_dados_iniciais devolve protein_target_today_g = 150 quando o peso de 100 kg é confirmado', async () => {
    const db = new FakeDb({ ...C5_17, weight_kg: 99 }, STAGING_CALC_ROWS, {
      user_id: USER_ID,
      age: 44,
      bmr: 1953.75,
      activity_factor: 1.55,
      lbm: 100,
      imc: 28.596757127741714,
      protein_factor: 1.8,
    })
    const result = await cadastra(db, { weight_kg: 100 })

    expect(result.success).toBe(true)
    expect(result.protein_target_today_g).toBe(150)
    expect(result.calories_target_today).toBe(1845)
    expect(numbersIn(result)).not.toContain(180)
    expect(numbersIn(result)).not.toContain(1.8)
  })
})

// ── C3-38 ───────────────────────────────────────────────────────────────────

describe('audit 2026-10-04 — M1 / C3-38: "160 g (2,0 g/kg)" com 100 kg — o fator dito tem de ser o da conta', () => {
  it('cadastra_dados_iniciais: a view devolve protein_factor 1.6 e o retorno da ferramenta não o contém', async () => {
    const db = new FakeDb(C3_38, STAGING_CALC_ROWS, C3_38_VIEW_ROW)
    const result = await cadastra(db, { weight_kg: 100, hunger_level: 'pouca' })

    expect(result).toEqual({
      success: true,
      updated_fields: ['weight_kg', 'hunger_level', 'updated_at'],
      metrics: {
        user_id: USER_ID,
        age: 44,
        bmr: 1953.75,
        activity_factor: 1.55,
        lbm: 100,
        imc: 28.596757127741714,
      },
      // Mifflin-St Jeor 1953.75 × 1.2 − 600 = 1744.5.
      calories_target_today: 1745,
      protein_target_today_g: 150,
    })
    expect(result.metrics).not.toHaveProperty('protein_factor')
    expect(JSON.stringify(result)).not.toContain('protein_factor')
    // No g/kg reaches the model: neither the view's 1.6, nor the cascade's 2.0,
    // nor the grams they would give (160 and 200).
    const numbers = numbersIn(result)
    for (const stale of [1.6, 2, 160, 200]) expect(numbers).not.toContain(stale)
    // The fixture row itself was not mutated.
    expect(C3_38_VIEW_ROW.protein_factor).toBe(1.6)
  })

  it('define_protocolo: 150 g e nenhum fator de proteína no retorno', async () => {
    const db = new FakeDb({ ...C3_38, current_protocol: null, deficit_level: null })
    const result = await protocolo(db, { protocol: 'recomposicao', deficit_level: 600 })

    expect(result).toEqual({
      success: true,
      protocol: 'recomposicao',
      calories_target_today: 1745,
      protein_target_today_g: 150,
      formula_used: 'BMR × 1.2 − 600 kcal (déficit)',
    })
    const numbers = numbersIn(result)
    for (const stale of [1.6, 2, 160, 200]) expect(numbers).not.toContain(stale)
  })

  it('a regra anterior (interruptor desligado) dava 200 g com a cascata — nem 160 g, nem "2,0 g/kg" do print', async () => {
    expect((await targetsOf(C3_38, [...STAGING_CALC_ROWS, SWITCH_OFF])).protein_target).toBe(200)
    expect((await targetsOf(C3_38)).protein_target).toBe(150)
  })

  it('a view sem linha (perfil novo): metrics é null e a meta continua 150 g', async () => {
    const db = new FakeDb(C3_38, STAGING_CALC_ROWS, null)
    const result = await cadastra(db, { weight_kg: 100 })
    expect(result.metrics).toBeNull()
    expect(result.protein_target_today_g).toBe(150)
  })

  // One switch for the whole rule: with it off the tool returns what HEAD
  // returned — the cascade's grams and the view's row, key by key.
  it.each([
    ['0 (recomendado)', SWITCH_OFF_ZERO],
    ['null', SWITCH_OFF],
  ])('interruptor desligado (linha = %s): cadastra_dados_iniciais devolve o retorno do HEAD, com protein_factor 1.6 e 200 g', async (_label, off) => {
    const db = new FakeDb(C3_38, [...STAGING_CALC_ROWS, off], C3_38_VIEW_ROW)
    const result = await cadastra(db, { weight_kg: 100, hunger_level: 'pouca' })

    expect(result).toEqual({
      success: true,
      updated_fields: ['weight_kg', 'hunger_level', 'updated_at'],
      metrics: {
        user_id: USER_ID,
        age: 44,
        bmr: 1953.75,
        activity_factor: 1.55,
        lbm: 100,
        imc: 28.596757127741714,
        protein_factor: 1.6,
      },
      calories_target_today: 1745,
      protein_target_today_g: 200,
    })
  })
})

// ── The database row of the factor: bounds (review of 2026-10-04) ───────────

describe('audit 2026-10-04 — M1: a linha calc.recomp_protein_g_per_kg lida pelo carregador real', () => {
  // The reviewer's profile: recomposição, 100 kg, fome pouca, 5 treinos, the
  // staging cascade (C3_38). `before` is what the first version of M1 gave.
  it.each([
    // [linha, antes, agora, valor]
    ['99', 9900, 150, 99],
    ['1e9', 100000000000, 150, 1e9],
    ['texto "1.5"', 200, 150, '1.5'],
    ['texto "0"', 200, 150, '0'],
    ['-1', 200, 150, -1],
    ['3.01', 301, 150, 3.01],
    ['true', 200, 150, true],
    ['{"value":1.5}', 200, 150, { value: 1.5 }],
  ])('linha = %s: fora da faixa ou de outro tipo → padrão do código (era %s g, agora %s g)', async (_label, _before, expected, value) => {
    const targets = await targetsOf(C3_38, [...STAGING_CALC_ROWS, switchRow(value)])
    expect(targets.protein_target).toBe(expected)
    expect(targets.calories_target).toBe(1745)
  })

  it.each([
    ['null', null],
    ['0', 0],
  ])('linha = %s: interruptor explícito → a cascata do staging, 200 g', async (_label, value) => {
    const targets = await targetsOf(C3_38, [...STAGING_CALC_ROWS, switchRow(value)])
    expect(targets.protein_target).toBe(200)
    expect(targets.calories_target).toBe(1745)
  })

  it.each([
    [1.2, 120],
    [1.5, 150],
    [3, 300],
  ])('linha = %s (número em 0 < v ≤ 3) troca o fator → %s g', async (value, expected) => {
    expect((await targetsOf(C3_38, [...STAGING_CALC_ROWS, switchRow(value)])).protein_target).toBe(
      expected,
    )
  })

  it('uma linha inválida não desliga a regra na ferramenta: 150 g e sem protein_factor', async () => {
    const db = new FakeDb(C3_38, [...STAGING_CALC_ROWS, switchRow('1.5')], C3_38_VIEW_ROW)
    const result = await cadastra(db, { weight_kg: 100, hunger_level: 'pouca' })
    expect(result.protein_target_today_g).toBe(150)
    expect(result.metrics).not.toHaveProperty('protein_factor')
  })
})

// ── C3-37 ───────────────────────────────────────────────────────────────────

describe('audit 2026-10-04 — M1 / C3-37: "Meta de proteína: 0 g"', () => {
  it('perfil sem peso: a ferramenta devolve null, nunca 0', async () => {
    const db = new FakeDb({ ...C5_17, weight_kg: null })
    const result = await cadastra(db, { hunger_level: 'moderada' })
    expect(result.protein_target_today_g).toBeNull()
    expect(result.calories_target_today).toBeNull()
  })

  it('com os 100 kg gravados em recomposição: 150 g', async () => {
    const db = new FakeDb({ ...C5_17, weight_kg: null })
    const result = await cadastra(db, { weight_kg: 100 })
    expect(result.protein_target_today_g).toBe(150)
  })
})

// ── The client at 99 kg, May–June 2026 ──────────────────────────────────────

describe('audit 2026-10-04 — M1: 99 kg em recomposição → 148,5 g ("148.5 g de proteína", 04/06/2026)', () => {
  const ROBERTO_99: Row = { ...C5_17, weight_kg: 99 }

  it('com a linha em cascata do staging', async () => {
    expect((await targetsOf(ROBERTO_99)).protein_target).toBe(148.5)
  })

  it('sem nenhuma linha calc.* (padrão do código)', async () => {
    expect((await targetsOf(ROBERTO_99, [])).protein_target).toBe(148.5)
  })

  it('62,5 kg → 93,8 g', async () => {
    expect((await targetsOf({ ...C5_17, weight_kg: 62.5 })).protein_target).toBe(93.8)
  })
})

// ── What did NOT change ─────────────────────────────────────────────────────

describe('audit 2026-10-04 — M1: ganho de massa, manutenção e protocolo não definido seguem calc.protein_factors', () => {
  /** QA A (staging): the profile of audit-10-01-flow-weight-day-target. */
  const QA_A: Row = {
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

  it.each([
    // [caso, perfil, meta de proteína de sempre]
    ['QA A, ganho de massa, 80 kg (01/10/2026)', QA_A, 144],
    ['QA A, ganho de massa, 80,5 kg (04/10/2026)', { ...QA_A, weight_kg: 80.5 }, 144.9],
    ['QA A, ganho de massa, 103,4 kg (snapshot de 01/10)', { ...QA_A, weight_kg: 103.4 }, 186.1],
    ['manutenção, 100 kg, pouca, 5x', { ...C3_38, current_protocol: 'manutencao' }, 200],
    [
      'protocolo não definido, 100 kg, moderada, 4x',
      { ...C5_17, current_protocol: null, training_frequency: 4 },
      180,
    ],
  ])('%s → %s g, com o interruptor ligado ou desligado', async (_label, profile, expected) => {
    expect((await targetsOf(profile)).protein_target).toBe(expected)
    expect((await targetsOf(profile, [...STAGING_CALC_ROWS, SWITCH_OFF])).protein_target).toBe(
      expected,
    )
  })

  it('define_protocolo com ganho de massa, 80 kg: 144 g, como antes', async () => {
    const db = new FakeDb({ ...QA_A, current_protocol: null })
    const result = await protocolo(db, { protocol: 'ganho_massa' })
    expect(result.protein_target_today_g).toBe(144)
  })

  /** What the view returns for QA_A (the reviewer's fixture: imc 23.37, factor 1.8). */
  const QA_A_VIEW_ROW: Row = {
    user_id: USER_ID,
    age: 26,
    // Mifflin-St Jeor: 10×80 + 6.25×185 − 5×26 + 5.
    bmr: 1831.25,
    activity_factor: 1.55,
    lbm: 80,
    imc: 23.37,
    // CASE hunger_level WHEN 'moderada' THEN 1.8.
    protein_factor: 1.8,
  }

  // Review of 2026-10-04 (protein lens, MEDIUM): the tool's return for ganho
  // de massa is the one of HEAD, with the switch off (the reviewer's input)
  // and with it on.
  it.each([
    ['desligado, linha = null (entrada do revisor)', [...STAGING_CALC_ROWS, SWITCH_OFF]],
    ['desligado, linha = 0', [...STAGING_CALC_ROWS, SWITCH_OFF_ZERO]],
    ['ligado, sem linha', STAGING_CALC_ROWS],
    ['ligado, sem nenhuma linha calc.*', []],
  ])('cadastra_dados_iniciais em ganho de massa, 80 kg, interruptor %s: metrics com protein_factor 1.8, como no HEAD', async (label, rows) => {
    const db = new FakeDb(QA_A, rows, QA_A_VIEW_ROW)
    const result = await cadastra(db, { weight_kg: 80 })

    expect(result).toEqual({
      success: true,
      updated_fields: ['weight_kg', 'updated_at'],
      metrics: {
        user_id: USER_ID,
        age: 26,
        bmr: 1831.25,
        activity_factor: 1.55,
        lbm: 80,
        imc: 23.37,
        protein_factor: 1.8,
      },
      // 1831.25 × 1.55 × 1.05 = 2980.36.
      calories_target_today: 2980,
      // Staging cascade: 80 × 1.8. Code default (no calc.* row): 80 × 1.5.
      protein_target_today_g: label.includes('nenhuma') ? 120 : 144,
    })
    expect(QA_A_VIEW_ROW.protein_factor).toBe(1.8)
  })

  it.each([
    ['manutencao', { ...C3_38, current_protocol: 'manutencao', deficit_level: null }],
    ['protocolo não definido', { ...C3_38, current_protocol: null, deficit_level: null }],
  ])('cadastra_dados_iniciais em %s: metrics é a linha da view inteira, com o interruptor ligado ou desligado', async (_label, profile) => {
    for (const rows of [STAGING_CALC_ROWS, [...STAGING_CALC_ROWS, SWITCH_OFF_ZERO]]) {
      clearCalcConfigCache()
      const result = await cadastra(new FakeDb(profile, rows, C3_38_VIEW_ROW), { weight_kg: 100 })
      expect(result.metrics).toEqual(C3_38_VIEW_ROW)
      expect(result.protein_target_today_g).toBe(200)
    }
  })

  // Declared pendency: during the sign-up the protocol is still null, so the
  // first number follows the database cascade and the view's factor is handed
  // over as on HEAD; after the choice the target is the fixed 1.5 and a new
  // call of the tool no longer carries the factor.
  it('caracterização: cadastro pelo WhatsApp sem protocolo → 200 g com protein_factor 1.6; depois de escolher recomposição → 150 g sem ele', async () => {
    const db = new FakeDb(
      { ...C3_38, current_protocol: null, deficit_level: null },
      STAGING_CALC_ROWS,
      C3_38_VIEW_ROW,
    )
    const signUp = await cadastra(db, { weight_kg: 100 })
    expect(signUp.protein_target_today_g).toBe(200)
    expect(signUp.metrics).toEqual(C3_38_VIEW_ROW)

    const chosen = await protocolo(db, { protocol: 'recomposicao', deficit_level: 600 })
    expect(chosen.protein_target_today_g).toBe(150)

    const afterChoice = await cadastra(db, { weight_kg: 100 })
    expect(afterChoice.protein_target_today_g).toBe(150)
    expect(afterChoice.metrics).not.toHaveProperty('protein_factor')
  })
})

// ── The line the patient's model reads ──────────────────────────────────────

interface Turn {
  deps: PipelineDeps
  prompts: string[]
}

function flattenSystemPrompt(value: unknown): string {
  if (typeof value === 'string') return value
  if (!Array.isArray(value)) return ''
  return value
    .map((part) =>
      typeof part === 'object' && part !== null && 'text' in part
        ? String((part as { text: unknown }).text)
        : '',
    )
    .join('')
}

/** Pipeline harness of the 2026-10-04 goldens, reduced to what a turn reads. */
function turn(provider: 'whatsapp' | 'mobile_flow', profile: Row, configRows: ConfigRow[]): Turn {
  const prompts: string[] = []
  const rowsFor = (table: string, filters: Row): unknown => {
    switch (table) {
      case 'users':
        return {
          id: USER_ID,
          name: 'Roberto',
          summary: null,
          last_active_at: null,
          country: 'BR',
          country_confirmed: true,
          country_detected_from_wpp: null,
          locale: 'pt-BR',
          metadata: null,
          timezone: 'America/Sao_Paulo',
        }
      case 'user_profiles':
        return profile
      case 'user_progress':
        return {
          current_streak: 0,
          longest_streak: 0,
          xp_total: 0,
          level: 1,
          blocks_completed: 0,
          deficit_block: 0,
          last_active_date: null,
        }
      case 'messages':
        return [
          {
            direction: 'in',
            content: 'Qual é a minha meta de proteína?',
            content_type: 'text',
            created_at: NOW.toISOString(),
            provider,
            provider_message_id: 'audit-10-04-protein-recomp',
          },
        ]
      case 'daily_snapshots':
        // No snapshot of the day: both channels fall on the live profile target.
        return filters.day_closed === true ? [] : null
      case 'global_config':
        return filters.key === 'router.haiku_enabled' ? null : configRows
      case 'v_active_prompts':
        return {
          stage: filters.stage ?? 'recomposicao',
          model: 'anthropic/claude-sonnet-4.6',
          temperature: 0,
          max_tokens: 512,
          system_prompt: 'REGRAS COMPARTILHADAS',
          allowed_tools: null,
        }
      default:
        return []
    }
  }

  const supabase = {
    from(table: string) {
      const filters: Row = {}
      const result = () => ({ data: rowsFor(table, filters), error: null })
      const one = async () => {
        const { data } = result()
        return { data: Array.isArray(data) ? (data[0] ?? null) : data, error: null }
      }
      const chain = Promise.resolve().then(result) as Promise<{ data: unknown; error: null }> &
        Record<string, unknown>
      for (const method of [
        'select',
        'neq',
        'gte',
        'lte',
        'lt',
        'gt',
        'in',
        'is',
        'like',
        'ilike',
        'or',
        'not',
        'order',
        'limit',
        'insert',
        'update',
        'upsert',
        'delete',
      ]) {
        chain[method] = () => chain
      }
      chain.eq = (key: string, value: unknown) => {
        filters[key] = value
        return chain
      }
      chain.single = one
      chain.maybeSingle = one
      return chain
    },
    rpc: async (name: string) => ({
      data: name === 'match_method_chunks' ? [] : USER_ID,
      error: null,
    }),
  } as unknown as PipelineDeps['supabase']

  const llm = {
    complete: async (input: { systemPrompt: unknown }) => {
      prompts.push(flattenSystemPrompt(input.systemPrompt))
      return {
        content: 'Resposta do modelo.',
        toolCalls: [],
        model: 'anthropic/claude-sonnet-4.6',
        promptTokens: 1000,
        completionTokens: 10,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']

  return { deps: { supabase, llm, maxToolIterations: 3 }, prompts }
}

async function proteinLine(
  provider: 'whatsapp' | 'mobile_flow',
  profile: Row,
  rows: ConfigRow[] = STAGING_CALC_ROWS,
): Promise<string[]> {
  clearCalcConfigCache()
  const t = turn(provider, profile, rows)
  if (provider === 'whatsapp') {
    await processMessage(t.deps, {
      from: '5511999990001',
      providerMessageId: 'audit-10-04-protein-recomp',
      text: 'Qual é a minha meta de proteína?',
      contentType: 'text',
      provider: 'whatsapp',
      timestamp: NOW,
    })
  } else {
    await processAuthenticatedMessage(t.deps, {
      userId: USER_ID,
      providerMessageId: 'audit-10-04-protein-recomp',
      text: 'Qual é a minha meta de proteína?',
      timestamp: NOW,
    })
  }
  const lines = (t.prompts[0] ?? '').split('\n')
  expect(lines).toContain('- Peso: 100 kg')
  return lines.filter((line) => line.startsWith('- Meta de proteína de hoje:'))
}

describe('audit 2026-10-04 — M1 / C5-17: a linha "Meta de proteína de hoje" do contexto do turno', () => {
  it('WhatsApp, 100 kg em recomposição: 150 g (antes 180 g)', async () => {
    expect(await proteinLine('whatsapp', C5_17)).toEqual(['- Meta de proteína de hoje: **150 g**'])
  })

  it('Flow do app, mesmo perfil, dia sem meta gravada: a mesma linha', async () => {
    expect(await proteinLine('mobile_flow', C5_17)).toEqual([
      '- Meta de proteína de hoje: **150 g**',
    ])
  })

  it('C3-38 (fome pouca, 5x): 150 g nos dois canais (a cascata daria 200 g)', async () => {
    expect(await proteinLine('whatsapp', C3_38)).toEqual(['- Meta de proteína de hoje: **150 g**'])
    expect(await proteinLine('mobile_flow', C3_38)).toEqual([
      '- Meta de proteína de hoje: **150 g**',
    ])
  })

  it('interruptor desligado no banco: a linha volta a 180 g nos dois canais', async () => {
    const off = [...STAGING_CALC_ROWS, SWITCH_OFF]
    expect(await proteinLine('whatsapp', C5_17, off)).toEqual([
      '- Meta de proteína de hoje: **180 g**',
    ])
    expect(await proteinLine('mobile_flow', C5_17, off)).toEqual([
      '- Meta de proteína de hoje: **180 g**',
    ])
  })

  it('ganho de massa, 100 kg, mesma fome e treino: a linha continua 180 g (não mudou)', async () => {
    expect(await proteinLine('whatsapp', { ...C5_17, current_protocol: 'ganho_massa' })).toEqual([
      '- Meta de proteína de hoje: **180 g**',
    ])
  })
})
