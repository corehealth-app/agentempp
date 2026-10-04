/**
 * Golden — composition goals: the BMI first-goal ladder (R3) and the safety
 * floors of a declared goal (R4). Audit of the client's WhatsApp group,
 * 2026-10-04. Rule and worked numbers: docs/CALCULO-MPP.md §8.
 *
 * STATUS OF THE RULES (never a new decision of the client):
 *  - R3: dito pelo cliente em 26/01/2026 (texto) e no manual 9.4.3.1;
 *    implementado em 2026-10-04 a pedido do Eduardo; confirmação do cliente
 *    pendente. Em 07/02/2026 ele escreveu "10 pontos" uma vez (conflito aberto).
 *  - R4 gordura: dito pelo cliente em 28/12/2025 (texto) e no manual 9.3;
 *    implementado em 2026-10-04 a pedido do Eduardo; confirmação pendente.
 *  - R4 peso/IMC: dito pelo cliente em 09/06/2026 (texto e manual 3.5), depois
 *    de aprovar o aviso em 01/06/2026; implementado em 2026-10-04 a pedido do
 *    Eduardo; confirmação pendente.
 *
 * READ FROM THE GROUP (not invented):
 *  - C3-03, 07/02/2026 13:39:22, and C2-49, 25/01/2026 09:36:53: test profile
 *    without photos, BMI 32.7. Prints: "Sua meta de IMC é reduzir para 30.0
 *    (uma redução de aproximadamente 2.7 pontos)" and "Meta de IMC: Reduzir de
 *    32.7 para 30.0".
 *  - C2-50, 26/01/2026 09:01:12: BMI 30.1, print "Meta de IMC: 30.0 (redução
 *    de ~0.1 ponto)".
 *  - Client's manual 9.4.3.1: "IMC 35 → 30, IMC 34 → 29, IMC 31 → 26".
 *  - 28/12/2025 14:55:27, typed: "não é possível reduzir para menos de 10% de
 *    gordura corporal no nosso sistema, pq teoricamente não é saudável".
 *  - 09/06/2026 18:22, typed: "esses valores muito abaixo não podemos fazer".
 *  - Staging `global_config` (read-only, 2026-10-04 ~14:20 BRT): the ten
 *    `calc.*` rows of STAGING_CALC_ROWS, and no `calc.imc_goal_step_points`.
 *
 * ASSUMED — declared:
 *  - The prints of BMI 32.7 carry no weight or height. The context test uses
 *    100 kg and 175 cm (BMI 32.65, shown as 32.7); the birth date, the
 *    activity level and the rest of that profile are invented.
 *  - R4 has no patient print. The body-fat and weight scenarios are the ones
 *    recomputed in the audit on commit cf89221 (before this change):
 *      man 12% asking 7%  → "Meta saudável: 7% (abaixo dos 12% atuais, delta
 *                            5pp). No ritmo seguro de ~0.5pp/semana, ~10
 *                            semanas. Boa meta — vamos focar." and goal 7 saved;
 *      man 8% asking 7%   → 'maintenance', goal 7 saved;
 *      man 8% asking 5%   → "Meta saudável: 5% … Boa meta — vamos focar.", saved;
 *      man 8% asking 4%   → "Cuidado — 4% está ABAIXO do limite essencial pra
 *                            homem (mínimo 5%) … Faz sentido revisar a meta?",
 *                            and saved anyway;
 *      55 kg → 48 kg, 170 cm → "… Sugiro ajustar a meta pra algo entre 53.5 e
 *                            72kg — quer rever?", and saved anyway.
 *  - Reproduced by the adversarial review of 2026-10-04 on the first version
 *    of this change (tool and pipeline run with a fake database; no print):
 *      54 kg → 53 kg, 170 cm      → 'maintenance', goal 53 saved (raw BMI 18.34);
 *      40 kg → 39.3 kg, 160 cm    → 'maintenance', goal 39.3 saved (BMI 15.35);
 *      55 kg → 53.4 kg, 170 cm    → "Ótima meta — IMC 18.5 cai bem na faixa
 *                                   saudável", goal 53.4 saved (raw BMI 18.478);
 *      70 kg → 66.7 kg, 190 cm    → the same (raw BMI 18.476); 66.6 kg refused;
 *      man 12% asking 9.96%       → refused, text "10% fica abaixo de 10%";
 *      woman 22% asking 9%        → define_meta_peso offered "a partir de 12%",
 *                                   define_protocolo "a partir de 10%";
 *      175 cm, 50 kg, define_protocolo{ganho_massa, IMC, 18} → goal dropped,
 *                                   while define_meta_peso{55.1} saves it;
 *      reassessment, "Peso 79 kg, fome moderada, não vou mandar fotos. Minha
 *      meta agora é 7% de gordura" → one model call, "Reavaliação concluída ✅",
 *                                   no word about the refusal, goal BF 15 erased.
 *    The height of 170 cm is a premise (09/06/2026 gave no height). Ids,
 *    dates of birth, the previous goals and the measurement date are synthetic.
 *  - The database is an in-memory fake of the three statements these tools
 *    send (`user_profiles` select/update by user_id, `global_config` select
 *    like 'calc.%'). Any other table or filter fails the test.
 *
 * Declared pendencies (CLAUDE.md criterion 2; same lines in docs/CALCULO-MPP.md §8):
 *
 * > RC R3 — cenário passo de 10 pontos ("perder 10 pontos do imc", texto de 07/02/2026) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Implementado o passo de 5 (26/01/2026 e manual). 32.7 daria 25 com passo 10; é uma troca de valor.
 * > RC R3 — cenário metas de IMC já gravadas com 30 NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Sem backfill: seguem no banco e na pergunta da reavaliação.
 * > RC R3 — cenário IMC de 25,0 a 25,9 (manual: meta 25; código: 23) e normalidade "menor que 25" / "IMC < 24" NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: margem de 1 ponto e alvo 25.
 * > RC R3 — cenário IMC de 30,95 a 30,99 (mostrado como 31.0) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Muda de 25 para 26 (acompanha o valor mostrado); travado em packages/core/tests/protocol-router.test.ts, sem relato de paciente.
 * > RC R3 — cenário peso e altura reais dos prints C3-03, C2-49 e C2-50 NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Os prints só trazem o IMC.
 * > RC R4 — cenário paciente que JÁ está abaixo do piso (gordura ≤ 10% ou IMC < 18,5) seguir em recomposição com déficit NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Manual 3.5 e 9.3; exige mexer no cadastro do app (RPC e contrato).
 * > RC R4 — cenário C3-05 (09/02/2026: gordura 12%, IMC 25.7, "Meta de BF definida: 10%" antes de escolher protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC R4 — cenário meta em kg que implica gordura abaixo de 10% (homem de 80 kg com 12% pedindo 76 kg) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Continua "Ótima meta" e grava.
 * > RC R4 — cenário metas já gravadas abaixo do piso NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Sem backfill: seguem no banco e na pergunta da reavaliação.
 * > RC R4 — cenário piso feminino (mulher pedindo de 10% a 11,9%) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O cliente nunca disse piso separado para mulher. O 12% é valor do código: continua aviso e grava (caso abaixo). A recusa abaixo de 10% oferece "a partir de 12%" para não contradizer esse aviso.
 * > RC R4 — cenário meta de peso que ainda deixa o IMC abaixo de 18,5 GANHANDO peso (45 → 48 kg) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: avisa e grava (caso abaixo).
 * > RC R4 — cenário meta de peso IGUAL ao peso atual, ou ganhando menos de 2% do peso, de quem já está abaixo de 18,5 (52 → 52 kg e 52 → 52,5 kg, 170 cm) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: 'maintenance' e grava (caso abaixo). PERDENDO, qualquer variação é recusada (54 → 53, 52 → 51,5, 40 → 39,3).
 * > RC R4 — cenário define_protocolo com meta de IMC abaixo de 18,5 de quem está GANHANDO peso (175 cm, 50 kg, ganho_massa, IMC 18) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A ferramenta não lê altura nem peso atual: descarta QUALQUER meta de IMC abaixo de 18,5 (o protocolo é gravado). A mesma pessoa em define_meta_peso (55,1 kg, ganhando) tem a meta gravada com aviso (caso abaixo).
 * > RC R4 — cenário meta de peso GANHANDO com IMC bruto de 18,45 a 18,499 (50 → 53,4 kg, 170 cm) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Muda: era "Ótima meta — IMC 18.5", agora o aviso "IMC 18.4, abaixo do saudável … quer rever?"; continua gravada. Travado em weight-goal-classifier.test.ts; sem relato de paciente.
 * > RC R4 — cenário recusa da meta na reavaliação com fotos corporais ainda pendentes, e a redação do modelo nesse turno NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O golden cobre o turno "não vou mandar fotos": o modelo recebe o goal_message e redige; o que ele escreve não é testado. Com fotos pendentes, o texto fixo "ainda falta foto …" também deixa de sair nesse turno (o modelo redige).
 * > RC R4 — cenário define_protocolo com meta abaixo do piso quando já existe meta gravada NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A meta anterior é apagada (null), como já acontece quando a meta é omitida; define_meta_peso, ao recusar, não toca na anterior.
 * > RC R4 — cenário escada automática dar 10% a mulher com até 15% de gordura, e 20% a mulher fora da normalidade (manual de 22/05/2026: ≤ 27%) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC R4 — cenário conversa real depois da recusa (o modelo dizer que registrou ou repetir a chamada) e redação da recusa aprovada pelo cliente (manual 3.5.2) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Os roteiros de cadastro e reavaliação ficam no banco; não há teste de conversa.
 * > RC R4 — cenário turno em que define_protocolo ou define_meta_peso gravou e o modelo TAMBÉM afirma uma refeição ou treino sem chamar a tool ("Almoço registrado … 521 kcal", sem o card "Total refeição") NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nesse turno a regra genérica do guard de escrita fantasma não dispara mais; o card "Total refeição", a proposta imitada, os bullets com kcal e o "pulei" continuam disparando (fake-write-detector.test.ts). Sem relato de paciente.
 */
import {
  calcIMCGoal,
  computeMetrics,
  imcGoalStepPoints,
  resolveProtocol,
  type UserProfile,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache, loadCalcConfig } from '../calc-config-loader.js'
import type { PipelineDeps } from '../pipeline.js'
import { processAuthenticatedMessage, processMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import { defineMetaPeso, defineProtocolo, type ToolContext } from '../tools.js'

type Row = Record<string, unknown>
type ConfigRow = { key: string; value: unknown }

const USER_ID = '0b9f6f0e-0000-4000-8000-0000000000c3'
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

/** The revert switch of R3, as a database row. */
const SWITCH_OFF: ConfigRow = { key: 'calc.imc_goal_step_points', value: null }

// ── In-memory database for the two tools ────────────────────────────────────

type ProfileUpdate = { patch: Row; userId: unknown }

class FakeDb {
  readonly updates: ProfileUpdate[] = []
  profile: Row

  constructor(
    profile: Row,
    private readonly configRows: ConfigRow[] = STAGING_CALC_ROWS,
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
            return { data: this.configRows.filter((r) => r.key.startsWith('calc.')), error: null }
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
        update: (patch: Row) => ({
          eq: async (column: string, value: unknown) => {
            if (column !== 'user_id') throw new Error(`unexpected filter ${column}`)
            this.updates.push({ patch, userId: value })
            if (value === this.profile.user_id) this.profile = { ...this.profile, ...patch }
            return { error: null }
          },
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
    userWpp: '5511999990003',
    userTimezone: 'America/Sao_Paulo',
    referenceTimestamp: NOW,
  }
}

/** Runs the tool as the pipeline does: the schema first, then execute. */
function metaPeso(db: FakeDb, args: Row) {
  return defineMetaPeso.execute(defineMetaPeso.parameters.parse(args), ctxFor(db))
}
function protocolo(db: FakeDb, args: Row) {
  return defineProtocolo.execute(defineProtocolo.parameters.parse(args), ctxFor(db))
}

const MAN: Row = {
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: 12,
  // Measured 4 days before the turn: not stale, so no extra warning field.
  body_fat_measured_at: '2026-09-30T18:00:00.000Z',
  updated_at: '2026-09-30T18:00:00.000Z',
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'recomposicao',
  deficit_level: 500,
  // The goal the patient already had (synthetic).
  goal_type: 'BF',
  goal_value: 15,
}

const WOMAN: Row = {
  ...MAN,
  sex: 'feminino',
  height_cm: 165,
  weight_kg: 62,
  body_fat_percent: 22,
  goal_type: 'BF',
  goal_value: 20,
}

const refusalText = (alvo: number, offerFrom: number) =>
  `Não registrei essa meta: ${alvo}% fica abaixo de 10% de gordura corporal, que é o limite inferior seguro do método. ` +
  'O método não reduz a gordura corporal abaixo de 10%. Nada mudou no seu cadastro. ' +
  `Posso registrar uma meta a partir de ${offerFrom}%. Qual você prefere?`

beforeEach(() => {
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})
afterEach(() => {
  vi.useRealTimers()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})

// ── R4: define_meta_peso, body fat ──────────────────────────────────────────

describe('audit 2026-10-04 — R4: meta de gordura abaixo de 10% não é gravada', () => {
  it('homem com 12% pedindo 7%: recusada, nada escrito, a meta anterior (15%) fica', async () => {
    const db = new FakeDb(MAN)
    const result = await metaPeso(db, { target_bf_percent: 7 })

    expect(result).toEqual({
      success: false,
      refused: true,
      goal_saved: false,
      reason: 'gordura_abaixo_do_piso',
      goal_type: 'BF',
      target_bf_percent: 7,
      classification: 'unhealthy_low',
      bf_atual: 12,
      bf_alvo: 7,
      bf_piso_metodo: 10,
      bf_minimo_saudavel: 10,
      direction: 'perder',
      delta_pp: 5,
      message_template: refusalText(7, 10),
    })
    // Before: "Meta saudável: 7% … Boa meta — vamos focar." and goal_value 7.
    expect(String(result.message_template)).not.toMatch(/Boa meta|Meta saudável|vamos focar/)
    expect(db.updates).toEqual([])
    expect(db.profile.goal_type).toBe('BF')
    expect(db.profile.goal_value).toBe(15)
  })

  it.each([
    // [alvo, o que a ferramenta fazia antes]
    [7, "'maintenance': gravava 7 e falava em Manutenção"],
    [5, '"Meta saudável: 5% … Boa meta — vamos focar." e gravava'],
    [4, '"Cuidado — 4% está ABAIXO do limite essencial … revisar a meta?" e gravava mesmo assim'],
  ])('homem com 8%% pedindo %s%%: recusada, nada escrito (antes: %s)', async (alvo) => {
    const db = new FakeDb({ ...MAN, body_fat_percent: 8 })
    const result = await metaPeso(db, { target_bf_percent: alvo })

    expect(result.success).toBe(false)
    expect(result.refused).toBe(true)
    expect(result.goal_saved).toBe(false)
    expect(result.reason).toBe('gordura_abaixo_do_piso')
    expect(result.message_template).toBe(refusalText(alvo, 10))
    expect(String(result.message_template)).not.toMatch(/Manutenção|Boa meta|revisar a meta/)
    expect(db.updates).toEqual([])
    expect(db.profile.goal_value).toBe(15)
  })

  it.each([
    [12, 10, 2, 4],
    [15, 10, 5, 10],
  ])('homem com %s%% pedindo %s%%: aceita no piso e gravada, como antes', async (atual, alvo, delta, semanas) => {
    const db = new FakeDb({ ...MAN, body_fat_percent: atual })
    const result = await metaPeso(db, { target_bf_percent: alvo })

    expect(result).toEqual({
      success: true,
      goal_type: 'BF',
      target_bf_percent: alvo,
      classification: 'ideal',
      bf_atual: atual,
      bf_alvo: alvo,
      // The only field of an accepted goal that changed: it was 5.
      bf_minimo_saudavel: 10,
      bf_recomp_limit: 20,
      semanas_para_meta_ritmo_seguro: semanas,
      direction: 'perder',
      delta_pp: delta,
      message_template:
        `Meta saudável: ${alvo}% (abaixo dos ${atual}% atuais, delta ${delta}pp). ` +
        `No ritmo seguro de ~0.5pp/semana, ~${semanas} semanas. Boa meta — vamos focar.`,
      bf_atual_stale: false,
      bf_atual_idade_dias: 4,
    })
    expect(db.updates).toEqual([
      {
        userId: USER_ID,
        patch: { goal_type: 'BF', goal_value: alvo, updated_at: NOW.toISOString() },
      },
    ])
    expect(db.profile.goal_value).toBe(alvo)
  })

  // Review of 2026-10-04, LOW: the text said "10% fica abaixo de 10%".
  it.each([
    [9.95],
    [9.96],
    [9.99],
    [9.999],
  ])('homem com 12%% pedindo %s%%: recusada, e o texto mostra 9.9%%, nunca "10%% fica abaixo de 10%%"', async (alvo) => {
    const db = new FakeDb(MAN)
    const result = await metaPeso(db, { target_bf_percent: alvo })

    expect(result).toEqual({
      success: false,
      refused: true,
      goal_saved: false,
      reason: 'gordura_abaixo_do_piso',
      goal_type: 'BF',
      target_bf_percent: alvo,
      classification: 'unhealthy_low',
      bf_atual: 12,
      bf_alvo: 9.9,
      bf_piso_metodo: 10,
      bf_minimo_saudavel: 10,
      direction: 'perder',
      delta_pp: 2.1,
      message_template: refusalText(9.9, 10),
    })
    expect(db.updates).toEqual([])
    expect(db.profile.goal_value).toBe(15)
  })

  it('mulher com 22% pedindo 9%: recusada, nada escrito, a meta anterior (20%) fica', async () => {
    const db = new FakeDb(WOMAN)
    const result = await metaPeso(db, { target_bf_percent: 9 })

    expect(result).toEqual({
      success: false,
      refused: true,
      goal_saved: false,
      reason: 'gordura_abaixo_do_piso',
      goal_type: 'BF',
      target_bf_percent: 9,
      classification: 'unhealthy_low',
      bf_atual: 22,
      bf_alvo: 9,
      bf_piso_metodo: 10,
      bf_minimo_saudavel: 12,
      direction: 'perder',
      delta_pp: 13,
      message_template: refusalText(9, 12),
    })
    expect(db.updates).toEqual([])
    expect(db.profile.goal_value).toBe(20)
  })

  // Pending question, not a rule of the client: the 12% of the code stays a
  // warning. Byte for byte what the tool returned before this change.
  it('mulher com 22% pedindo 11%: inalterado — aviso de hoje e meta gravada', async () => {
    const db = new FakeDb(WOMAN)
    const result = await metaPeso(db, { target_bf_percent: 11 })

    expect(result).toEqual({
      success: true,
      goal_type: 'BF',
      target_bf_percent: 11,
      classification: 'unhealthy_low',
      bf_atual: 22,
      bf_alvo: 11,
      bf_minimo_saudavel: 12,
      bf_recomp_limit: 28,
      semanas_para_meta_ritmo_seguro: null,
      direction: 'perder',
      delta_pp: 11,
      message_template:
        'Cuidado — 11% está ABAIXO do limite essencial pra mulher (mínimo 12%). ' +
        'Perder gordura abaixo desse limite compromete hormônios, recuperação muscular e saúde geral. ' +
        'Sugiro mirar pelo menos 15% — ainda atlético, mas seguro. Faz sentido revisar a meta?',
      bf_atual_stale: false,
      bf_atual_idade_dias: 4,
    })
    expect(db.updates).toEqual([
      {
        userId: USER_ID,
        patch: { goal_type: 'BF', goal_value: 11, updated_at: NOW.toISOString() },
      },
    ])
  })
})

// ── R4: define_meta_peso, weight ────────────────────────────────────────────

describe('audit 2026-10-04 — R4: meta de peso que deixa o IMC abaixo de 18,5', () => {
  const THIN: Row = {
    ...MAN,
    height_cm: 170,
    weight_kg: 55,
    body_fat_percent: null,
    goal_type: 'peso_kg',
    goal_value: 54,
  }

  it('55 kg → 48 kg, 170 cm (perdendo): recusada, nada escrito, faixa saudável no texto', async () => {
    const db = new FakeDb(THIN)
    const result = await metaPeso(db, { target_weight_kg: 48 })

    expect(result).toEqual({
      success: false,
      refused: true,
      goal_saved: false,
      reason: 'peso_abaixo_do_minimo_saudavel',
      goal_type: 'peso_kg',
      target_weight_kg: 48,
      classification: 'unhealthy_low',
      imc_atual: 19,
      imc_alvo: 16.6,
      peso_minimo_saudavel_kg: 53.5,
      peso_maximo_saudavel_kg: 72,
      direction: 'perder',
      delta_kg: 7,
      message_template:
        'Essa meta (48kg) te deixaria com IMC 16.6, abaixo do saudável (mínimo OMS é 18.5). ' +
        'Pra sua altura, o peso mínimo saudável é 53.5kg. ' +
        'Por segurança, não registrei essa meta e nada mudou no seu cadastro. ' +
        'Posso registrar uma meta entre 53.5 e 72kg. Qual você prefere?',
    })
    expect(db.updates).toEqual([])
    expect(db.profile.goal_type).toBe('peso_kg')
    expect(db.profile.goal_value).toBe(54)
  })

  it('45 kg → 48 kg, 170 cm (ganhando): inalterado — aviso de hoje e meta gravada', async () => {
    const db = new FakeDb({ ...THIN, weight_kg: 45, goal_type: null, goal_value: null })
    const result = await metaPeso(db, { target_weight_kg: 48 })

    expect(result).toEqual({
      success: true,
      goal_type: 'peso_kg',
      target_weight_kg: 48,
      classification: 'unhealthy_low',
      imc_atual: 15.6,
      imc_alvo: 16.6,
      peso_minimo_saudavel_kg: 53.5,
      peso_maximo_saudavel_kg: 72,
      semanas_para_meta_ritmo_seguro: null,
      direction: 'ganhar',
      delta_kg: 3,
      message_template:
        'Essa meta (48kg) te deixaria com IMC 16.6, abaixo do saudável (mínimo OMS é 18.5). ' +
        'Pra sua altura, o peso mínimo saudável é 53.5kg. ' +
        'Sugiro ajustar a meta pra algo entre 53.5 e 72kg — quer rever?',
    })
    expect(db.updates).toEqual([
      {
        userId: USER_ID,
        patch: { goal_type: 'peso_kg', goal_value: 48, updated_at: NOW.toISOString() },
      },
    ])
  })

  it('55 kg → 53.5 kg, 170 cm (IMC alvo 18.5, no piso): aceita e gravada, como antes', async () => {
    const db = new FakeDb(THIN)
    const result = await metaPeso(db, { target_weight_kg: 53.5 })

    expect(result.success).toBe(true)
    expect(result).not.toHaveProperty('refused')
    expect(result.imc_alvo).toBe(18.5)
    expect(db.updates).toHaveLength(1)
    expect(db.profile.goal_value).toBe(53.5)
  })

  // Review of 2026-10-04, HIGH. The "manter" band (a change under 2% of the
  // weight) ran before the floor: the tool answered "Beleza — manter o peso
  // atual. Vou ajustar pro protocolo de Manutenção…" and saved the goal.
  it('54 kg → 53 kg, 170 cm (perde menos de 2%, IMC 18,7 → 18,3): recusada, nada escrito', async () => {
    const db = new FakeDb({ ...THIN, weight_kg: 54, goal_value: 54 })
    const result = await metaPeso(db, { target_weight_kg: 53 })

    expect(result).toEqual({
      success: false,
      refused: true,
      goal_saved: false,
      reason: 'peso_abaixo_do_minimo_saudavel',
      goal_type: 'peso_kg',
      target_weight_kg: 53,
      classification: 'unhealthy_low',
      imc_atual: 18.7,
      imc_alvo: 18.3,
      peso_minimo_saudavel_kg: 53.5,
      peso_maximo_saudavel_kg: 72,
      direction: 'perder',
      delta_kg: 1,
      message_template:
        'Essa meta (53kg) te deixaria com IMC 18.3, abaixo do saudável (mínimo OMS é 18.5). ' +
        'Pra sua altura, o peso mínimo saudável é 53.5kg. ' +
        'Por segurança, não registrei essa meta e nada mudou no seu cadastro. ' +
        'Posso registrar uma meta entre 53.5 e 72kg. Qual você prefere?',
    })
    expect(String(result.message_template)).not.toMatch(/manter|Manutenção/)
    expect(db.updates).toEqual([])
    expect(db.profile.goal_value).toBe(54)
  })

  it('40 kg → 39.3 kg, 160 cm (já abaixo de 18,5, perde menos de 2%): recusada, nada escrito', async () => {
    const db = new FakeDb({ ...THIN, height_cm: 160, weight_kg: 40, goal_value: 40 })
    const result = await metaPeso(db, { target_weight_kg: 39.3 })

    expect(result).toMatchObject({
      success: false,
      refused: true,
      goal_saved: false,
      reason: 'peso_abaixo_do_minimo_saudavel',
      classification: 'unhealthy_low',
      imc_atual: 15.6,
      imc_alvo: 15.4,
      peso_minimo_saudavel_kg: 47.4,
      direction: 'perder',
    })
    expect(db.updates).toEqual([])
    expect(db.profile.goal_value).toBe(40)
  })

  it('52 kg → 51.5 kg, 170 cm (era pendência declarada: "manter" e gravava): recusada, nada escrito', async () => {
    const db = new FakeDb({ ...THIN, weight_kg: 52, goal_value: 52 })
    const result = await metaPeso(db, { target_weight_kg: 51.5 })

    expect(result).toMatchObject({
      success: false,
      refused: true,
      goal_saved: false,
      imc_alvo: 17.8,
    })
    expect(db.updates).toEqual([])
    expect(db.profile.goal_value).toBe(52)
  })

  // Review of 2026-10-04, HIGH. The floor judged the BMI rounded to one
  // decimal: 53.4 / 1.70² = 18.478 became 18.5 and the tool answered "Ótima
  // meta — IMC 18.5 cai bem na faixa saudável" while quoting 53.5 kg as the
  // minimum healthy weight.
  it.each([
    // [altura, atual, alvo, IMC atual mostrado, mínimo, máximo, delta]
    [170, 55, 53.4, 19, 53.5, 72, 1.6],
    [190, 70, 66.7, 19.4, 66.8, 89.9, 3.3],
  ])('%s cm, %s kg → %s kg (IMC bruto 18,48): recusada, nada escrito, e o texto mostra IMC 18.4', async (altura, atual, alvo, imcAtual, min, max, delta) => {
    const db = new FakeDb({ ...THIN, height_cm: altura, weight_kg: atual, goal_value: atual })
    const result = await metaPeso(db, { target_weight_kg: alvo })

    expect(result).toEqual({
      success: false,
      refused: true,
      goal_saved: false,
      reason: 'peso_abaixo_do_minimo_saudavel',
      goal_type: 'peso_kg',
      target_weight_kg: alvo,
      classification: 'unhealthy_low',
      imc_atual: imcAtual,
      imc_alvo: 18.4,
      peso_minimo_saudavel_kg: min,
      peso_maximo_saudavel_kg: max,
      direction: 'perder',
      delta_kg: delta,
      message_template:
        `Essa meta (${alvo}kg) te deixaria com IMC 18.4, abaixo do saudável (mínimo OMS é 18.5). ` +
        `Pra sua altura, o peso mínimo saudável é ${min}kg. ` +
        'Por segurança, não registrei essa meta e nada mudou no seu cadastro. ' +
        `Posso registrar uma meta entre ${min} e ${max}kg. Qual você prefere?`,
    })
    expect(String(result.message_template)).not.toMatch(/Ótima meta|IMC 18\.5/)
    expect(db.updates).toEqual([])
    expect(db.profile.goal_value).toBe(atual)

    // The minimum the refusal offers is itself accepted and saved.
    const offered = await metaPeso(db, { target_weight_kg: min })
    expect(offered).toMatchObject({ success: true, classification: 'ideal', imc_alvo: 18.5 })
    expect(offered).not.toHaveProperty('refused')
    expect(db.updates).toEqual([
      {
        userId: USER_ID,
        patch: { goal_type: 'peso_kg', goal_value: min, updated_at: NOW.toISOString() },
      },
    ])
  })

  it('190 cm, 70 kg → 66.6 kg (IMC bruto 18,45): recusada como antes desta correção', async () => {
    const db = new FakeDb({ ...THIN, height_cm: 190, weight_kg: 70, goal_value: 70 })
    const result = await metaPeso(db, { target_weight_kg: 66.6 })
    expect(result).toMatchObject({ success: false, refused: true, imc_alvo: 18.4 })
    expect(db.updates).toEqual([])
  })

  it('150 cm: o mínimo oferecido é 41.7 kg (41.6 kg é IMC 18,49 e a própria tool recusa)', async () => {
    const db = new FakeDb({ ...THIN, height_cm: 150, weight_kg: 45, goal_value: 45 })
    const refused = await metaPeso(db, { target_weight_kg: 41.6 })
    expect(refused).toMatchObject({ refused: true, peso_minimo_saudavel_kg: 41.7 })
    expect(db.updates).toEqual([])

    const accepted = await metaPeso(db, { target_weight_kg: 41.7 })
    expect(accepted).toMatchObject({ success: true, imc_alvo: 18.5 })
    expect(db.profile.goal_value).toBe(41.7)
  })

  // Declared pendency: a goal EQUAL to the current weight is not a loss.
  it('52 kg → 52 kg, 170 cm (meta igual ao peso atual, IMC 18,0): inalterado — "manter" e gravada', async () => {
    const db = new FakeDb({ ...THIN, weight_kg: 52, goal_type: null, goal_value: null })
    const result = await metaPeso(db, { target_weight_kg: 52 })

    expect(result).toMatchObject({
      success: true,
      classification: 'maintenance',
      direction: 'manter',
      imc_alvo: 18,
      message_template:
        'Beleza — manter o peso atual. Vou ajustar pro protocolo de Manutenção, onde o foco é estabilidade e composição corporal (mais músculo, menos gordura).',
    })
    expect(result).not.toHaveProperty('refused')
    expect(db.profile.goal_value).toBe(52)
  })
})

// ── R4: define_protocolo never loses the protocol ───────────────────────────

describe('audit 2026-10-04 — R4: define_protocolo grava o protocolo e descarta só a meta abaixo do piso', () => {
  const ONBOARDING: Row = {
    ...MAN,
    current_protocol: null,
    deficit_level: null,
    goal_type: null,
    goal_value: null,
  }

  it('recomposição com meta BF 7: protocolo e déficit gravados, meta não', async () => {
    const db = new FakeDb(ONBOARDING)
    const result = await protocolo(db, {
      protocol: 'recomposicao',
      deficit_level: 500,
      goal_type: 'BF',
      goal_value: 7,
    })

    expect(db.updates).toEqual([
      {
        userId: USER_ID,
        patch: {
          current_protocol: 'recomposicao',
          deficit_level: 500,
          goal_type: null,
          goal_value: null,
          updated_at: NOW.toISOString(),
        },
      },
    ])
    expect(db.profile.current_protocol).toBe('recomposicao')
    expect(db.profile.deficit_level).toBe(500)

    // The same call with the goal omitted: what the tool has always returned.
    const plain = new FakeDb(ONBOARDING)
    const baseline = await protocolo(plain, { protocol: 'recomposicao', deficit_level: 500 })
    expect(plain.updates).toEqual(db.updates)
    expect(baseline).toEqual({
      success: true,
      protocol: 'recomposicao',
      // Katch-McArdle: 370 + 21.6 × (80 kg × 0.88) = 1890.64; × 1.2 − 500 = 1768.77.
      calories_target_today: 1769,
      // 80 kg × 1.5 g/kg: recomposição is fixed (rule M1, docs/CALCULO-MPP.md
      // §1b). It was 144 (× 1.8, staging `calc.protein_factors`) until M1.
      protein_target_today_g: 120,
      formula_used: 'BMR × 1.2 − 500 kcal (déficit)',
    })

    expect(result).toEqual({
      ...baseline,
      goal_saved: false,
      goal_refused_reason: 'gordura_abaixo_do_piso',
      goal_type_refused: 'BF',
      goal_value_refused: 7,
      goal_floor: 10,
      goal_message:
        'Protocolo registrado. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, ' +
        'que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere?',
    })
  })

  it('meta no piso ou acima é gravada e o retorno é o de sempre (BF 10, BF 15, IMC 18.5, IMC 23)', async () => {
    for (const [goalType, goalValue] of [
      ['BF', 10],
      ['BF', 15],
      ['IMC', 18.5],
      ['IMC', 23],
    ] as const) {
      const db = new FakeDb(ONBOARDING)
      const result = await protocolo(db, {
        protocol: 'recomposicao',
        deficit_level: 500,
        goal_type: goalType,
        goal_value: goalValue,
      })
      expect(db.updates[0]?.patch).toMatchObject({ goal_type: goalType, goal_value: goalValue })
      expect(Object.keys(result).sort()).toEqual(
        [
          'calories_target_today',
          'formula_used',
          'protein_target_today_g',
          'protocol',
          'success',
        ].sort(),
      )
    }
  })

  it('meta de IMC 18 (abaixo de 18,5): protocolo gravado, meta não', async () => {
    const db = new FakeDb({ ...ONBOARDING, body_fat_percent: null })
    const result = await protocolo(db, {
      protocol: 'recomposicao',
      deficit_level: 400,
      goal_type: 'IMC',
      goal_value: 18,
    })

    expect(db.updates[0]?.patch).toEqual({
      current_protocol: 'recomposicao',
      deficit_level: 400,
      goal_type: null,
      goal_value: null,
      updated_at: NOW.toISOString(),
    })
    expect(result).toMatchObject({
      success: true,
      protocol: 'recomposicao',
      // Mifflin-St Jeor (no body fat): 10×80 + 6.25×180 − 5×36 + 5 = 1750; × 1.2 − 400.
      calories_target_today: 1700,
      goal_saved: false,
      goal_refused_reason: 'imc_abaixo_do_minimo_saudavel',
      goal_floor: 18.5,
      goal_message:
        'Protocolo registrado. A meta de IMC 18 não foi registrada: fica abaixo do saudável (mínimo OMS é 18.5). ' +
        'Posso registrar uma meta de IMC a partir de 18.5. Qual você prefere?',
    })
  })

  it('ganho de massa com meta BF 7: baseline do ciclo capturado como sempre, meta não', async () => {
    const db = new FakeDb(ONBOARDING)
    const result = await protocolo(db, { protocol: 'ganho_massa', goal_type: 'BF', goal_value: 7 })

    expect(db.updates[0]?.patch).toEqual({
      current_protocol: 'ganho_massa',
      deficit_level: null,
      goal_type: null,
      goal_value: null,
      updated_at: NOW.toISOString(),
      cycle_start_weight_kg: 80,
      cycle_start_bf_percent: 12,
      cycle_start_training_freq: 4,
      cycle_start_at: NOW.toISOString(),
    })
    expect(result).toMatchObject({ success: true, protocol: 'ganho_massa', goal_saved: false })
  })

  // Review of 2026-10-04, LOW: for a woman this tool offered "a partir de
  // 10%" and define_meta_peso "a partir de 12%". Same offer now.
  it('mulher, recomposição com meta BF 9: as duas ferramentas oferecem a mesma coisa (a partir de 12%)', async () => {
    const db = new FakeDb({ ...WOMAN, goal_type: null, goal_value: null })
    const viaProtocolo = await protocolo(db, {
      protocol: 'recomposicao',
      deficit_level: 500,
      goal_type: 'BF',
      goal_value: 9,
    })
    expect(db.profile.current_protocol).toBe('recomposicao')
    expect(db.profile.goal_value).toBeNull()
    expect(viaProtocolo).toMatchObject({
      success: true,
      goal_saved: false,
      goal_floor: 10,
      goal_message:
        'Protocolo registrado. A meta de 9% de gordura corporal não foi registrada: fica abaixo de 10%, ' +
        'que é o limite inferior seguro do método. Posso registrar uma meta a partir de 12%. Qual você prefere?',
    })

    const viaMetaPeso = await metaPeso(new FakeDb(WOMAN), { target_bf_percent: 9 })
    const offer = 'Posso registrar uma meta a partir de 12%. Qual você prefere?'
    expect(String(viaMetaPeso.message_template).endsWith(offer)).toBe(true)
    expect(String(viaProtocolo.goal_message).endsWith(offer)).toBe(true)
  })

  it('sexo ausente no perfil: o protocolo é gravado e a oferta cai no piso do método (10%)', async () => {
    const db = new FakeDb({ ...ONBOARDING, sex: null })
    const result = await protocolo(db, {
      protocol: 'recomposicao',
      deficit_level: 500,
      goal_type: 'BF',
      goal_value: 7,
    })
    expect(db.profile.current_protocol).toBe('recomposicao')
    expect(String(result.goal_message)).toContain('Posso registrar uma meta a partir de 10%.')
  })

  // Declared pendency (review of 2026-10-04, LOW): this tool reads neither the
  // height nor the current weight, so it drops an IMC goal under 18.5 also for
  // someone GAINING weight; define_meta_peso, for the same person, saves it.
  it('caracterização: 175 cm, 50 kg (IMC 16,3), ganho de massa com meta IMC 18 — descartada aqui, gravada com aviso em define_meta_peso (55.1 kg)', async () => {
    const UNDERWEIGHT: Row = {
      ...ONBOARDING,
      height_cm: 175,
      weight_kg: 50,
      body_fat_percent: null,
    }
    const db = new FakeDb(UNDERWEIGHT)
    const result = await protocolo(db, {
      protocol: 'ganho_massa',
      goal_type: 'IMC',
      goal_value: 18,
    })

    expect(db.updates[0]?.patch).toEqual({
      current_protocol: 'ganho_massa',
      deficit_level: null,
      goal_type: null,
      goal_value: null,
      updated_at: NOW.toISOString(),
      cycle_start_weight_kg: 50,
      cycle_start_bf_percent: null,
      cycle_start_training_freq: 4,
      cycle_start_at: NOW.toISOString(),
    })
    expect(result).toMatchObject({
      success: true,
      protocol: 'ganho_massa',
      goal_saved: false,
      goal_refused_reason: 'imc_abaixo_do_minimo_saudavel',
      goal_message:
        'Protocolo registrado. A meta de IMC 18 não foi registrada: fica abaixo do saudável (mínimo OMS é 18.5). ' +
        'Posso registrar uma meta de IMC a partir de 18.5. Qual você prefere?',
    })

    const other = new FakeDb(UNDERWEIGHT)
    const viaMetaPeso = await metaPeso(other, { target_weight_kg: 55.1 })
    expect(viaMetaPeso).toMatchObject({
      success: true,
      classification: 'unhealthy_low',
      direction: 'ganhar',
      imc_atual: 16.3,
      imc_alvo: 18,
    })
    expect(viaMetaPeso).not.toHaveProperty('refused')
    expect(other.profile.goal_value).toBe(55.1)
  })

  // Declared pendency: the previous goal is cleared, as when the goal is omitted.
  it('caracterização: com meta anterior gravada, a meta abaixo do piso apaga a anterior (como a meta omitida)', async () => {
    const db = new FakeDb(MAN)
    await protocolo(db, {
      protocol: 'recomposicao',
      deficit_level: 500,
      goal_type: 'BF',
      goal_value: 7,
    })
    expect(db.profile.goal_type).toBeNull()
    expect(db.profile.goal_value).toBeNull()

    const omitted = new FakeDb(MAN)
    await protocolo(omitted, { protocol: 'recomposicao', deficit_level: 500 })
    expect(omitted.profile.goal_type).toBeNull()
    expect(omitted.profile.goal_value).toBeNull()
  })
})

// ── The text the model reads about the tools ────────────────────────────────

describe('audit 2026-10-04 — R4: a descrição das ferramentas diz que a meta abaixo do piso não é gravada', () => {
  it('define_meta_peso', () => {
    const d = defineMetaPeso.description
    expect(d).toContain('Abaixo de 10% a tool NÃO grava')
    expect(d).toContain('refused=true')
    expect(d).toContain('goal_saved=false')
    expect(d).toContain('IMC abaixo de 18,5')
    // The old text told the model the range went down to 3%.
    expect(d).not.toContain('Faixa 3-50')
  })

  it('define_protocolo', () => {
    const d = defineProtocolo.description
    expect(d).toContain('BF abaixo de 10% ou IMC abaixo de 18,5 NÃO é gravado como meta')
    expect(d).toContain('goal_saved=false')
  })
})

// ── R3: the ladder, with the configuration the runtime really loads ─────────

function configClient(rows: ConfigRow[]) {
  return new FakeDb({}, rows)
}

describe('audit 2026-10-04 — R3: primeira meta de IMC com a config do banco de staging', () => {
  it('sem linha para a chave nova, o loader entrega passo 5 e os degraus [30, 25, 23, 22, 21]', async () => {
    const config = await loadCalcConfig(configClient(STAGING_CALC_ROWS))
    expect(config.imc_goal_steps).toEqual([30, 25, 23, 22, 21])
    expect(config.imc_limit_recomp).toBe(25)
    expect(config.imc_goal_step_points).toBe(5)
  })

  it.each([
    // [IMC, meta, origem]
    [32.7, 27.7, 'C3-03 e C2-49: o print dizia 30.0'],
    [30.1, 25, 'C2-50: o print dizia 30.0'],
    [35, 30, 'manual 9.4.3.1'],
    [34, 29, 'manual 9.4.3.1'],
    [31, 26, 'manual 9.4.3.1'],
    [36, 31, 'derivado'],
    [45, 40, 'derivado'],
    [27, 25, 'derivado'],
    [25.4, 23, 'derivado'],
    [25.0, 23, 'derivado'],
  ])('IMC %s → meta %s (%s)', async (imc, goal) => {
    const config = await loadCalcConfig(configClient(STAGING_CALC_ROWS))
    expect(calcIMCGoal(imc, config)).toBe(goal)
  })

  it('C3-03: IMC 32.7 sem gordura no perfil → meta de IMC 27.7, nunca 30; recomposição sem escolha', async () => {
    const config = await loadCalcConfig(configClient(STAGING_CALC_ROWS))
    const profile: UserProfile = {
      sex: 'masculino',
      birthDate: new Date('1990-01-01'),
      heightCm: 175,
      weightKg: 100,
      bodyFatPercent: null,
      activityLevel: 'moderado',
      trainingFrequency: 4,
      waterIntake: 'moderado',
      hungerLevel: 'moderada',
      currentProtocol: null,
      goalType: null,
      goalValue: null,
      deficitLevel: null,
      bedTime: '23:00',
      wakeTime: '07:00',
      foodOrganization: 'sim',
    }
    const metrics = computeMetrics(profile, NOW, config)
    expect(metrics.imc?.toFixed(1)).toBe('32.7')

    expect(resolveProtocol(profile, metrics, config)).toEqual({
      protocol: 'recomposicao',
      canChoose: false,
      blockers: ['IMC acima do limite saudável para ganho de massa'],
      goalType: 'IMC',
      goalValue: 27.7,
    })
  })

  it('interruptor: a linha calc.imc_goal_step_points = null devolve a escada anterior, sem deploy', async () => {
    const config = await loadCalcConfig(configClient([...STAGING_CALC_ROWS, SWITCH_OFF]))
    expect(config.imc_goal_step_points).toBeNull()
    expect(calcIMCGoal(32.7, config)).toBe(30)
    expect(calcIMCGoal(31, config)).toBe(30)
    expect(calcIMCGoal(45, config)).toBe(30)
    expect(calcIMCGoal(30.1, config)).toBe(25)
    expect(calcIMCGoal(25.4, config)).toBe(23)
  })

  it('interruptor: a linha com o número 0 também devolve a escada anterior', async () => {
    const config = await loadCalcConfig(
      configClient([...STAGING_CALC_ROWS, { key: 'calc.imc_goal_step_points', value: 0 }]),
    )
    expect(calcIMCGoal(32.7, config)).toBe(30)
    expect(calcIMCGoal(45, config)).toBe(30)
  })

  // Second review of 2026-10-04 (LOW), the reviewer's exact row: the staging
  // rows plus calc.imc_goal_step_points = the TEXT "5". The loader copies the
  // value as it is; before this fix calcIMCGoal and resolveProtocol came out
  // identical to commit 9624cd5 (32.7 → 30), with no error and no log. The
  // other values are the same typing mistakes `fixedRecompProteinFactor`
  // already refuses for the protein row (synthetic).
  it.each([
    ['o texto "5" (linha do revisor)', '5'],
    ['o texto "cinco"', 'cinco'],
    ['texto vazio', ''],
    ['-5', -5],
    ['50 (acima do limite de digitação, 20)', 50],
    ['true', true],
    ['objeto', { points: 5 }],
  ])('linha calc.imc_goal_step_points com %s: a regra continua ligada com o padrão do código (32.7 → 27.7, nunca 30)', async (_label, value) => {
    const config = await loadCalcConfig(
      configClient([...STAGING_CALC_ROWS, { key: 'calc.imc_goal_step_points', value }]),
    )
    // The loader does not clean the row: the reader does.
    expect(config.imc_goal_step_points).toEqual(value)
    expect(imcGoalStepPoints(config)).toBe(5)
    expect(calcIMCGoal(32.7, config)).toBe(27.7)
    expect(calcIMCGoal(31, config)).toBe(26)
    expect(calcIMCGoal(45, config)).toBe(40)
    expect(calcIMCGoal(30.1, config)).toBe(25)

    const profile: UserProfile = {
      sex: 'masculino',
      birthDate: new Date('1990-01-01'),
      heightCm: 175,
      weightKg: 100,
      bodyFatPercent: null,
      activityLevel: 'moderado',
      trainingFrequency: 4,
      waterIntake: 'moderado',
      hungerLevel: 'moderada',
      currentProtocol: null,
      goalType: null,
      goalValue: null,
      deficitLevel: null,
      bedTime: '23:00',
      wakeTime: '07:00',
      foodOrganization: 'sim',
    }
    expect(resolveProtocol(profile, computeMetrics(profile, NOW, config), config)).toMatchObject({
      protocol: 'recomposicao',
      goalType: 'IMC',
      goalValue: 27.7,
    })
  })

  it('linha com um número em (0, 20]: é o passo (10 → 32.7 vira 25; 45 vira 35)', async () => {
    const config = await loadCalcConfig(
      configClient([...STAGING_CALC_ROWS, { key: 'calc.imc_goal_step_points', value: 10 }]),
    )
    expect(imcGoalStepPoints(config)).toBe(10)
    expect(calcIMCGoal(32.7, config)).toBe(25)
    expect(calcIMCGoal(45, config)).toBe(35)
  })
})

// ── R3: the only place the patient's model reads the goal ───────────────────

/** Profile behind the context test: 100 kg, 175 cm (assumed; BMI shown 32.7). */
const PROFILE_IMC_32_7: Row = {
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 175,
  weight_kg: 100,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'recomposicao',
  goal_type: null,
  goal_value: null,
  deficit_level: 500,
}

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
function turn(provider: 'whatsapp' | 'mobile_flow', configRows: ConfigRow[]): Turn {
  const prompts: string[] = []
  const rowsFor = (table: string, filters: Row): unknown => {
    switch (table) {
      case 'users':
        return {
          id: USER_ID,
          name: 'Luan',
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
        return PROFILE_IMC_32_7
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
            content: 'Qual é a minha meta?',
            content_type: 'text',
            created_at: NOW.toISOString(),
            provider,
            provider_message_id: 'audit-10-04-goal-ladder',
          },
        ]
      case 'daily_snapshots':
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

async function decisionLine(
  provider: 'whatsapp' | 'mobile_flow',
  rows: ConfigRow[],
): Promise<string> {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  const t = turn(provider, rows)
  if (provider === 'whatsapp') {
    await processMessage(t.deps, {
      from: '5511999990003',
      providerMessageId: 'audit-10-04-goal-ladder',
      text: 'Qual é a minha meta?',
      contentType: 'text',
      provider: 'whatsapp',
      timestamp: NOW,
    })
  } else {
    await processAuthenticatedMessage(t.deps, {
      userId: USER_ID,
      providerMessageId: 'audit-10-04-goal-ladder',
      text: 'Qual é a minha meta?',
      timestamp: NOW,
    })
  }
  const lines = (t.prompts[0] ?? '').split('\n')
  expect(lines).toContain('- IMC: 32.7')
  return lines.find((line) => line.startsWith('- Decisão automática:')) ?? ''
}

describe('audit 2026-10-04 — R3: a linha "Decisão automática" do contexto do turno', () => {
  const LINE = (goal: string) =>
    `- Decisão automática: protocol=recomposicao canChoose=false blockers=[IMC acima do limite saudável para ganho de massa] goal=IMC=${goal}`

  it('WhatsApp, IMC 32.7 sem gordura: goal=IMC=27.7 (antes 30)', async () => {
    expect(await decisionLine('whatsapp', STAGING_CALC_ROWS)).toBe(LINE('27.7'))
  })

  it('Flow do app, mesmo perfil: a mesma linha', async () => {
    expect(await decisionLine('mobile_flow', STAGING_CALC_ROWS)).toBe(LINE('27.7'))
  })

  it('interruptor desligado no banco: a linha volta a goal=IMC=30 nos dois canais', async () => {
    expect(await decisionLine('whatsapp', [...STAGING_CALC_ROWS, SWITCH_OFF])).toBe(LINE('30'))
    clearCalcConfigCache()
    expect(await decisionLine('mobile_flow', [...STAGING_CALC_ROWS, SWITCH_OFF])).toBe(LINE('30'))
  })
})

// ── R4: the refusal reaches the patient at reassessment (WhatsApp) ──────────
//
// Review of 2026-10-04, MEDIUM. At reassessment the pipeline answers a turn
// made only of cadastra_dados_iniciais / define_protocolo with a fixed text
// and no second model call. A goal dropped by define_protocolo came back as
// success:true + goal_saved:false, counted as a plain success, and the patient
// read "Reavaliação concluída ✅" while the previous goal was erased.
//
// The patient's sentence is the reviewer's reproduction (no print exists):
// man, 80 kg, 12% body fat, saved goal BF 15, `reevaluation.due` in the last
// 48 h. The model's two tool calls are scripted; everything else is the real
// pipeline and the real tools.

const REEVAL_TEXT =
  'Peso 79 kg, fome moderada, não vou mandar fotos. Minha meta agora é 7% de gordura'
const MODEL_ANSWER = 'RESPOSTA REDIGIDA PELO MODELO'

interface ScriptedToolCall {
  id: string
  name: string
  arguments: string
}

interface ReevalTurn {
  deps: PipelineDeps
  /** `messages` of every model call, as the model received them. */
  modelCalls: Array<Array<{ role?: string; content?: unknown }>>
  /** `event` of every row inserted in `product_events`, in order. */
  events: string[]
  profile: () => Row
}

/** The first model call returns `toolCalls` (when there are any); every other
 * call returns `answer`. */
function reevalTurn(
  text: string,
  toolCalls: ScriptedToolCall[],
  reevaluationDue: boolean,
  answer: string = MODEL_ANSWER,
): ReevalTurn {
  let profile: Row = {
    ...MAN,
    user_id: USER_ID,
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    onboarding_completed: true,
  }
  const modelCalls: ReevalTurn['modelCalls'] = []
  const events: string[] = []

  const rowsFor = (table: string, filters: Row): unknown => {
    switch (table) {
      case 'users':
        return {
          id: USER_ID,
          name: 'Luan',
          summary: null,
          last_active_at: null,
          country: 'BR',
          country_confirmed: true,
          country_detected_from_wpp: null,
          locale: 'pt-BR',
          metadata: null,
          timezone: 'America/Sao_Paulo',
          status: 'active',
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
            content: text,
            content_type: 'text',
            created_at: NOW.toISOString(),
            provider: 'whatsapp',
            provider_message_id: 'audit-10-04-reeval',
          },
        ]
      case 'daily_snapshots':
        return filters.day_closed === true ? [] : null
      case 'global_config':
        return filters.key === 'router.haiku_enabled' ? null : STAGING_CALC_ROWS
      case 'product_events':
        return reevaluationDue && filters.event === 'reevaluation.due'
          ? [{ id: 1, occurred_at: NOW.toISOString(), properties: {} }]
          : []
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
        'delete',
      ]) {
        chain[method] = () => chain
      }
      chain.insert = (row: Row | Row[]) => {
        if (table === 'product_events') {
          for (const r of Array.isArray(row) ? row : [row]) events.push(String(r.event))
        }
        return chain
      }
      // cadastra_dados_iniciais upserts the profile; define_protocolo updates it.
      const write = (patch: Row) => {
        if (table === 'user_profiles') profile = { ...profile, ...patch }
        return chain
      }
      chain.update = write
      chain.upsert = write
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
    complete: async (input: { messages: ReevalTurn['modelCalls'][number] }) => {
      modelCalls.push(input.messages.map((m) => ({ ...m })))
      const first = modelCalls.length === 1 && toolCalls.length > 0
      return {
        content: first ? '' : answer,
        toolCalls: first ? toolCalls : [],
        model: 'anthropic/claude-sonnet-4.6',
        promptTokens: 1000,
        completionTokens: 10,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']

  return {
    deps: { supabase, llm, maxToolIterations: 3 },
    modelCalls,
    events,
    profile: () => profile,
  }
}

const CADASTRA_CALL: ScriptedToolCall = {
  id: 't1',
  name: 'cadastra_dados_iniciais',
  arguments: JSON.stringify({ weight_kg: 79, hunger_level: 'moderada' }),
}
const protocoloCall = (goal: Row): ScriptedToolCall => ({
  id: 't2',
  name: 'define_protocolo',
  arguments: JSON.stringify({ protocol: 'recomposicao', deficit_level: 500, ...goal }),
})

async function runReeval(t: ReevalTurn, text: string) {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  return processMessage(t.deps, {
    from: '5511999990003',
    providerMessageId: 'audit-10-04-reeval',
    text,
    contentType: 'text',
    provider: 'whatsapp',
    timestamp: NOW,
  })
}

/** The fixed reassessment text for this profile at 79 kg (unchanged by the
 * floor work). Katch-McArdle: 370 + 21.6 × (79 × 0.88) = 1871.63; × 1.2 − 500
 * = 1745.96. Protein: 79 kg × 1.5 g/kg (rule M1, docs/CALCULO-MPP.md §1b). */
const REEVAL_DONE =
  'Reavaliação concluída ✅\n\n' +
  '🎯 Nova meta: **1.746 kcal** | **118.5 g** de proteína\n' +
  '📋 Protocolo: Recomposição corporal\n\n' +
  'Próxima reavaliação em 14 dias. Seguimos! 💪'

describe('audit 2026-10-04 — R4: na reavaliação a recusa da meta chega ao paciente', () => {
  it('meta de 7% dentro de define_protocolo: o modelo redige com o goal_message em mãos (antes: "Reavaliação concluída ✅" e a recusa sumia)', async () => {
    const t = reevalTurn(
      REEVAL_TEXT,
      [CADASTRA_CALL, protocoloCall({ goal_type: 'BF', goal_value: 7 })],
      true,
    )
    const out = await runReeval(t, REEVAL_TEXT)

    // A second model call happened and its answer is what the patient reads.
    expect(t.modelCalls).toHaveLength(2)
    expect(out.text).toBe(MODEL_ANSWER)
    expect(out.text).not.toContain('Reavaliação concluída')

    const protocolo = out.toolCalls.find((c) => c.name === 'define_protocolo')
    expect(protocolo?.result).toMatchObject({
      success: true,
      protocol: 'recomposicao',
      goal_saved: false,
      goal_refused_reason: 'gordura_abaixo_do_piso',
      goal_message:
        'Protocolo registrado. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, ' +
        'que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere?',
    })
    // The message is in the tool result the model answers from.
    const toolMessages = (t.modelCalls[1] ?? []).filter((m) => m.role === 'tool')
    expect(
      toolMessages.some((m) =>
        String(m.content).includes('Posso registrar uma meta a partir de 10%.'),
      ),
    ).toBe(true)

    // The protocol and the weight were saved; the goal was not.
    expect(t.profile()).toMatchObject({
      weight_kg: 79,
      current_protocol: 'recomposicao',
      deficit_level: 500,
      goal_type: null,
      goal_value: null,
    })
  })

  it.each([
    [
      'com meta válida (BF 15) em define_protocolo',
      [CADASTRA_CALL, protocoloCall({ goal_type: 'BF', goal_value: 15 })],
    ],
    ['com define_protocolo sem meta', [CADASTRA_CALL, protocoloCall({})]],
    ['só com cadastra_dados_iniciais', [CADASTRA_CALL]],
  ])('reavaliação normal %s: o texto fixo de sempre, byte a byte, sem segunda chamada ao modelo', async (_label, calls) => {
    const text = 'Peso 79 kg, fome moderada, não vou mandar fotos.'
    const t = reevalTurn(text, calls, true)
    const out = await runReeval(t, text)

    expect(t.modelCalls).toHaveLength(1)
    expect(out.text).toBe(REEVAL_DONE)
  })

  it('sem reevaluation.due recente o modelo já redigia (inalterado)', async () => {
    const t = reevalTurn(
      REEVAL_TEXT,
      [CADASTRA_CALL, protocoloCall({ goal_type: 'BF', goal_value: 7 })],
      false,
    )
    const out = await runReeval(t, REEVAL_TEXT)
    expect(t.modelCalls).toHaveLength(2)
    expect(out.text).toBe(MODEL_ANSWER)
  })
})

// ── R4: the model's faithful answer to the refusal is not a phantom meal ────
//
// Review of 2026-10-04 (round 2), MEDIUM. Since the refusal goes to the model,
// its answer repeats the tool's own words — "Protocolo registrado … a meta não
// foi registrada" — next to the new target in kcal. The phantom-write guard
// (claim verb + kcal or 🔥/💪/📊, no registra_refeicao in the turn) read that
// as a meal registered without the tool and forced a THIRD model call with
// "você afirmou ter registrado a refeição/treino MAS não chamou a tool
// `registra_refeicao` … Chame a tool AGORA". Reproduced by the reviewer through
// processMessage with the first two answers below (fake WhatsApp, model and
// database; no print exists): 3 model calls, events llm.fake_write_detected
// and llm.fake_write_unresolved. Same profile, sentence and tool calls as the
// block above. The third answer joins the two signatures; the read tool of the
// control (consulta_metricas) and the invalid argument are synthetic.
//
// A turn in which define_protocolo or define_meta_peso ran without error is no
// longer read as a phantom MEAL write by that generic rule.

const ANSWER_WITH_KCAL =
  'Sua nova meta é 1.746 kcal e 118,5 g de proteína por dia. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere?'
const ANSWER_WITH_EMOJI =
  'A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪'
const ANSWER_WITH_BOTH =
  'Protocolo registrado. Sua nova meta é 1.746 kcal por dia. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪'
const FAKE_WRITE_RETRY = 'você afirmou ter registrado a refeição/treino MAS não chamou a tool'

const sawFakeWriteRetry = (t: ReevalTurn): boolean =>
  t.modelCalls.some((messages) =>
    messages.some((m) => m.role === 'user' && String(m.content).includes(FAKE_WRITE_RETRY)),
  )

describe('audit 2026-10-04 — R4: a resposta fiel à recusa não é escrita fantasma de refeição', () => {
  it.each([
    { label: 'com kcal (a resposta do revisor)', answer: ANSWER_WITH_KCAL },
    { label: 'sem kcal, terminando em 💪 (a outra do revisor)', answer: ANSWER_WITH_EMOJI },
    { label: '"Protocolo registrado" + kcal + 💪', answer: ANSWER_WITH_BOTH },
  ])('reavaliação com a meta de 7% recusada, resposta $label: 2 chamadas ao modelo e o texto chega como foi escrito (antes: 3 chamadas)', async ({
    answer,
  }) => {
    const t = reevalTurn(
      REEVAL_TEXT,
      [CADASTRA_CALL, protocoloCall({ goal_type: 'BF', goal_value: 7 })],
      true,
      answer,
    )
    const out = await runReeval(t, REEVAL_TEXT)

    expect(t.modelCalls).toHaveLength(2)
    expect(out.text).toBe(answer)
    expect(sawFakeWriteRetry(t)).toBe(false)
    expect(t.events).not.toContain('llm.fake_write_detected')
    expect(t.events).not.toContain('llm.fake_write_unresolved')
    // The turn is the refusal turn: protocol saved, goal dropped.
    expect(out.toolCalls.find((c) => c.name === 'define_protocolo')?.result).toMatchObject({
      success: true,
      goal_saved: false,
    })
    expect(t.profile()).toMatchObject({
      weight_kg: 79,
      current_protocol: 'recomposicao',
      goal_type: null,
      goal_value: null,
    })
  })

  it('fora da reavaliação (sem reevaluation.due) a mesma resposta também passa com 2 chamadas', async () => {
    const t = reevalTurn(
      REEVAL_TEXT,
      [CADASTRA_CALL, protocoloCall({ goal_type: 'BF', goal_value: 7 })],
      false,
      ANSWER_WITH_BOTH,
    )
    const out = await runReeval(t, REEVAL_TEXT)

    expect(t.modelCalls).toHaveLength(2)
    expect(out.text).toBe(ANSWER_WITH_BOTH)
    expect(t.events).not.toContain('llm.fake_write_detected')
  })

  it('controle — nenhuma tool no turno: a mesma resposta dispara o guard (retry forçado e os dois eventos)', async () => {
    const t = reevalTurn(REEVAL_TEXT, [], true, ANSWER_WITH_BOTH)
    await runReeval(t, REEVAL_TEXT)

    // Answer, then the forced retry.
    expect(t.modelCalls).toHaveLength(2)
    expect(sawFakeWriteRetry(t)).toBe(true)
    expect(t.events).toContain('llm.fake_write_detected')
    expect(t.events).toContain('llm.fake_write_unresolved')
  })

  it('controle — só uma tool de LEITURA rodou (consulta_metricas): o guard dispara do mesmo jeito', async () => {
    const t = reevalTurn(
      REEVAL_TEXT,
      [{ id: 't1', name: 'consulta_metricas', arguments: '{}' }],
      true,
      ANSWER_WITH_BOTH,
    )
    const out = await runReeval(t, REEVAL_TEXT)

    const read = out.toolCalls.find((c) => c.name === 'consulta_metricas')
    expect(read).toBeDefined()
    expect(read?.error).toBeUndefined()
    // Tool call, answer, forced retry.
    expect(t.modelCalls).toHaveLength(3)
    expect(sawFakeWriteRetry(t)).toBe(true)
    expect(t.events).toContain('llm.fake_write_detected')
    expect(t.events).toContain('llm.fake_write_unresolved')
  })

  it('controle — só cadastra_dados_iniciais rodou (fora da reavaliação): o guard dispara do mesmo jeito', async () => {
    const t = reevalTurn(REEVAL_TEXT, [CADASTRA_CALL], false, ANSWER_WITH_BOTH)
    await runReeval(t, REEVAL_TEXT)

    expect(t.modelCalls).toHaveLength(3)
    expect(sawFakeWriteRetry(t)).toBe(true)
    expect(t.events).toContain('llm.fake_write_detected')
  })

  it('controle — define_protocolo chamada com argumento inválido (erro, nada gravado): o guard dispara', async () => {
    const t = reevalTurn(
      REEVAL_TEXT,
      [{ id: 't1', name: 'define_protocolo', arguments: JSON.stringify({ protocol: 'cutting' }) }],
      false,
      ANSWER_WITH_BOTH,
    )
    const before = { ...t.profile() }
    const out = await runReeval(t, REEVAL_TEXT)

    expect(out.toolCalls.find((c) => c.name === 'define_protocolo')?.error).toBeTruthy()
    expect(t.profile()).toEqual(before)
    expect(sawFakeWriteRetry(t)).toBe(true)
    expect(t.events).toContain('llm.fake_write_detected')
  })
})
