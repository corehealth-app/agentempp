/**
 * Audit 2026-10-04 — rules R1 and R2 of the client's WhatsApp group and the
 * value of the app's "Déficit líquido" line (docs/CALCULO-MPP.md §2c).
 *
 * THE RULE, as the client (Dr. Roberto) wrote it — it is NOT a new decision:
 *   20/01/2026 17:38 (texto): "Balanço diário Recomposição: Somatório das
 *     calorias consumidas no dia - (BMR x 1,2 + calorias gastas no exercicio
 *     do dia)"; "Balanço calórico Ganho de massa muscular: Somatório das
 *     calorias totais consumidas no dia - (BMR x fator de atividade)";
 *     "Balanço calórico Manutenção: Somatório das calorias totais consumidas
 *     no dia - (BMR x fator de atividade)".
 *   22/02/2026 12:10 (áudio): "A fórmula que tá lá do balanço é meta né não é
 *     meta … é o BMR vezes o fator de atividade física".
 *   23/02/2026 20:14 (áudio): "o exercício físico … só vai entrar no balanço
 *     quando for recomposição corporal".
 *   09/03/2026 12:37 (texto): "1)Balanço do dia recomposição: Calorias
 *     consumidas no dia - [(BMR x 1,2 + calorias do exerciio)] 2) Balanco
 *     ganho de massa: Calorias consumidas - (BMR x fator de atividade) 3)
 *     Balanço manutenção: Calorias consumidas - (BMR x fator de atividade)";
 *     13:18: "nos protocolos de ganho de massa e manutenção, mesmo q o usuario
 *     informe a atividade fisica do dia ela não deve entrar no calculo do
 *     balanço pq ela ja foi contemplada no fator multiplicador".
 *   Recomposição, the numbers he asked for: 20/05/2026 08:39 "O déficit de
 *     ontem deveria ser 500 - 233=267 + 565 = 832"; 21/05/2026 22:11
 *     "500-126=374 / 374+523=897 kcal de déficit hj … 5.757+897 =
 *     6.654/7.700"; 22/05/2026 12:38 "O deficit ou não do dia só pode ser
 *     falado após o dia fechado".
 * Dito pelo cliente nessas datas; implementado em 2026-10-04 a pedido do
 * Eduardo; confirmação do cliente pendente.
 *
 * WHAT CHANGED (one function, one switch — `dayEnergyBalance` and
 * `DAY_BALANCE_AGAINST_EXPENDITURE` in packages/core/src/engine/balance.ts):
 *  - app, GET /today: `daily_balance_kcal` (the "Déficit líquido" line) is
 *    consumed − the day's expenditure; two additive fields say what it was
 *    measured against; calculation_version v3;
 *  - Flow chat: the "Balanço calórico de hoje" line of the context and the
 *    day-balance key of consulta_progresso give the same number.
 * "Restam / Excedente" (the food line) stays against the TARGET, without
 * exercise, in every protocol. The daily closer, the block credit, the
 * WhatsApp context and the generated column are untouched.
 *
 * Every test runs production code: the real loadOfficialDailyState (with the
 * real calc-config loader), the real Flow pipeline entry
 * (processAuthenticatedMessage) and the real consulta_progresso called by the
 * model through that pipeline. The block credit is the real creditDayToBloco.
 *
 * The "+133" (2799 against 2666) is a recalculation of the audit (homem,
 * 81 kg, 180 cm, 44 anos, moderado), NOT a number the client stated.
 *
 * REVIEW OF 2026-10-04 (balance lens) — its inputs are locked at the end of
 * this file, each through the same production entries:
 *  - day of a protocol change: the registration RPCs keep the FIRST target of
 *    the day, so the day row carries the OLD protocol's target and the
 *    expenditure was derived from it with the NEW protocol's rule (2799 stored
 *    in ganho de massa, recomposição at noon, 2500 consumed → "-799 against
 *    3299" when the client's rule gives +436). The stored target is now
 *    compared with the three targets the profile gives now
 *    (`resolveDayBalanceInputs`, packages/core/src/engine/day-balance-inputs.ts);
 *    when it is nearer to another protocol's target the day keeps the legacy
 *    number on the Today screen AND in the Flow. A new weight is not a change
 *    of protocol: the QA account's own day (2980 stored at 80 kg, 2988 at
 *    80,5 kg) stays on the rule. Switch: `DAY_BALANCE_DAY_ROW_GUARD`;
 *  - closed day whose row carries a protocol different from the profile's:
 *    app and Flow now both use the row's protocol and ITS programmed deficit;
 *  - `daily_balance_reference_kcal` is an integer on the legacy path too
 *    (packages/core/src/daily-state.test.ts);
 *  - a multiplier saved as the JSON text "1.05" is read as a number;
 *  - the multiplier of the calc config reaches consulta_progresso (1,10).
 *
 * > RC R1/R2 — cenário crédito do bloco e fechamento diário em ganho_massa/manutenção (o cliente escreveu em 08/05/2026 que nesses protocolos o bloco de 7.700 "é substituido pelo bloco acumaldo de Kcal em 14 dias"; o bloco de 14 dias não está definido) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: o fechamento credita meta + exercício − consumido (travado abaixo como está).
 * > RC R1/R2 — cenário contexto do WhatsApp e consulta_progresso do WhatsApp NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado e travado em audit-10-04-whatsapp-context-lock.test.ts.
 * > RC R1/R2 — cenário mensagem de bom dia do WhatsApp (engagement-sender) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC R1/R2 — cenário consulta_resumo_periodo (média da coluna gerada, com exercício e contra a meta, também no Flow) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC R1/R2 — cenário coluna gerada daily_snapshots.daily_balance (consumido − meta − exercício em todo protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC R1/R2 — cenário rótulo "Balanço do dia" e legenda do exercício do iPhone vistos no aparelho NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Coberto no código do app em commit separado do mesmo dia (9624cd5): rótulo "Balanço do dia", valor em palavras ("Déficit de N kcal" / "Superávit de N kcal"), legenda lida de daily_balance_includes_exercise (campo ausente = "Exercício incluído"). Ainda não verificado no aparelho. Continua aberto: o VoiceOver lê o valor duas vezes nessa linha; as frases da trilha e do tour sobre o bloco de 7.700 aparecem para todo protocolo; o app mostra o número do dia aberto.
 * > RC R1/R2 — cenário protocolo ainda não definido (null) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: consumido − meta − exercício (travado abaixo).
 * > RC R1/R2 — cenário número de dia aberto na tela Hoje (o cliente disse em 22/05/2026 12:38 que "O deficit ou não do dia só pode ser falado após o dia fechado") NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A tela continua mostrando o número provisório do dia em andamento (travado abaixo: 22/05 12:37).
 * > RC R1/R2 — cenário dia em que o fechamento não credita o balanço observado (sub-registro abaixo de 50% da meta, dia incompleto, dia sem atividade) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nesses dias o número da tela e do Flow não é o crédito do bloco (travado abaixo: 22/05 12:37, tela −2423, crédito 500).
 * > RC R1/R2 — cenário resposta do MODELO no Flow com as linhas novas (conversa real) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Só nova rodada no iPhone/staging prova.
 * > RC R1/R2 — cenário redação das linhas novas do Flow (texto entregue ao modelo, sem aprovação clínica do cliente) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC R1/R2 — cenário prosa do Flow sobre o balanço do dia sem o número exato ("você está em superávit", "superávit de quase 60 kcal") NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   reconcileBalanceProse só poupa a frase que cita o balanço do dia com o número exato (±1) e o sinal certo; no WhatsApp ela não mudou.
 * > RC R1/R2 — cenário acréscimo do ganho de massa ("mais o zero mais os cinco por cento", 22/02/2026: 5% fixo ou faixa de 0 a 5%?) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A referência é a meta do dia dividida pelo multiplicador configurado (1,05).
 * > RC R1/R2 — cenário degraus de déficit na passagem recomposição → manutenção (áudios de 25/03/2026) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC R1/R2 — cenário deficit_level ou multiplicador alterado depois de a meta do dia ter sido gravada NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   deficit_level: a referência é a meta gravada no dia + o déficit ATUAL do perfil. Multiplicador: se a meta gravada ficar mais perto da meta de manutenção do que da de ganho com o multiplicador novo (conta QA com 1,10: gravada 2980, ganho 3131, manutenção 2846), o dia cai no número legado (−2761, travado abaixo); senão a referência é a meta gravada ÷ o multiplicador atual.
 * > RC R1/R2 — cenário dia de troca de protocolo: balanço do dia pela regra do cliente com o gasto do protocolo NOVO NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nesse dia a linha do dia guarda a meta do protocolo antigo, e a tela e o Flow mostram o número legado (consumido − meta gravada − exercício, "Exercício incluído"): manhã em ganho de massa 2799, recomposição ao meio-dia, 2500 consumido → −299 (travado abaixo; a regra do cliente daria 2500 − 2064 = +436). O número legado desse dia não é o que o fechamento credita: o fechamento regrava a meta.
 * > RC R1/R2 — cenário dia em que o peso, o nível de atividade ou a idade mudam depois de a meta do dia ter sido gravada (mesmo protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O gasto continua derivado da meta gravada: conta QA 04/10, gravada 2980 com 80 kg, perfil com 80,5 kg dá 2988 → tela e Flow −2297 contra 2838 (com a meta nova seria −2305 contra 2846). O fechamento recalcula a meta com o perfil da hora do fechamento: nesses dias a tela e o crédito do bloco diferem pela diferença entre as duas metas.
 * > RC R1/R2 — cenário meta gravada mais perto da meta de outro protocolo por mudança grande de peso ou de nível de atividade no dia (sem troca de protocolo), e troca manutenção ↔ ganho de massa junto com mudança de peso NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A comparação é por proximidade entre a meta gravada e as três metas que o perfil dá agora, sem tolerância fixa. Ganho de massa e manutenção diferem só pelo multiplicador (133 kcal no exemplo da auditoria): uma mudança de alguns quilos no dia cai no número legado sem troca de protocolo, e uma troca manutenção ↔ ganho junto com mudança de peso pode não ser percebida.
 * > RC R1/R2 — cenário perfil incompleto (meta não calculável) com meta gravada no dia NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Sem meta calculada não há comparação: vale a regra do protocolo sobre a meta gravada.
 * > RC R1/R2 — cenário dia fechado em recomposição cujo deficit_level do perfil mudou depois do fechamento NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A linha do dia guarda o protocolo do fechamento, não o déficit programado: a tela e o Flow usam o deficit_level atual do perfil (500 quando ausente).
 * > RC R1/R2 — cenário dados reais de perfil dos dias 19/05, 21/05 e 22/05/2026 (altura, idade, peso; BMR × 1,2 lido do banco) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Os relatos trazem meta, consumido, exercício e bloco; a referência 2.343 é meta 1.843 + déficit 500.
 * > RC R1/R2 — cenário painel admin (/users/[id] e /formulas, que mostram a coluna gerada e a fórmula antiga) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 */
import {
  computeDailyTargets,
  creditDayToBloco,
  DAY_BALANCE_AGAINST_EXPENDITURE,
  DAY_BALANCE_DAY_ROW_GUARD,
  netBalance,
  type ProfileRow,
} from '@mpp/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache, loadCalcConfig } from '../calc-config-loader.js'
import { loadOfficialDailyState } from '../daily-state-service.js'
import type { PipelineDeps } from '../pipeline.js'
import { processAuthenticatedMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'

type Row = Record<string, unknown>
type Protocol = 'recomposicao' | 'ganho_massa' | 'manutencao' | null

const USER_ID = 'audit-10-04-day-balance'
const TURN_ID = 'mobile_flow/audit-10-04-day-balance/turn'
const TIMEZONE = 'America/Sao_Paulo'

// ── Staging `global_config`, read 2026-10-04 ~14:20 BRT ─────────────────────
// No `calc.ganho_massa_surplus_multiplier` row there: the code default (1,05).
const STAGING_CONFIG: Row[] = [
  {
    key: 'calc.activity_factors',
    value: { sedentario: 1.2, leve: 1.375, moderado: 1.55, alto: 1.725, atleta: 1.9 },
  },
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

// ── Profiles ────────────────────────────────────────────────────────────────
// QA account A (staging, 2026-10-04). The birth date was not part of the
// readout (same placeholder as the other goldens of this audit); the day
// target comes from the day row.
const QA_PROFILE: ProfileRow = {
  sex: 'masculino',
  birth_date: '2000-01-01',
  height_cm: 185,
  weight_kg: 80.5,
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
// The client's own days of May. Height, age and weight are not in the
// reports (declared above): only the protocol and the programmed deficit of
// 500 he states ("500 - 233", "500-126") matter; the target is the day row's.
const RECOMP_PROFILE: ProfileRow = {
  ...QA_PROFILE,
  current_protocol: 'recomposicao',
  deficit_level: 500,
}
// The audit's derived examples (44 anos at the instants below).
const DERIVED_GAIN_PROFILE: ProfileRow = {
  ...QA_PROFILE,
  birth_date: '1982-01-15',
  height_cm: 180,
  weight_kg: 81,
}
const MAINTENANCE_PROFILE: ProfileRow = {
  ...QA_PROFILE,
  birth_date: '1982-01-15',
  height_cm: 187,
  weight_kg: 101,
  current_protocol: 'manutencao',
}

interface Scenario {
  name: string
  /** The instant of the request (the local day is the day row's date). */
  now: string
  date: string
  profile: ProfileRow
  target: number
  consumed: number
  exercise: number
  dayStatus: string | null
  /** user_progress.deficit_block before the day closes. */
  block: number
  /** Today, before this change: consumed − target − exercise. */
  before: number
  /** After: consumed − the day's expenditure. */
  after: number
  reference: number
  includesExercise: boolean
  remainingFood: number
  foodExcess: number
  /** Columns of the day row that differ from the open day built by `dayRow`. */
  row?: Row
}

// ── The scenarios, value by value ───────────────────────────────────────────
const RECOMP_19_05: Scenario = {
  name: 'recomposição 19/05/2026 (2076 / 1843, treino 565, jantar "Pulei")',
  now: '2026-05-20T02:30:00.000Z',
  date: '2026-05-19',
  profile: RECOMP_PROFILE,
  target: 1843,
  consumed: 2076,
  exercise: 565,
  dayStatus: 'user_skipped',
  block: 5254,
  before: -332,
  after: -832,
  reference: 2343,
  includesExercise: true,
  remainingFood: 0,
  foodExcess: 233,
}
const RECOMP_21_05: Scenario = {
  name: 'recomposição 21/05/2026 (1969 / 1843, treino 523 = 297 musculação + 226 bicicleta)',
  now: '2026-05-22T01:11:00.000Z',
  date: '2026-05-21',
  profile: RECOMP_PROFILE,
  target: 1843,
  consumed: 1969,
  exercise: 523,
  dayStatus: null,
  block: 5757,
  before: -397,
  after: -897,
  reference: 2343,
  includesExercise: true,
  remainingFood: 0,
  foodExcess: 126,
}
const RECOMP_22_05_OPEN: Scenario = {
  name: 'recomposição, dia aberto 22/05/2026 12:37 (568 / 1843, treino 648 = 365 + 283)',
  now: '2026-05-22T15:37:00.000Z',
  date: '2026-05-22',
  profile: RECOMP_PROFILE,
  target: 1843,
  consumed: 568,
  exercise: 648,
  dayStatus: null,
  block: 6654,
  before: -1923,
  after: -2423,
  reference: 2343,
  includesExercise: true,
  remainingFood: 1275,
  foodExcess: 0,
}
const QA_GAIN: Scenario = {
  name: 'ganho de massa, conta QA 04/10/2026 (541 / 2980, treino 322)',
  now: '2026-10-04T15:03:40.503Z',
  date: '2026-10-04',
  profile: QA_PROFILE,
  target: 2980,
  consumed: 541,
  exercise: 322,
  dayStatus: null,
  block: 0,
  before: -2761,
  after: -2297,
  reference: 2838,
  includesExercise: false,
  remainingFood: 2439,
  foodExcess: 0,
}
const QA_GAIN_ON_TARGET_WORKOUT: Scenario = {
  ...QA_GAIN,
  name: 'ganho de massa comendo exatamente 2980, com o treino de 322',
  consumed: 2980,
  before: -322,
  after: 142,
  remainingFood: 0,
}
const QA_GAIN_ON_TARGET_NO_WORKOUT: Scenario = {
  ...QA_GAIN,
  name: 'ganho de massa comendo exatamente 2980, sem treino',
  consumed: 2980,
  exercise: 0,
  before: 0,
  after: 142,
  remainingFood: 0,
}
const MAINTENANCE: Scenario = {
  name: 'manutenção (3044 / 3044, treino 400)',
  now: '2026-10-04T15:03:40.503Z',
  date: '2026-10-04',
  profile: MAINTENANCE_PROFILE,
  target: 3044,
  consumed: 3044,
  exercise: 400,
  dayStatus: null,
  block: 0,
  before: -400,
  after: 0,
  reference: 3044,
  includesExercise: false,
  remainingFood: 0,
  foodExcess: 0,
}
const DERIVED_GAIN_WORKOUT: Scenario = {
  name: 'exemplo derivado da auditoria: ganho de massa comendo 2799 contra 2666, treino 300',
  now: '2026-10-04T15:03:40.503Z',
  date: '2026-10-04',
  profile: DERIVED_GAIN_PROFILE,
  target: 2799,
  consumed: 2799,
  exercise: 300,
  dayStatus: null,
  block: 0,
  before: -300,
  after: 133,
  reference: 2666,
  includesExercise: false,
  remainingFood: 0,
  foodExcess: 0,
}
const DERIVED_GAIN_NO_WORKOUT: Scenario = {
  ...DERIVED_GAIN_WORKOUT,
  name: 'exemplo derivado da auditoria: 2799 contra 2666, sem treino',
  exercise: 0,
  before: 0,
}
// Protocol not set: the day row of the QA account under a profile whose
// protocol is still null. Nothing may change here.
const NULL_PROTOCOL: Scenario = {
  ...QA_GAIN,
  name: 'protocolo ainda não definido (541 / 2980, treino 322)',
  profile: { ...QA_PROFILE, current_protocol: null },
  before: -2761,
  after: -2761,
  reference: 2980,
  includesExercise: true,
}

// The QA day row under a calc config whose multiplier is 1,10, with the
// profile whose own target at 1,10 is the 2980 of the row (185 cm, 26 anos,
// moderado, 71,65 kg: BMR 1747,75 × 1,55 × 1,10 = 2980). Not the QA account:
// its 80,5 kg give 3131 at 1,10 (see GAIN_MULTIPLIER_CHANGED at the end).
const CONFIG_1_10: Row[] = [
  ...STAGING_CONFIG,
  { key: 'calc.ganho_massa_surplus_multiplier', value: 1.1 },
]
const GAIN_AT_1_10: Scenario = {
  ...QA_GAIN,
  name: 'ganho de massa com multiplicador 1,10 desde antes da meta do dia (541 / 2980, treino 322)',
  profile: { ...QA_PROFILE, weight_kg: 71.65 },
  after: -2168,
  reference: 2709,
}

const CHANGED: Scenario[] = [
  RECOMP_19_05,
  RECOMP_21_05,
  RECOMP_22_05_OPEN,
  QA_GAIN,
  QA_GAIN_ON_TARGET_WORKOUT,
  QA_GAIN_ON_TARGET_NO_WORKOUT,
  MAINTENANCE,
  DERIVED_GAIN_WORKOUT,
  DERIVED_GAIN_NO_WORKOUT,
]
const ALL: Scenario[] = [...CHANGED, NULL_PROTOCOL]

// ── One fake database for the app read and for the Flow pipeline ────────────
interface ScriptedStep {
  content?: string
  toolCalls?: Array<{ id: string; name: string; arguments: string }>
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Row }>
  llmCalls: Array<{ systemPrompt: unknown; messages: unknown[] }>
}

interface Read {
  table: string
  columns: string
  filters: Row
}

function dayRow(s: Scenario): Row {
  return {
    id: `snapshot-${s.date}`,
    date: s.date,
    calories_target: s.target,
    protein_target: 144,
    calories_consumed: s.consumed,
    protein_g: 59.03,
    carbs_g: 47.32,
    fat_g: 10.27,
    exercise_calories: s.exercise,
    water_consumed_ml: 500,
    // The generated column, as the database computes it (unchanged).
    daily_balance: s.consumed - s.target - s.exercise,
    deficit_accumulated: 0,
    // `current_protocol` of the day row is written only at closing.
    current_protocol: null,
    day_status: s.dayStatus,
    day_closed: false,
    gap_reminder_sent_at: null,
    updated_at: s.now,
    ...(s.row ?? {}),
  }
}

function harness(
  s: Scenario,
  options: { text?: string; script?: ScriptedStep[]; config?: Row[] } = {},
): Harness {
  const day = dayRow(s)
  const text = options.text ?? 'Mostre meu progresso recente.'
  const script = options.script ?? [{ content: 'Resposta do modelo.' }]
  const inserts: Harness['inserts'] = []
  const llmCalls: Harness['llmCalls'] = []

  const rowsFor = (read: Read): unknown => {
    switch (read.table) {
      case 'users':
        return {
          id: USER_ID,
          name: 'Paciente',
          summary: null,
          last_active_at: null,
          country: 'BR',
          country_confirmed: true,
          country_detected_from_wpp: null,
          locale: 'pt-BR',
          metadata: null,
          timezone: TIMEZONE,
        }
      case 'user_profiles':
        return s.profile
      case 'user_progress':
        return {
          current_streak: 0,
          longest_streak: 0,
          xp_total: 0,
          level: 1,
          blocks_completed: 0,
          deficit_block: s.block,
          last_active_date: null,
          updated_at: s.now,
        }
      case 'messages':
        return [
          {
            direction: 'in',
            content: text,
            content_type: 'text',
            created_at: s.now,
            provider: 'mobile_flow',
            provider_message_id: TURN_ID,
          },
        ]
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return []
        if (read.filters.date !== s.date) return null
        // The app reads the day with its logs embedded; none are needed here.
        if (read.columns.includes('meal_logs(')) return { ...day, meal_logs: [], workout_logs: [] }
        if (read.columns.trim() === '*') return day
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), day[key.trim()] ?? null]),
        )
      }
      case 'global_config':
        if (read.filters.key === 'router.haiku_enabled') return null
        return options.config ?? STAGING_CONFIG
      case 'v_active_prompts':
        return {
          stage: read.filters.stage ?? 'recomposicao',
          model: 'anthropic/claude-sonnet-4.6',
          temperature: 0,
          max_tokens: 512,
          system_prompt: 'REGRAS COMPARTILHADAS',
          allowed_tools: null,
        }
      default:
        // pending_registrations, notification_preferences, agent_rules, …: empty.
        return []
    }
  }

  const supabase = {
    from(table: string) {
      const read: Read = { table, columns: '', filters: {} }
      const result = () => ({ data: rowsFor(read), error: null })
      const one = async () => {
        const { data } = result()
        return { data: Array.isArray(data) ? (data[0] ?? null) : data, error: null }
      }
      const chain = Promise.resolve().then(result) as Promise<{ data: unknown; error: null }> &
        Record<string, unknown>
      for (const method of [
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
        'update',
        'upsert',
        'delete',
      ]) {
        chain[method] = () => chain
      }
      chain.select = (columns?: string) => {
        if (typeof columns === 'string') read.columns = columns
        return chain
      }
      chain.eq = (key: string, value: unknown) => {
        read.filters[key] = value
        return chain
      }
      chain.insert = (row: Row) => {
        inserts.push({ table, row })
        return chain
      }
      chain.single = one
      chain.maybeSingle = one
      return chain
    },
    rpc: async (name: string) => {
      if (name === 'list_mobile_routine_items') {
        return { data: { local_date: s.date, items: [] }, error: null }
      }
      return { data: name === 'match_method_chunks' ? [] : USER_ID, error: null }
    },
  } as unknown as PipelineDeps['supabase']

  let call = 0
  const llm = {
    complete: async (input: { systemPrompt: unknown; messages: unknown[] }) => {
      llmCalls.push({ systemPrompt: input.systemPrompt, messages: [...input.messages] })
      const step = script[Math.min(call, script.length - 1)] ?? {}
      call += 1
      return {
        content: step.content ?? '',
        toolCalls: step.toolCalls ?? [],
        model: 'anthropic/claude-sonnet-4.6',
        promptTokens: 0,
        completionTokens: 0,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']

  return { deps: { supabase, llm, maxToolIterations: 3 }, inserts, llmCalls }
}

/** GET /today: the real service, with the real calc-config loader. */
function today(s: Scenario, h: Harness = harness(s)) {
  return loadOfficialDailyState(h.deps.supabase, USER_ID, TIMEZONE, new Date(s.now), {
    loadConfig: loadCalcConfig,
    // The meal pattern is not part of the balance.
    loadMealPattern: async () => ({
      expected: new Set(['cafe', 'almoco', 'jantar'] as const),
      activeDays: 10,
      countByType: { cafe: 10, almoco: 10, lanche: 2, jantar: 9, ceia: 0 },
      threshold: 0.5,
      fallbackUsed: false,
    }),
    loadSkippedMeals: async () => new Set<'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'>(),
  })
}

function flow(s: Scenario, h: Harness, text = 'Mostre meu progresso recente.') {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: TURN_ID,
    text,
    timestamp: new Date(s.now),
  })
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

/** The numeric section of the Flow context for a turn the model answers. */
async function flowContext(s: Scenario, config?: Row[]): Promise<string[]> {
  const h = harness(s, { config })
  await flow(s, h)
  expect(h.llmCalls.length).toBeGreaterThan(0)
  const prompt = flattenSystemPrompt(h.llmCalls[0]?.systemPrompt)
  const start = prompt.indexOf('### Dados numéricos REAIS')
  const end = prompt.indexOf('### Regras importantes')
  expect(start).toBeGreaterThan(-1)
  expect(end).toBeGreaterThan(start)
  return prompt.slice(start, end).trimEnd().split('\n')
}

const balanceLine = (lines: string[]): string =>
  lines.find((line) => line.startsWith('- Balanço calórico de hoje')) ?? ''
const foodLine = (lines: string[]): string =>
  lines.find((line) => line.startsWith('- Para COMIDA hoje')) ?? ''

/** `energia_hoje` as the model reads it after calling consulta_progresso. */
async function flowTool(s: Scenario, config?: Row[]): Promise<Row> {
  const h = harness(s, {
    config,
    script: [
      { toolCalls: [{ id: 'call-1', name: 'consulta_progresso', arguments: '{}' }] },
      { content: 'Resposta do modelo.' },
    ],
  })
  const output = await flow(s, h)
  expect(output.toolCalls.map((call) => call.name)).toEqual(['consulta_progresso'])
  const toolMessages = (h.llmCalls[1]?.messages ?? []).filter(
    (message): message is { role: 'tool'; tool_call_id: string; content: string } =>
      typeof message === 'object' &&
      message !== null &&
      (message as { role?: unknown }).role === 'tool',
  )
  expect(toolMessages).toHaveLength(1)
  const seen = toolMessages[0]?.content ?? ''
  expect(seen).not.toContain('daily_balance')
  return (JSON.parse(seen) as { energia_hoje: Row }).energia_hoje
}

/** What the Flow line of each shape must read. */
const expenditureLine = (s: Scenario): string =>
  s.includesExercise
    ? `- Balanço calórico de hoje COM exercício (consumido − gasto do dia; gasto do dia = ${s.reference} kcal de gasto de referência + ${s.exercise} kcal de exercício): ${s.after} kcal (negativo=déficit, positivo=superávit) — é o déficit ou superávit real do dia até agora, provisório até o dia fechar; o crédito no bloco 7700 só acontece no fechamento do dia e este número NÃO é o que resta para comer`
    : `- Balanço calórico de hoje (consumido − gasto de referência de ${s.reference} kcal; o exercício já está no fator de atividade e não é somado): ${s.after} kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer`
const legacyLine = (s: Scenario, protocol: Protocol): string =>
  `- Balanço calórico de hoje COM exercício (consumido − meta − exercício): ${s.before} kcal (negativo=déficit, positivo=superávit) — ${
    protocol === 'recomposicao'
      ? 'o crédito do bloco 7700 só é calculado no fechamento do dia (déficit programado − este número); até lá o valor é provisório e NÃO é o que resta para comer'
      : 'NÃO é o que resta para comer'
  }`

type Switches = Record<keyof typeof DAY_BALANCE_AGAINST_EXPENDITURE, boolean>
const switches = DAY_BALANCE_AGAINST_EXPENDITURE as Switches
const SHIPPED: Switches = { ...DAY_BALANCE_AGAINST_EXPENDITURE }
const ALL_OFF: Switches = { recomposicao: false, ganho_massa: false, manutencao: false }

beforeEach(() => {
  vi.useFakeTimers()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})
const dayRowGuard = DAY_BALANCE_DAY_ROW_GUARD as { enabled: boolean }

afterEach(() => {
  Object.assign(switches, SHIPPED)
  dayRowGuard.enabled = true
  vi.useRealTimers()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})

describe('audit 2026-10-04 R1/R2 — the scenarios are what they say they are', () => {
  it.each(ALL)('$name: the "before" is consumed − target − exercise', (s) => {
    expect(netBalance(s.consumed, s.target, s.exercise)).toBe(s.before)
    expect(dayRow(s).daily_balance).toBe(s.before)
    expect(Math.max(0, s.target - s.consumed)).toBe(s.remainingFood)
    expect(Math.max(0, s.consumed - s.target)).toBe(s.foodExcess)
  })

  it('the derived profiles give the targets of the examples (real computeDailyTargets, staging factors)', async () => {
    vi.setSystemTime(new Date('2026-10-04T15:03:40.503Z'))
    const config = await loadCalcConfig(harness(QA_GAIN).deps.supabase)

    // 81 kg, 180 cm, 44 anos, moderado: BMR 1720 × 1,55 = 2666; × 1,05 = 2799.
    expect(computeDailyTargets(DERIVED_GAIN_PROFILE, config).calories_target).toBe(2799)
    expect(
      computeDailyTargets({ ...DERIVED_GAIN_PROFILE, current_protocol: 'manutencao' }, config)
        .calories_target,
    ).toBe(2666)
    // 101 kg, 187 cm, 44 anos, moderado: BMR 1963,75 × 1,55 = 3044.
    expect(computeDailyTargets(MAINTENANCE_PROFILE, config).calories_target).toBe(3044)
    // QA account: the reference 2838 is what manutenção would be at 80 kg
    // (the weight the day target 2980 was stored with).
    expect(
      computeDailyTargets({ ...QA_PROFILE, weight_kg: 80, current_protocol: 'manutencao' }, config)
        .calories_target,
    ).toBe(2838)
    expect(computeDailyTargets({ ...QA_PROFILE, weight_kg: 80 }, config).calories_target).toBe(2980)
    // …and the profile of the readout (80,5 kg, registered that day) gives
    // 2988: the QA day is itself a day whose stored target is not the
    // profile's any more. It stays on the rule (review of 2026-10-04, below).
    expect(computeDailyTargets(QA_PROFILE, config).calories_target).toBe(2988)
  })
})

describe('audit 2026-10-04 R1/R2 — app, GET /today (real loadOfficialDailyState)', () => {
  it.each(ALL)('$name: daily_balance_kcal $before → $after against $reference', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)

    expect(state.local_date).toBe(s.date)
    expect(state.targets.calories_kcal).toBe(s.target)
    expect(state.consumed.calories_kcal).toBe(s.consumed)
    expect(state.daily_balance_kcal).toBe(s.after)
    expect(state.daily_balance_reference_kcal).toBe(s.reference)
    expect(state.daily_balance_includes_exercise).toBe(s.includesExercise)
    expect(state.calculation_version).toBe('bodyflow.daily-state.v3')
    // The food line: against the target, without exercise, before and after.
    expect(state.remaining_food_kcal).toBe(s.remainingFood)
    expect(state.food_excess_kcal).toBe(s.foodExcess)
    expect(state.exercise_kcal).toBe(s.exercise)
    // Open day: the number is provisional and the block is only the stored one.
    expect(state.daily_balance_status).toBe('provisional')
    expect(state.block_7700.current_kcal).toBe(s.block)
    // The app decodes Int.
    for (const value of [
      state.daily_balance_kcal,
      state.daily_balance_reference_kcal,
      state.remaining_food_kcal,
      state.food_excess_kcal,
    ]) {
      expect(Number.isInteger(value)).toBe(true)
      expect(Object.is(value, -0)).toBe(false)
    }
  })

  it('QA account: "Restam" 2439 before and after, and the workout is outside both numbers', async () => {
    vi.setSystemTime(new Date(QA_GAIN.now))
    const withWorkout = await today(QA_GAIN)
    const noWorkout = await today({ ...QA_GAIN, exercise: 0 })

    expect(withWorkout.remaining_food_kcal).toBe(2439)
    expect(noWorkout.remaining_food_kcal).toBe(2439)
    expect(withWorkout.daily_balance_kcal).toBe(-2297)
    expect(noWorkout.daily_balance_kcal).toBe(-2297)
    expect(withWorkout.protocol).toBe('ganho_massa')
    expect(withWorkout.block_7700.enabled).toBe(false)
  })

  it('ganho de massa eating exactly 2980: +142 with and without the 322 kcal workout', async () => {
    vi.setSystemTime(new Date(QA_GAIN.now))

    expect((await today(QA_GAIN_ON_TARGET_WORKOUT)).daily_balance_kcal).toBe(142)
    expect((await today(QA_GAIN_ON_TARGET_NO_WORKOUT)).daily_balance_kcal).toBe(142)
  })

  it('the multiplier comes from the loaded calc config: with calc.ganho_massa_surplus_multiplier 1,10 the reference is 2709', async () => {
    // Review of 2026-10-04: this case used the QA profile, whose target at
    // 1,10 is 3131 — a day row of 2980 under it is a day whose multiplier
    // changed after the target was stored, which now keeps the legacy number
    // (locked at the end of this file). The profile here is the one whose own
    // target at 1,10 is the 2980 of the row.
    vi.setSystemTime(new Date(GAIN_AT_1_10.now))
    const state = await today(GAIN_AT_1_10, harness(GAIN_AT_1_10, { config: CONFIG_1_10 }))

    expect(state.daily_balance_reference_kcal).toBe(2709)
    expect(state.daily_balance_kcal).toBe(541 - 2709)
    expect(state.remaining_food_kcal).toBe(2439)
  })

  it("recomposição with no deficit_level stored: the closer's default of 500", async () => {
    vi.setSystemTime(new Date(RECOMP_19_05.now))
    const state = await today({
      ...RECOMP_19_05,
      profile: { ...RECOMP_PROFILE, deficit_level: null },
    })

    expect(state.daily_balance_kcal).toBe(-832)
    expect(state.daily_balance_reference_kcal).toBe(2343)
  })

  it.each([
    [400, 2243, -732],
    [600, 2443, -932],
  ] as const)('recomposição with deficit_level %s: against %s → %s', async (level, reference, after) => {
    vi.setSystemTime(new Date(RECOMP_19_05.now))
    const state = await today({
      ...RECOMP_19_05,
      profile: { ...RECOMP_PROFILE, deficit_level: level },
    })

    expect(state.daily_balance_reference_kcal).toBe(reference)
    expect(state.daily_balance_kcal).toBe(after)
  })
})

describe('audit 2026-10-04 R1/R2 — the block credit did not move (real creditDayToBloco)', () => {
  const credit = (s: Scenario, dayStatus: 'complete' | 'user_skipped' | null) =>
    creditDayToBloco({
      hasActivity: true,
      dayStatus,
      caloriesConsumed: s.consumed,
      caloriesTarget: s.target,
      // The closer reads the generated column, which did not change.
      dailyBalance: Number(dayRow(s).daily_balance),
      designDeficit: s.profile.current_protocol === 'recomposicao' ? 500 : 0,
    })

  it('19/05: the credit is still 832 (5.254 → 6.086), and the screen now shows the same 832 as a deficit', async () => {
    vi.setSystemTime(new Date(RECOMP_19_05.now))
    const state = await today(RECOMP_19_05)

    expect(credit(RECOMP_19_05, 'user_skipped')).toBe(832)
    expect(RECOMP_19_05.block + 832).toBe(6086)
    expect(state.daily_balance_kcal).toBe(-832)
    // No credit is projected on the open day.
    expect(state.block_7700.current_kcal).toBe(5254)
  })

  it('21/05: the credit is still 897 (5.757 → 6.654), and the screen shows -897', async () => {
    vi.setSystemTime(new Date(RECOMP_21_05.now))
    const state = await today(RECOMP_21_05)

    expect(credit(RECOMP_21_05, 'complete')).toBe(897)
    expect(RECOMP_21_05.block + 897).toBe(6654)
    expect(state.daily_balance_kcal).toBe(-897)
    expect(state.block_7700.current_kcal).toBe(5757)
  })

  it('declared as it is — open day 22/05 12:37: the screen shows -2423 while a closing now would credit 500', async () => {
    // 568 kcal is under 50% of 1843: the closer treats it as under-logging
    // and credits only the programmed deficit. Screen and block coincide
    // only on a day that credits normally (RC above).
    vi.setSystemTime(new Date(RECOMP_22_05_OPEN.now))
    const state = await today(RECOMP_22_05_OPEN)

    expect(state.daily_balance_kcal).toBe(-2423)
    expect(state.daily_balance_status).toBe('provisional')
    expect(state.block_7700.current_kcal).toBe(6654)
    expect(credit(RECOMP_22_05_OPEN, 'complete')).toBe(500)
  })

  it('declared as it is — ganho de massa / manutenção: the closer still credits target + exercise − consumed', async () => {
    // The client wrote on 08/05/2026 that the 7700 block is replaced by a
    // 14-day block in these protocols; that block is not defined (RC above).
    vi.setSystemTime(new Date(MAINTENANCE.now))

    expect((await today(MAINTENANCE)).daily_balance_kcal).toBe(0)
    expect(credit(MAINTENANCE, 'complete')).toBe(400)
    expect((await today(QA_GAIN_ON_TARGET_WORKOUT)).daily_balance_kcal).toBe(142)
    expect(credit(QA_GAIN_ON_TARGET_WORKOUT, 'complete')).toBe(322)
  })
})

describe('audit 2026-10-04 R1/R2 — Flow context (real processAuthenticatedMessage)', () => {
  it.each(
    CHANGED,
  )('$name: the line reads $after, the same number as the Today screen', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const lines = await flowContext(s)
    const state = await today(s)

    expect(balanceLine(lines)).toBe(expenditureLine(s))
    expect(balanceLine(lines)).toContain(`: ${state.daily_balance_kcal} kcal (negativo=déficit`)
    // The old number is nowhere in what the model reads (unless it equals a
    // number that is legitimately there).
    if (s.before !== s.after && s.before !== 0) {
      expect(lines.join('\n')).not.toContain(`${s.before} kcal`)
    }
    // The food line did not move.
    expect(foodLine(lines)).toBe(
      s.foodExcess > 0
        ? `- Para COMIDA hoje (consumido − meta, SEM exercício): excedente de ${s.foodExcess} kcal acima da meta`
        : `- Para COMIDA hoje (meta − consumido, SEM exercício): restam ${s.remainingFood} kcal`,
    )
    expect(lines).toContain(
      `- Exercício hoje: ${s.exercise} kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida`,
    )
    expect(lines.some((line) => line.startsWith('- REGRA: exercício NÃO libera comida'))).toBe(true)
    // Never the unlabeled legacy line of the WhatsApp context.
    expect(lines.join('\n')).not.toContain('- Balanço calórico de hoje: ')
  })

  it.each([
    QA_GAIN,
    QA_GAIN_ON_TARGET_WORKOUT,
    MAINTENANCE,
    DERIVED_GAIN_WORKOUT,
  ])('$name: the energy lines never say "7700" nor "bloco"', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const energy = (await flowContext(s)).filter((line) =>
      /^- (?:Para COMIDA|Exercício hoje|Balanço calórico de hoje|REGRA)/.test(line),
    )

    expect(energy).toHaveLength(4)
    expect(energy.join('\n')).not.toMatch(/7\.?700|bloco/i)
    expect(energy.join('\n')).not.toContain('COM exercício')
  })

  it.each([
    RECOMP_19_05,
    RECOMP_21_05,
    RECOMP_22_05_OPEN,
  ])('$name: the line says provisional, credited only at closing, and not what is left to eat', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const line = balanceLine(await flowContext(s))

    expect(line).toContain('é o déficit ou superávit real do dia até agora')
    expect(line).toContain('provisório até o dia fechar')
    expect(line).toContain('o crédito no bloco 7700 só acontece no fechamento do dia')
    expect(line.endsWith('NÃO é o que resta para comer')).toBe(true)
    expect(line).not.toContain('é o número que o fechamento')
  })

  it('protocol not set: the line of before, byte for byte', async () => {
    vi.setSystemTime(new Date(NULL_PROTOCOL.now))
    const lines = await flowContext(NULL_PROTOCOL)

    expect(balanceLine(lines)).toBe(legacyLine(NULL_PROTOCOL, null))
    expect(balanceLine(lines)).toContain(': -2761 kcal')
    expect(foodLine(lines)).toBe(
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2439 kcal',
    )
  })

  it('the multiplier comes from the loaded calc config in the Flow too (1,10 → 2709)', async () => {
    vi.setSystemTime(new Date(GAIN_AT_1_10.now))

    expect(balanceLine(await flowContext(GAIN_AT_1_10, CONFIG_1_10))).toContain(
      'gasto de referência de 2709 kcal; o exercício já está no fator de atividade e não é somado): -2168 kcal',
    )
  })
})

describe('audit 2026-10-04 R1/R2 — consulta_progresso called by the model on the Flow', () => {
  const FOOD_RULE =
    'Exercício não libera comida nem apaga excedente: a meta é a mesma com ou sem treino e o que resta para comida é meta − consumido, sem exercício.'

  it.each([
    RECOMP_19_05,
    RECOMP_21_05,
    RECOMP_22_05_OPEN,
  ])('$name: balanco_do_dia_com_exercicio_kcal $after against gasto_de_referencia_kcal $reference', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const energy = await flowTool(s)

    expect(energy).toEqual({
      meta_kcal: s.target,
      consumido_kcal: s.consumed,
      ...(s.foodExcess > 0
        ? { excedente_de_comida_kcal: s.foodExcess }
        : { restam_para_comida_kcal: s.remainingFood }),
      exercicio_kcal: s.exercise,
      gasto_de_referencia_kcal: s.reference,
      balanco_do_dia_com_exercicio_kcal: s.after,
      regra: `${FOOD_RULE} O gasto do treino fica à parte; balanco_do_dia_com_exercicio_kcal é consumido − (gasto_de_referencia_kcal + exercicio_kcal): o déficit (negativo) ou superávit (positivo) real do dia até agora, provisório até o dia fechar, quando é creditado no bloco 7700. Não é o que resta para comer.`,
    })
  })

  it.each([
    QA_GAIN,
    QA_GAIN_ON_TARGET_WORKOUT,
    QA_GAIN_ON_TARGET_NO_WORKOUT,
    MAINTENANCE,
    DERIVED_GAIN_WORKOUT,
    DERIVED_GAIN_NO_WORKOUT,
  ])('$name: balanco_do_dia_sem_exercicio_kcal $after against gasto_de_referencia_kcal $reference', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const energy = await flowTool(s)

    expect(energy).toEqual({
      meta_kcal: s.target,
      consumido_kcal: s.consumed,
      restam_para_comida_kcal: s.remainingFood,
      exercicio_kcal: s.exercise,
      gasto_de_referencia_kcal: s.reference,
      balanco_do_dia_sem_exercicio_kcal: s.after,
      regra: `${FOOD_RULE} O gasto do treino fica à parte; balanco_do_dia_sem_exercicio_kcal é consumido − gasto_de_referencia_kcal (negativo = déficit, positivo = superávit): o exercício já está no fator de atividade e não é somado. Não é o que resta para comer.`,
    })
    expect(JSON.stringify(energy)).not.toMatch(/7\.?700|bloco/i)
  })

  it('protocol not set: the key and the rule of before', async () => {
    vi.setSystemTime(new Date(NULL_PROTOCOL.now))

    expect(await flowTool(NULL_PROTOCOL)).toEqual({
      meta_kcal: 2980,
      consumido_kcal: 541,
      restam_para_comida_kcal: 2439,
      exercicio_kcal: 322,
      balanco_do_dia_com_exercicio_kcal: -2761,
      regra: `${FOOD_RULE} O gasto do treino fica à parte; balanco_do_dia_com_exercicio_kcal não é o que resta para comer.`,
    })
  })
})

describe('audit 2026-10-04 R1/R2 — the switch: off brings every number back', () => {
  it.each(
    CHANGED,
  )('$name: all off → $before again on the Today screen, in the Flow line and in the tool', async (s) => {
    Object.assign(switches, ALL_OFF)
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)

    expect(state.daily_balance_kcal).toBe(s.before)
    expect(state.daily_balance_reference_kcal).toBe(s.target)
    expect(state.daily_balance_includes_exercise).toBe(true)
    expect(state.remaining_food_kcal).toBe(s.remainingFood)
    expect(state.food_excess_kcal).toBe(s.foodExcess)

    clearCalcConfigCache()
    expect(balanceLine(await flowContext(s))).toBe(legacyLine(s, s.profile.current_protocol))

    clearCalcConfigCache()
    const energy = await flowTool(s)
    expect(energy.balanco_do_dia_com_exercicio_kcal).toBe(s.before)
    expect(energy).not.toHaveProperty('balanco_do_dia_sem_exercicio_kcal')
    expect(energy).not.toHaveProperty('gasto_de_referencia_kcal')
  })

  it('one protocol off leaves the other two on', async () => {
    switches.ganho_massa = false

    vi.setSystemTime(new Date(QA_GAIN.now))
    expect((await today(QA_GAIN)).daily_balance_kcal).toBe(-2761)
    expect((await today(MAINTENANCE)).daily_balance_kcal).toBe(0)
    vi.setSystemTime(new Date(RECOMP_19_05.now))
    expect((await today(RECOMP_19_05)).daily_balance_kcal).toBe(-832)
  })
})

describe('audit 2026-10-04 R1/R2 — a true Flow sentence about the day balance is not rewritten into "restam"', () => {
  // Ganho de massa, consumed between the reference (2838) and the target
  // (2980): 80 kcal of food are still left AND the day is a true surplus of
  // 62 kcal against expenditure. The reconciler of the prose only knows the
  // food balance; with a card in the answer it turned "superávit de 62 kcal"
  // into "restam 80 kcal".
  const BETWEEN: Scenario = {
    ...QA_GAIN,
    name: 'ganho de massa entre a referência e a meta (2900 / 2980)',
    consumed: 2900,
    before: -402,
    after: 62,
    remainingFood: 80,
  }
  const CARD = '🔥 Consumido: 2900 / 2980 kcal (97%)\n🎯 Restam: 80 kcal'
  // The Flow channel records no `llm.balance_prose_reconciled` event (its
  // telemetry carries no content), so the text the patient gets is the proof.
  const answer = async (s: Scenario, content: string): Promise<string> => {
    vi.setSystemTime(new Date(s.now))
    const h = harness(s, { script: [{ content }] })
    return (await flow(s, h)).text
  }

  it('the scenario: food left 80, day balance +62, on the screen and in the context', async () => {
    vi.setSystemTime(new Date(BETWEEN.now))
    const state = await today(BETWEEN)
    const lines = await flowContext(BETWEEN)

    expect(state.remaining_food_kcal).toBe(80)
    expect(state.daily_balance_kcal).toBe(62)
    expect(foodLine(lines)).toBe(
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 80 kcal',
    )
    expect(balanceLine(lines)).toContain('não é somado): 62 kcal')
  })

  it('"superávit de 62 kcal" next to a card stays as the model wrote it', async () => {
    const text = await answer(
      BETWEEN,
      `Hoje você está com superávit de 62 kcal em relação ao seu gasto do dia.\n\n${CARD}`,
    )

    expect(text).toContain('superávit de 62 kcal em relação ao seu gasto do dia')
    expect(text).not.toContain('restam 80 kcal em relação')
  })

  it('"62 kcal de superávit" (the other word order) stays too', async () => {
    const text = await answer(
      BETWEEN,
      `Contra o seu gasto do dia são 62 kcal de superávit.\n\n${CARD}`,
    )

    expect(text).toContain('são 62 kcal de superávit')
  })

  it('a surplus with another number is still corrected to the food line (not the day balance: the model made it up)', async () => {
    const text = await answer(BETWEEN, `Hoje você está com superávit de 500 kcal.\n\n${CARD}`)

    expect(text).toContain('Hoje você está com restam 80 kcal.')
    expect(text).not.toContain('superávit de 500')
  })

  it('switch off (the behaviour of before): the same true sentence is rewritten into "restam 80 kcal"', async () => {
    switches.ganho_massa = false
    const text = await answer(
      BETWEEN,
      `Hoje você está com superávit de 62 kcal em relação ao seu gasto do dia.\n\n${CARD}`,
    )

    expect(text).toContain('restam 80 kcal em relação ao seu gasto do dia')
    expect(text).not.toContain('superávit de 62')
  })

  it('recomposição 19/05: "déficit de 832 kcal" stays although the food line is an excess of 233', async () => {
    const card = '🔥 Consumido: 2076 / 1843 kcal (113%)\n🎯 Excedente: 233 kcal'
    const kept = await answer(
      RECOMP_19_05,
      `Com o treino, o dia está com déficit de 832 kcal até agora.\n\n${card}`,
    )

    expect(kept).toContain('déficit de 832 kcal até agora')

    // The balance against the target (the number of before) is not exempt.
    const fixed = await answer(
      RECOMP_19_05,
      `Com o treino, o dia está com déficit de 332 kcal até agora.\n\n${card}`,
    )
    expect(fixed).toContain('o dia está com excedente de 233 kcal até agora')
    expect(fixed).not.toContain('déficit de 332')
  })
})

// ════════════════════════════════════════════════════════════════════════════
// Review of 2026-10-04 (balance lens). Every input the reviewer listed, through
// the real loadOfficialDailyState, the real Flow pipeline and the real tool.
// ════════════════════════════════════════════════════════════════════════════

/** A day whose stored target was written under another protocol's rule. */
interface ChangeDay extends Scenario {
  /** What the Today screen and the Flow said before the review. */
  wrong: number
  wrongReference: number
}

// homem, 81 kg, 180 cm, 44 anos, moderado (the reviewer's profile): manutenção
// 2666, ganho de massa 2799, recomposição/500 1564 (BMR 1720 × 1,2 = 2064).
const CHANGE_TO_RECOMP: ChangeDay = {
  name: 'dia de troca: manhã em ganho de massa (2799 gravada), recomposição/500 ao meio-dia, 2500 consumido',
  now: '2026-10-04T15:03:40.503Z',
  date: '2026-10-04',
  profile: { ...DERIVED_GAIN_PROFILE, current_protocol: 'recomposicao', deficit_level: 500 },
  target: 2799,
  consumed: 2500,
  exercise: 0,
  dayStatus: null,
  block: 0,
  // The legacy number: consumed − stored target − exercise (also HEAD's).
  before: -299,
  after: -299,
  reference: 2799,
  includesExercise: true,
  remainingFood: 299,
  foodExcess: 0,
  // 2500 − (2799 + 500) − 0: a deficit, when the client's rule gives
  // 2500 − 2064 = +436, a surplus.
  wrong: -799,
  wrongReference: 3299,
}
const CHANGE_TO_GAIN: ChangeDay = {
  ...CHANGE_TO_RECOMP,
  name: 'dia de troca, o inverso: manhã em recomposição (1564 gravada), ganho de massa ao meio-dia, 2000 consumido',
  profile: DERIVED_GAIN_PROFILE,
  target: 1564,
  consumed: 2000,
  before: 436,
  after: 436,
  reference: 1564,
  remainingFood: 0,
  foodExcess: 436,
  // 2000 − round(1564 ÷ 1,05): a surplus of 510, when the client's rule gives
  // 2000 − 2666 = −666, a deficit.
  wrong: 510,
  wrongReference: 1490,
}
const FIRST_DAY_TO_RECOMP: ChangeDay = {
  ...CHANGE_TO_RECOMP,
  name: 'primeiro dia: 2666 gravada sem protocolo, depois recomposição, 1800 consumido',
  profile: { ...DERIVED_GAIN_PROFILE, current_protocol: 'recomposicao', deficit_level: null },
  target: 2666,
  consumed: 1800,
  before: -866,
  after: -866,
  reference: 2666,
  remainingFood: 866,
  foodExcess: 0,
  // 1800 − (2666 + 500), when the client's rule gives 1800 − 2064 = −264.
  wrong: -1366,
  wrongReference: 3166,
}
const CHANGE_DAYS: ChangeDay[] = [CHANGE_TO_RECOMP, CHANGE_TO_GAIN, FIRST_DAY_TO_RECOMP]

const FOOD_RULE_OF_THE_TOOL =
  'Exercício não libera comida nem apaga excedente: a meta é a mesma com ou sem treino e o que resta para comida é meta − consumido, sem exercício.'
/** The legacy line of a day whose stored target is of another rule: no block claim. */
const changeDayLine = (s: Scenario): string =>
  `- Balanço calórico de hoje COM exercício (consumido − meta − exercício): ${s.after} kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer`

describe('review 2026-10-04 — day of a protocol change: the legacy number on the Today screen AND in the Flow', () => {
  it('the scenarios are what they say: the three targets of the reviewer profile', async () => {
    vi.setSystemTime(new Date(CHANGE_TO_RECOMP.now))
    const config = await loadCalcConfig(harness(CHANGE_TO_RECOMP).deps.supabase)
    const under = (current_protocol: Protocol) =>
      computeDailyTargets({ ...DERIVED_GAIN_PROFILE, current_protocol }, config).calories_target

    expect(under('ganho_massa')).toBe(2799)
    expect(under('recomposicao')).toBe(1564)
    expect(under('manutencao')).toBe(2666)
    // A profile with no protocol yet gets the manutenção rule.
    expect(under(null)).toBe(2666)
    for (const s of CHANGE_DAYS) {
      expect(netBalance(s.consumed, s.target, s.exercise)).toBe(s.after)
    }
  })

  it.each(
    CHANGE_DAYS,
  )('$name: Today $wrong (against $wrongReference) → $after, against the stored target, with exercise', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)

    expect(state.targets.calories_kcal).toBe(s.target)
    expect(state.daily_balance_kcal).toBe(s.after)
    expect(state.daily_balance_reference_kcal).toBe(s.target)
    expect(state.daily_balance_includes_exercise).toBe(true)
    // Only the balance falls back: the protocol published is the profile's.
    expect(state.protocol).toBe(s.profile.current_protocol)
    // The food line is the same as ever.
    expect(state.remaining_food_kcal).toBe(s.remainingFood)
    expect(state.food_excess_kcal).toBe(s.foodExcess)
    expect(Number.isInteger(state.daily_balance_kcal)).toBe(true)
    expect(Number.isInteger(state.daily_balance_reference_kcal)).toBe(true)
  })

  it.each(
    CHANGE_DAYS,
  )('$name: the Flow line reads $after, the same number as the Today screen, and claims no block credit', async (s) => {
    vi.setSystemTime(new Date(s.now))
    const lines = await flowContext(s)
    const state = await today(s)

    expect(balanceLine(lines)).toBe(changeDayLine(s))
    expect(balanceLine(lines)).toContain(`: ${state.daily_balance_kcal} kcal (negativo=déficit`)
    expect(lines.join('\n')).not.toContain(`${s.wrong} kcal`)
    expect(lines.join('\n')).not.toContain(`${s.wrongReference} kcal`)
    expect(lines.join('\n')).not.toContain('déficit ou superávit real do dia')
    expect(lines.join('\n')).not.toContain('déficit programado − este número')
    expect(foodLine(lines)).toBe(
      s.foodExcess > 0
        ? `- Para COMIDA hoje (consumido − meta, SEM exercício): excedente de ${s.foodExcess} kcal acima da meta`
        : `- Para COMIDA hoje (meta − consumido, SEM exercício): restam ${s.remainingFood} kcal`,
    )
  })

  it.each(
    CHANGE_DAYS,
  )('$name: consulta_progresso gives the same $after under the legacy key', async (s) => {
    vi.setSystemTime(new Date(s.now))

    expect(await flowTool(s)).toEqual({
      meta_kcal: s.target,
      consumido_kcal: s.consumed,
      ...(s.foodExcess > 0
        ? { excedente_de_comida_kcal: s.foodExcess }
        : { restam_para_comida_kcal: s.remainingFood }),
      exercicio_kcal: s.exercise,
      balanco_do_dia_com_exercicio_kcal: s.after,
      regra: `${FOOD_RULE_OF_THE_TOOL} O gasto do treino fica à parte; balanco_do_dia_com_exercicio_kcal não é o que resta para comer.`,
    })
  })

  it('a workout on the day of the change is inside the legacy number, on the screen and in the Flow', async () => {
    const s: Scenario = { ...CHANGE_TO_RECOMP, exercise: 300, before: -599, after: -599 }
    vi.setSystemTime(new Date(s.now))

    expect((await today(s)).daily_balance_kcal).toBe(-599)
    expect(balanceLine(await flowContext(s))).toBe(changeDayLine(s))
    expect((await flowTool(s)).balanco_do_dia_com_exercicio_kcal).toBe(-599)
  })

  it('the day after (the day row stores the target of the new protocol): the rule of the protocol again', async () => {
    const s: Scenario = {
      ...CHANGE_TO_RECOMP,
      name: 'recomposição com a meta de recomposição gravada (1564), 2500 consumido',
      target: 1564,
      before: 936,
      after: 436,
      reference: 2064,
      remainingFood: 0,
      foodExcess: 936,
    }
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)

    // The client's rule: 2500 − (BMR × 1,2 = 2064) − 0 = +436.
    expect(state.daily_balance_kcal).toBe(436)
    expect(state.daily_balance_reference_kcal).toBe(2064)
    expect(balanceLine(await flowContext(s))).toBe(expenditureLine(s))
  })

  it('a sentence quoting the number of before ("déficit de 299 kcal" over a food excess of 201) is corrected to the food line again', async () => {
    // 3000 consumed against the 2799 stored: before the review the day
    // balance was 3000 − (2799 + 500) = −299, so the prose reconciler spared
    // "déficit de 299 kcal" as a true number of the day. The day now keeps the
    // legacy number (+201, the food excess itself) and nothing is spared.
    const s: Scenario = { ...CHANGE_TO_RECOMP, consumed: 3000, remainingFood: 0, foodExcess: 201 }
    const content = `Com a recomposição, o dia está com déficit de 299 kcal até agora.\n\n🔥 Consumido: 3000 / 2799 kcal (107%)\n🎯 Excedente: 201 kcal`
    vi.setSystemTime(new Date(s.now))
    expect((await today(s)).daily_balance_kcal).toBe(201)

    const fixed = (await flow(s, harness(s, { script: [{ content }] }))).text
    expect(fixed).toContain('o dia está com excedente de 201 kcal até agora')
    expect(fixed).not.toContain('déficit de 299')

    // Switch off: the sentence is spared again (the behaviour of before).
    dayRowGuard.enabled = false
    clearCalcConfigCache()
    const kept = (await flow(s, harness(s, { script: [{ content }] }))).text
    expect(kept).toContain('o dia está com déficit de 299 kcal até agora')
  })

  // Second review of 2026-10-04 (LOW, test gap). pipeline.ts spares a sentence
  // about the day balance only when the number is the one of the §2c rule
  // (`flowDay?.basis === 'expenditure'`), never the legacy number. The mutant
  // `flowDay ? { dayBalance: flowDay.balance } : {}` kept the 2530 tests of
  // the agent green: in the case above the legacy number IS the food excess
  // (+201), so it cannot tell the two apart. With a workout the legacy number
  // (consumed − target − exercise) and the food line differ.
  it('with a workout on the day of the change (3000 / 2799, treino 500): the legacy number is -299 and "déficit de 299 kcal" is still corrected to "excedente de 201 kcal"', async () => {
    const s: Scenario = {
      ...CHANGE_TO_RECOMP,
      consumed: 3000,
      exercise: 500,
      before: -299,
      after: -299,
      remainingFood: 0,
      foodExcess: 201,
    }
    const content = `Com o treino, o dia está com déficit de 299 kcal até agora.\n\n🔥 Consumido: 3000 / 2799 kcal (107%)\n🎯 Excedente: 201 kcal`
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)
    // The legacy number, with exercise: 3000 − 2799 − 500.
    expect(state.daily_balance_kcal).toBe(-299)
    expect(state.daily_balance_includes_exercise).toBe(true)
    expect(state.daily_balance_reference_kcal).toBe(2799)
    expect(state.food_excess_kcal).toBe(201)
    expect(balanceLine(await flowContext(s))).toBe(changeDayLine(s))

    clearCalcConfigCache()
    const fixed = (await flow(s, harness(s, { script: [{ content }] }))).text
    expect(fixed).toContain('o dia está com excedente de 201 kcal até agora')
    expect(fixed).not.toContain('déficit de 299')
  })

  it('protocol not set (3100 / 2980, treino 322): the legacy number is -202 and "déficit de 202 kcal" is corrected to "excedente de 120 kcal", as before', async () => {
    const s: Scenario = {
      ...NULL_PROTOCOL,
      name: 'protocolo ainda não definido (3100 / 2980, treino 322)',
      consumed: 3100,
      before: -202,
      after: -202,
      remainingFood: 0,
      foodExcess: 120,
    }
    const content = `Com o treino, o dia está com déficit de 202 kcal até agora.\n\n🔥 Consumido: 3100 / 2980 kcal (104%)\n🎯 Excedente: 120 kcal`
    vi.setSystemTime(new Date(s.now))
    expect(netBalance(s.consumed, s.target, s.exercise)).toBe(-202)
    const state = await today(s)
    expect(state.protocol).toBeNull()
    expect(state.daily_balance_kcal).toBe(-202)
    expect(state.daily_balance_includes_exercise).toBe(true)
    expect(state.food_excess_kcal).toBe(120)
    expect(balanceLine(await flowContext(s))).toBe(legacyLine(s, null))

    clearCalcConfigCache()
    const fixed = (await flow(s, harness(s, { script: [{ content }] }))).text
    expect(fixed).toContain('o dia está com excedente de 120 kcal até agora')
    expect(fixed).not.toContain('déficit de 202')
  })

  it.each(
    CHANGE_DAYS,
  )('$name — DAY_BALANCE_DAY_ROW_GUARD off: $wrong against $wrongReference comes back on the screen, in the Flow line and in the tool', async (s) => {
    dayRowGuard.enabled = false
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)
    const recomp = s.profile.current_protocol === 'recomposicao'

    expect(state.daily_balance_kcal).toBe(s.wrong)
    expect(state.daily_balance_reference_kcal).toBe(s.wrongReference)
    expect(state.daily_balance_includes_exercise).toBe(recomp)

    clearCalcConfigCache()
    expect(balanceLine(await flowContext(s))).toBe(
      expenditureLine({
        ...s,
        after: s.wrong,
        reference: s.wrongReference,
        includesExercise: recomp,
      }),
    )

    clearCalcConfigCache()
    const energy = await flowTool(s)
    expect(energy.gasto_de_referencia_kcal).toBe(s.wrongReference)
    expect(
      recomp ? energy.balanco_do_dia_com_exercicio_kcal : energy.balanco_do_dia_sem_exercicio_kcal,
    ).toBe(s.wrong)
  })
})

describe('review 2026-10-04 — a new weight is not a change of protocol', () => {
  it('QA account 04/10: stored 2980 (80 kg), profile at 80,5 kg (2988) → still -2297 against 2838, on the screen, in the Flow and in the tool', async () => {
    vi.setSystemTime(new Date(QA_GAIN.now))
    const state = await today(QA_GAIN)

    expect(state.daily_balance_kcal).toBe(-2297)
    expect(state.daily_balance_reference_kcal).toBe(2838)
    expect(state.daily_balance_includes_exercise).toBe(false)
    expect(balanceLine(await flowContext(QA_GAIN))).toBe(expenditureLine(QA_GAIN))
    expect((await flowTool(QA_GAIN)).balanco_do_dia_sem_exercicio_kcal).toBe(-2297)
  })

  it('declared as it is — with the target the profile gives now (2988) the number would be -2305 against 2846', async () => {
    // RC above: on a day the weight changes, the expenditure is still derived
    // from the target stored in the morning.
    const s: Scenario = { ...QA_GAIN, target: 2988, after: -2305, reference: 2846 }
    vi.setSystemTime(new Date(s.now))

    expect((await today(s)).daily_balance_kcal).toBe(-2305)
    expect((await today(s)).daily_balance_reference_kcal).toBe(2846)
  })
})

describe('review 2026-10-04 — closed day whose row carries another protocol than the profile', () => {
  // The day row keeps `current_protocol` only after the closing.
  const CLOSED_RECOMP_ROW: Scenario = {
    ...RECOMP_19_05,
    name: 'linha do dia fechada em recomposição (2076 / 1843 / 565), perfil hoje em ganho de massa',
    profile: QA_PROFILE,
    row: { current_protocol: 'recomposicao', day_closed: true },
  }
  const CLOSED_GAIN_ROW: Scenario = {
    ...QA_GAIN_ON_TARGET_WORKOUT,
    name: 'linha do dia fechada em ganho de massa (2980 / 2980 / 322), perfil hoje em recomposição/500',
    profile: RECOMP_PROFILE,
    row: { current_protocol: 'ganho_massa', day_closed: true },
  }

  it('row recomposição, profile ganho de massa: -832 against 2343 on the screen (was -332 against 1843) and in the Flow (was +321 against 1755)', async () => {
    const s = CLOSED_RECOMP_ROW
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)

    expect(state.protocol).toBe('recomposicao')
    expect(state.daily_balance_kcal).toBe(-832)
    expect(state.daily_balance_reference_kcal).toBe(2343)
    expect(state.daily_balance_includes_exercise).toBe(true)
    expect(balanceLine(await flowContext(s))).toBe(expenditureLine(s))
    expect(await flowTool(s)).toMatchObject({
      gasto_de_referencia_kcal: 2343,
      balanco_do_dia_com_exercicio_kcal: -832,
    })
  })

  it('row ganho de massa, profile recomposição/500: +142 against 2838 on the screen and in the Flow (was -822 against 3480)', async () => {
    const s = CLOSED_GAIN_ROW
    vi.setSystemTime(new Date(s.now))
    const state = await today(s)

    expect(state.protocol).toBe('ganho_massa')
    expect(state.daily_balance_kcal).toBe(142)
    expect(state.daily_balance_reference_kcal).toBe(2838)
    expect(state.daily_balance_includes_exercise).toBe(false)
    expect(balanceLine(await flowContext(s))).toBe(expenditureLine(s))
    const energy = await flowTool(s)
    expect(energy).toMatchObject({
      gasto_de_referencia_kcal: 2838,
      balanco_do_dia_sem_exercicio_kcal: 142,
    })
    expect(energy).not.toHaveProperty('balanco_do_dia_com_exercicio_kcal')
  })

  it('DAY_BALANCE_DAY_ROW_GUARD off: the two numbers of before, one on the screen and another in the Flow', async () => {
    dayRowGuard.enabled = false
    vi.setSystemTime(new Date(CLOSED_RECOMP_ROW.now))
    const state = await today(CLOSED_RECOMP_ROW)

    expect(state.protocol).toBe('recomposicao')
    expect(state.daily_balance_kcal).toBe(-332)
    expect(state.daily_balance_reference_kcal).toBe(1843)
    clearCalcConfigCache()
    expect(balanceLine(await flowContext(CLOSED_RECOMP_ROW))).toContain(
      'gasto de referência de 1755 kcal; o exercício já está no fator de atividade e não é somado): 321 kcal',
    )

    clearCalcConfigCache()
    vi.setSystemTime(new Date(CLOSED_GAIN_ROW.now))
    expect((await today(CLOSED_GAIN_ROW)).daily_balance_kcal).toBe(142)
    clearCalcConfigCache()
    expect(balanceLine(await flowContext(CLOSED_GAIN_ROW))).toContain(
      'gasto do dia = 3480 kcal de gasto de referência + 322 kcal de exercício): -822 kcal',
    )
  })
})

describe('review 2026-10-04 — the multiplier of the calc config', () => {
  it('reaches consulta_progresso through the pipeline: 1,10 → gasto_de_referencia_kcal 2709, balanco_do_dia_sem_exercicio_kcal -2168', async () => {
    // Dropping the calc config where the pipeline builds the tool context
    // left every suite green; with the default 1,05 this reads 2838 / -2297.
    vi.setSystemTime(new Date(GAIN_AT_1_10.now))
    const energy = await flowTool(GAIN_AT_1_10, CONFIG_1_10)

    expect(energy).toMatchObject({
      meta_kcal: 2980,
      consumido_kcal: 541,
      restam_para_comida_kcal: 2439,
      exercicio_kcal: 322,
      gasto_de_referencia_kcal: 2709,
      balanco_do_dia_sem_exercicio_kcal: -2168,
    })
    // The same number on the screen and in the context of the same turn.
    clearCalcConfigCache()
    const state = await today(GAIN_AT_1_10, harness(GAIN_AT_1_10, { config: CONFIG_1_10 }))
    expect(state.daily_balance_kcal).toBe(-2168)
    expect(state.daily_balance_reference_kcal).toBe(2709)
  })

  it('the 1,10 scenario is what it says: that profile gives 2980 at 1,10, and the QA profile gives 3131', async () => {
    vi.setSystemTime(new Date(GAIN_AT_1_10.now))
    const config = await loadCalcConfig(
      harness(GAIN_AT_1_10, { config: CONFIG_1_10 }).deps.supabase,
    )

    expect(config.ganho_massa_surplus_multiplier).toBe(1.1)
    expect(computeDailyTargets(GAIN_AT_1_10.profile, config).calories_target).toBe(2980)
    expect(computeDailyTargets(QA_PROFILE, config).calories_target).toBe(3131)
    expect(
      computeDailyTargets({ ...QA_PROFILE, current_protocol: 'manutencao' }, config)
        .calories_target,
    ).toBe(2846)
  })

  it('declared as it is — multiplier changed after the day target was stored (QA row 2980, config now 1,10): the legacy -2761 everywhere', async () => {
    // 2980 is nearer to what manutenção gives now (2846) than to ganho de
    // massa at 1,10 (3131): the day keeps the legacy number (RC above).
    const s: Scenario = {
      ...QA_GAIN,
      name: 'GAIN_MULTIPLIER_CHANGED',
      after: -2761,
      reference: 2980,
      includesExercise: true,
    }
    vi.setSystemTime(new Date(s.now))
    const state = await today(s, harness(s, { config: CONFIG_1_10 }))

    expect(state.daily_balance_kcal).toBe(-2761)
    expect(state.daily_balance_reference_kcal).toBe(2980)
    expect(state.daily_balance_includes_exercise).toBe(true)
    clearCalcConfigCache()
    expect(balanceLine(await flowContext(s, CONFIG_1_10))).toBe(changeDayLine(s))
    clearCalcConfigCache()
    expect((await flowTool(s, CONFIG_1_10)).balanco_do_dia_com_exercicio_kcal).toBe(-2761)
  })

  it('saved as the JSON text "1.05": target 2799, reference 2666, +134 on the screen, in the Flow and in the tool (was 2799 / +1)', async () => {
    // The reviewer's case, through the real loader: ganho de massa, no target
    // stored on the day row, 2800 consumed. The target was computed with 1,05
    // (JS coercion in `tdee * multiplier`) while the reference was not.
    const config: Row[] = [
      ...STAGING_CONFIG,
      { key: 'calc.ganho_massa_surplus_multiplier', value: '1.05' },
    ]
    const s: Scenario = {
      ...DERIVED_GAIN_NO_WORKOUT,
      name: 'multiplicador gravado como texto "1.05", sem meta gravada no dia, 2800 consumido',
      consumed: 2800,
      before: 1,
      after: 134,
      reference: 2666,
      remainingFood: 0,
      foodExcess: 1,
      // The generated column with no stored target: consumed − 0 − exercise.
      row: { calories_target: null, daily_balance: 2800 },
    }
    vi.setSystemTime(new Date(s.now))
    const loaded = await loadCalcConfig(harness(s, { config }).deps.supabase)
    expect(loaded.ganho_massa_surplus_multiplier).toBe('1.05')

    clearCalcConfigCache()
    const state = await today(s, harness(s, { config }))
    expect(state.targets.calories_kcal).toBe(2799)
    expect(state.daily_balance_reference_kcal).toBe(2666)
    expect(state.daily_balance_kcal).toBe(134)
    expect(state.food_excess_kcal).toBe(1)

    clearCalcConfigCache()
    expect(balanceLine(await flowContext(s, config))).toBe(expenditureLine(s))

    clearCalcConfigCache()
    expect(await flowTool(s, config)).toMatchObject({
      meta_kcal: 2799,
      excedente_de_comida_kcal: 1,
      gasto_de_referencia_kcal: 2666,
      balanco_do_dia_sem_exercicio_kcal: 134,
    })
  })
})
