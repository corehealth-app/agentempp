/**
 * Audit 2026-10-04 — iPhone, staging, QA account A, build 21b5ec7, Flow chat.
 * RC A: "exercise frees food" (the nº 1 confusion of this agent).
 *
 * The patient wrote in the app's Flow chat (messages.provider 'mobile_flow',
 * created 2026-10-04T15:03:40.503Z, stored exactly like this, no accents):
 *   "Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?"
 * and Flow answered (2026-10-04T15:03:50.524Z, anthropic/claude-sonnet-4.6,
 * 11,024 prompt tokens, 95 completion tokens):
 *   "Sim! Sua meta já considera esse gasto — o balanço de hoje já está com as
 *    322 kcal do treino descontadas. […] O sistema já ajustou tudo na meta de
 *    2.980 kcal."
 *
 * Day row at that turn (daily_snapshots, 2026-10-04): target 2980, protein
 * target 144.00, consumed 541, protein 59.03, carbs 47.32, fat 10.27, exercise
 * 322, water 500 ml, daily_balance -2761, day open. Profile: masculino,
 * 185 cm, 80.5 kg, moderado, 4 treinos, ganho_massa, America/Sao_Paulo.
 * (The handoff table quotes the phrase with accents and Today showing "restam
 * 2.678": that was the screen before the second lunch of 14:59Z. Both are
 * kept below as neighbours; the exact scenario is the staging readout.)
 *
 * Root cause: the per-turn context gave the model only the NET balance (with
 * exercise) under a generic label, no food balance and no rule; nothing
 * deterministic stood between the model and the patient.
 *
 * Fix, Flow channel only:
 *  - the direct question is answered by the system, with no model call
 *    (exercise-food-guard.ts). "Direct question" is a whitelist: the WHOLE
 *    message must be (greeting) + report of today's workout + the question.
 *    The first predicate searched for the question anywhere in the message
 *    and the review of 2026-10-04 showed it hijacking unrelated messages; the
 *    inputs it reproduced through this pipeline are locked below;
 *  - round 2 of that review: a statement ("…consigo comer mais.") is not a
 *    question, no question stands without the report of the workout, "essas N
 *    kcal" must repeat the burn reported, and the answer says the workout
 *    calories are the ones stored. Its inputs are locked below too;
 *  - round 3: a message with no "?" sent right after a question of Flow is
 *    the patient's answer ("Está conseguindo comer…?" → "Treinei hoje e dá
 *    pra comer mais"), and "essas calorias" with no number needs the burn
 *    stated in the report. Its inputs are locked below, with their history;
 *  - the model answers a repeated question only when Flow's last reply is,
 *    character by character, the text the system would send now (no loop);
 *    with other numbers or another day state the system answers again;
 *  - the context labels both balances and states the rule
 *    (flow-energy-context.ts);
 *  - consulta_progresso returns `energia_hoje` instead of the raw net balance.
 * No formula changed. Every test here runs the REAL pipeline entry
 * (processAuthenticatedMessage) or the real tool; nothing is a replica.
 *
 * > RC A — cenário canal WhatsApp NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Travado como está em audit-10-04-whatsapp-context-lock.test.ts.
 * > RC A — cenário pergunta direta fora da gramática NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Erro de digitação, "será que", "consigo", emoji, modalidade fora da lista,
 *   "passar da meta", pergunta sem o relato do treino de hoje, "essas
 *   calorias" sem número e sem gasto dito no relato…: vai para o modelo com o
 *   contexto corrigido. Lista em exercise-food-guard.test.ts
 *   (OUTSIDE_THE_GRAMMAR).
 * > RC A — cenário mensagem mista (relato do treino + pergunta direta + outro pedido, sintoma, alimento ou segunda pergunta) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A resposta do sistema não entra; quem responde é o modelo.
 * > RC A — cenário resposta do MODELO com o contexto corrigido NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inclui a pergunta repetida quando a última resposta do Flow é o mesmo
 *   texto que o sistema daria agora. Só nova rodada no iPhone/staging prova.
 * > RC A — cenário redação da resposta do sistema e da REGRA NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Texto clínico ainda sem aprovação do Roberto.
 * > RC A — cenário exercício no balanço de ganho_massa/manutenção NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Decisão do Roberto em aberto; a resposta só diz que o gasto fica à parte.
 * > RC A — cenário consulta_resumo_periodo (média de daily_balance sem rótulo), "balanço de ontem" e resumo persistente do paciente NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * > RC A — cenário afirmação sem pontuação final ("treinei hoje e posso comer mais") quando o Flow NÃO tinha acabado de perguntar algo NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Sem "?" e sem marca no fim o predicado não separa a pergunta ditada da
 *   afirmação: a mensagem ainda recebe a resposta do sistema, a não ser que a
 *   última resposta do Flow no dia termine em pergunta — aí é resposta do
 *   paciente e vai para o modelo. Com "." ou "!" no fim vai sempre para o
 *   modelo. Os dois lados travados abaixo.
 * > RC A — cenário pergunta ditada sem "?" logo depois de uma pergunta do Flow NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Pela mesma regra vai para o modelo, com o contexto corrigido (travado
 *   abaixo como está).
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import type { PipelineDeps } from '../pipeline.js'
import { mobileFlowSystemPolicy, processAuthenticatedMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import { consultaProgresso } from '../tools.js'

// ── The report, value by value ──────────────────────────────────────────────
const NOW = new Date('2026-10-04T15:03:40.503Z')
const PHRASE = 'Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?'
// Neighbour: the same phrase as the handoff quotes it, with accents.
const PHRASE_ACCENTED = 'Treinei musculação hoje e gastei 322 kcal. Posso comer 322 kcal a mais?'
const WRONG_REPLY =
  'Sim! Sua meta já considera esse gasto — o balanço de hoje já está com as 322 kcal do treino descontadas.\n\nEntão tecnicamente você tem espaço pra comer um pouco mais, mas não precisa "repor" as 322 kcal separadamente. O sistema já ajustou tudo na meta de 2.980 kcal.'
const WRONG_REPLY_AT = '2026-10-04T15:03:50.524Z'

/** The correct answer for the state of the report, character by character. */
const ANSWER_541 =
  'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.'
const ANSWER_302 =
  'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 302 kcal, então restam 2.678 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.'

/** Said when the day has no workout stored, in every protocol. */
const NO_WORKOUT =
  'Não encontrei treino registrado hoje. Quando você registrar o treino no app, o gasto fica à parte e não entra no que resta para comida.'

const USER_ID = 'qa-a'
const TURN_ID = 'mobile_flow/qa-a/audit-10-04-turn'

type Row = Record<string, unknown>

// The birth date was not part of the staging readout (same placeholder as the
// audit of 2026-10-01). On the Flow the day target comes from the day row.
const PROFILE: Row = {
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

/** Day row at the turn of the report. */
const S541: Row = {
  date: '2026-10-04',
  calories_target: 2980,
  protein_target: '144.00',
  calories_consumed: 541,
  protein_g: '59.03',
  carbs_g: '47.32',
  fat_g: '10.27',
  exercise_calories: 322,
  water_consumed_ml: 500,
  daily_balance: -2761,
  deficit_accumulated: 0,
  day_status: null,
  day_closed: false,
  gap_reminder_sent_at: null,
}
/** Neighbour: the same day before the second lunch (Today showed "restam 2.678"). */
const S302: Row = { ...S541, calories_consumed: 302, daily_balance: -3000 }

const PROGRESS: Row = {
  current_streak: 0,
  longest_streak: 0,
  xp_total: 0,
  level: 1,
  blocks_completed: 0,
  deficit_block: 0,
  last_active_date: null,
}

interface Read {
  table: string
  columns: string
  filters: Row
}

interface ScriptedStep {
  content?: string
  toolCalls?: Array<{ id: string; name: string; arguments: string }>
}

interface Fixture {
  day?: Row | null
  profile?: Row
  /** Stored rows of the channel, any order; the current inbound row is added. */
  history?: Row[]
  text?: string
  now?: Date
  script?: ScriptedStep[]
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Row }>
  llmCalls: Array<{ systemPrompt: unknown; messages: unknown[] }>
}

/**
 * Fake client that honours the filters the pipeline sends (the shared scripted
 * harness ignores them, and the day row would leak into the 14-day window):
 * the day row answers only the read of its date, projected to the columns
 * asked; `day_closed = true` gets no rows, as on staging (the day was open);
 * messages are filtered by provider and returned newest first.
 */
function harness(fixture: Fixture = {}): Harness {
  const day = fixture.day === undefined ? S541 : fixture.day
  const profile = fixture.profile ?? PROFILE
  const now = fixture.now ?? NOW
  const text = fixture.text ?? PHRASE
  const script = fixture.script ?? [{ content: WRONG_REPLY }]
  const inserts: Harness['inserts'] = []
  const llmCalls: Harness['llmCalls'] = []
  const messages: Row[] = [
    ...(fixture.history ?? []),
    {
      direction: 'in',
      content: text,
      content_type: 'text',
      created_at: now.toISOString(),
      provider: 'mobile_flow',
      provider_message_id: TURN_ID,
    },
  ]

  const rowsFor = (read: Read): unknown => {
    switch (read.table) {
      case 'users':
        return {
          id: USER_ID,
          name: 'QA A',
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
        return PROGRESS
      case 'messages':
        return messages
          .filter((row) => read.filters.provider == null || row.provider === read.filters.provider)
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return []
        if (!day || read.filters.date !== '2026-10-04') return null
        if (read.columns.trim() === '*') return day
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), day[key.trim()] ?? null]),
        )
      }
      case 'global_config':
        if (read.filters.key === 'router.haiku_enabled') return null
        // Staging override of the protein factors (same as audit 2026-10-01).
        return [
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
      case 'v_active_prompts':
        return {
          stage: read.filters.stage ?? 'ganho_massa',
          model: 'anthropic/claude-sonnet-4.6',
          temperature: 0,
          max_tokens: 512,
          system_prompt: 'REGRAS COMPARTILHADAS',
          allowed_tools: null,
        }
      default:
        // agent_rules, product_events (reads), pending_registrations, …: empty.
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
    rpc: async (name: string) => ({
      data: name === 'match_method_chunks' ? [] : USER_ID,
      error: null,
    }),
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
        promptTokens: 11024,
        completionTokens: 95,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']

  return { deps: { supabase, llm, maxToolIterations: 3 }, inserts, llmCalls }
}

function flow(h: Harness, text: string = PHRASE, now: Date = NOW) {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: TURN_ID,
    text,
    timestamp: now,
  })
}

function events(h: Harness, name: string): Row[] {
  return h.inserts
    .filter((entry) => entry.table === 'product_events' && entry.row.event === name)
    .map((entry) => entry.row)
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

/** The numeric section of the per-turn context, line by line. */
function numericSection(prompt: string): string[] {
  const start = prompt.indexOf('### Dados numéricos REAIS')
  const end = prompt.indexOf('### Regras importantes')
  expect(start).toBeGreaterThan(-1)
  expect(end).toBeGreaterThan(start)
  return prompt.slice(start, end).trimEnd().split('\n')
}

/** Runs a turn the model answers and returns the context it was given. */
async function contextFor(fixture: Fixture): Promise<string[]> {
  const h = harness({ script: [{ content: 'Resposta do modelo.' }], ...fixture })
  await flow(h, fixture.text ?? 'Mostre meu progresso recente.', fixture.now ?? NOW)
  expect(h.llmCalls.length).toBeGreaterThan(0)
  return numericSection(flattenSystemPrompt(h.llmCalls[0]?.systemPrompt))
}

/** A stored row of the Flow channel. */
const row = (direction: 'in' | 'out', content: string, at: string, id: string): Row => ({
  direction,
  content,
  content_type: 'text',
  created_at: at,
  provider: 'mobile_flow',
  provider_message_id: `mobile_flow/qa-a/${id}`,
})

const ENERGY_LINE = /^- (?:Para COMIDA|Exercício hoje|Balanço calórico de hoje|REGRA)/

const RULE_LINE =
  '- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; o que o paciente pode comer é só o que está na linha "Para COMIDA". Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso e mostre meta, consumido e o que resta para comida; o gasto do treino fica à parte.'

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

describe('audit 2026-10-04 RC A — the exact report: "posso comer 322 kcal a mais?"', () => {
  it('exact phrase, exact day row, exact instant: the system answers, the model is never called', async () => {
    // The model is scripted to repeat the wrong reply of the iPhone. Before
    // the fix this test fails with output.text === WRONG_REPLY.
    const h = harness({ script: [{ content: WRONG_REPLY }] })
    const output = await flow(h)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
    expect(output).toMatchObject({
      preferAudio: false,
      singleMessage: true,
      toolCalls: [],
      stage: 'ganho_massa',
      modelUsed: 'anthropic/claude-sonnet-4.6',
      promptTokens: 0,
      completionTokens: 0,
      costUsd: 0,
    })
    // Target 2.980 unchanged; 2.439 left = 2.980 − 541; the 322 stay apart.
    expect(output.text).toContain('sua meta continua em 2.980 kcal')
    expect(output.text).toContain('restam 2.439 kcal para comer hoje')
    expect(output.text).toContain('As 322 kcal de treino registradas hoje ficam à parte')
    // The patient typed the stored number: no note about whose number it is.
    expect(output.text).not.toContain('Esse é o valor registrado no app.')
    // "registradas" in a system text is not a model's write claim: no guard runs.
    expect(events(h, 'llm.fake_write_detected')).toHaveLength(0)
    expect(events(h, 'llm.fake_write_unresolved')).toHaveLength(0)
  })

  it('nothing of the wrong reply survives: no "já considera", no net balance as food, no Markdown', async () => {
    const h = harness()
    const { text } = await flow(h)

    // 2.761 = net balance; 3.000 = net balance at 302; 3.302 = target + exercise.
    for (const wrong of [
      'já considera',
      'espaço pra comer',
      '2.761',
      '2761',
      '3.000',
      '3.302',
      '*',
      '`',
    ]) {
      expect(text).not.toContain(wrong)
    }
    expect(text).not.toMatch(/^Sim\b/)
  })

  it('records one event, with no patient text in it', async () => {
    const h = harness()
    await flow(h)

    const recorded = events(h, 'pipeline.deterministic_exercise_food')
    expect(recorded).toEqual([
      {
        user_id: USER_ID,
        event: 'pipeline.deterministic_exercise_food',
        properties: {
          stage: 'ganho_massa',
          protocol: 'ganho_massa',
          has_target: true,
          has_snapshot: true,
        },
      },
    ])
    const serialized = JSON.stringify(h.inserts)
    expect(serialized).not.toContain('Treinei')
    expect(serialized).not.toContain('322')
  })

  it.each([
    ['as stored on staging (no accents), day row of the turn', PHRASE, S541, ANSWER_541],
    [
      'as stored on staging (no accents), day row before the second lunch',
      PHRASE,
      S302,
      ANSWER_302,
    ],
    ['as the handoff quotes it (accents), day row of the turn', PHRASE_ACCENTED, S541, ANSWER_541],
    [
      'as the handoff quotes it (accents), day row before the second lunch',
      PHRASE_ACCENTED,
      S302,
      ANSWER_302,
    ],
  ])('%s', async (_name, text, day, expected) => {
    const h = harness({ day, text, script: [{ content: WRONG_REPLY }] })
    const output = await flow(h, text)

    expect(output.text).toBe(expected)
    expect(h.llmCalls).toHaveLength(0)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
  })

  it('retest on the same account: the wrong reply in the channel history does not come back', async () => {
    // What the QA account holds after 04/10: the exact turn of the report and
    // its wrong reply are among the 50 history rows (and in the anti-repetition
    // block). The summary row before them is synthetic. The retest instant is
    // not from the report.
    const retestAt = new Date('2026-10-04T15:30:00.000Z')
    const history: Row[] = [
      {
        direction: 'in',
        content: 'Mostre meu progresso recente.',
        content_type: 'text',
        created_at: '2026-10-04T14:40:00.000Z',
        provider: 'mobile_flow',
        provider_message_id: 'mobile_flow/qa-a/earlier-in',
      },
      {
        direction: 'out',
        content: 'Hoje: 302 kcal consumidas, meta 2.980 kcal. Treino: 322 kcal queimadas.',
        content_type: 'text',
        created_at: '2026-10-04T14:40:09.000Z',
        provider: 'mobile_flow',
        provider_message_id: 'mobile_flow/qa-a/earlier-out',
      },
      {
        direction: 'in',
        content: PHRASE,
        content_type: 'text',
        created_at: NOW.toISOString(),
        provider: 'mobile_flow',
        provider_message_id: 'mobile_flow/qa-a/report-in',
      },
      {
        direction: 'out',
        content: WRONG_REPLY,
        content_type: 'text',
        created_at: WRONG_REPLY_AT,
        provider: 'mobile_flow',
        provider_message_id: 'mobile_flow/qa-a/report-out',
      },
    ]
    const h = harness({ history, now: retestAt, script: [{ content: WRONG_REPLY }] })
    const output = await flow(h, PHRASE, retestAt)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
  })
})

describe('audit 2026-10-04 RC A — what the Flow model reads on the same day', () => {
  it.each([
    'Mostre meu progresso recente.',
    'Quanto ainda posso comer hoje?',
  ])('"%s": both balances labeled, the rule next to them, never the unlabeled net balance', async (text) => {
    const h = harness({ text, script: [{ content: 'Resposta do modelo.' }] })
    const output = await flow(h, text)

    // Not the direct question: the model answers, once.
    expect(output.text).toBe('Resposta do modelo.')
    expect(h.llmCalls).toHaveLength(1)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(0)

    const prompt = flattenSystemPrompt(h.llmCalls[0]?.systemPrompt)
    expect(numericSection(prompt)).toEqual([
      '### Dados numéricos REAIS do paciente (use estes, NÃO INVENTE)',
      '⚠️ Estes valores são canônicos — calculados pelo sistema. NUNCA recalcule meta/balanço/streak na cabeça nem invente números diferentes destes.',
      '',
      '- Meta calórica de hoje: **2980 kcal**',
      '- Meta de proteína de hoje: **144 g**',
      '- Consumido hoje: 541 kcal | 59.03 g proteína | 47.32g carbo | 10.27g gordura',
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2439 kcal',
      '- Exercício hoje: 322 kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida',
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -2761 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
      RULE_LINE,
      '- Sequência atual: 0 dias consecutivos (recorde 0) | XP: 0 (nível 1) | Blocos 7700 fechados: 0',
      '- Bloco 7700 em andamento: **0 kcal de 7700** (0%)',
    ])
    // The legacy line (colon right after "hoje") is what misled the model.
    expect(prompt).not.toContain('- Balanço calórico de hoje: ')
    // -2761 appears once, and only on the line that says what it is.
    expect(prompt.split('-2761')).toHaveLength(2)
    expect(prompt.split('\n').find((line) => line.includes('-2761'))).toContain('COM exercício')
  })

  it('the day row before the second lunch (consumed 302): 2678 left, net -3000', async () => {
    const lines = await contextFor({ day: S302 })

    expect(lines).toContain(
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2678 kcal',
    )
    expect(lines).toContain(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -3000 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
  })

  it('the stable (cached) block of the Flow prompt is untouched: shared rules + channel policy', async () => {
    const h = harness({
      text: 'Mostre meu progresso recente.',
      script: [{ content: 'Resposta do modelo.' }],
    })
    await flow(h, 'Mostre meu progresso recente.')

    const blocks = h.llmCalls[0]?.systemPrompt as Array<{ text: string; cache?: string }>
    expect(Array.isArray(blocks)).toBe(true)
    // Passes before and after the fix: no cache invalidation, no policy edit.
    expect(blocks[0]).toEqual({
      text: `REGRAS COMPARTILHADAS${mobileFlowSystemPolicy}`,
      cache: 'ephemeral_1h',
    })
    expect(blocks[0]?.text).not.toContain('Para COMIDA')
    expect(blocks[0]?.text).not.toContain('REGRA: exercício')
  })

  it('the fix lives in the variable (uncached) block only', async () => {
    const h = harness({
      text: 'Mostre meu progresso recente.',
      script: [{ content: 'Resposta do modelo.' }],
    })
    await flow(h, 'Mostre meu progresso recente.')

    const blocks = h.llmCalls[0]?.systemPrompt as Array<{ text: string; cache?: string }>
    expect(blocks).toHaveLength(2)
    expect(blocks[1]?.cache).toBeUndefined()
    expect(blocks[1]?.text).toContain('Para COMIDA')
    expect(blocks[1]?.text).toContain(RULE_LINE)
  })
})

describe('audit 2026-10-04 RC A — neighbours on the Flow (context and system answer)', () => {
  const recomposicao = (day: Row): Fixture => ({
    profile: { ...PROFILE, current_protocol: 'recomposicao', deficit_level: 500 },
    day: { ...S541, ...day },
  })

  it('recomposição, Roberto 2026-05-20 (1407 / 1843 / 467): 436 left, block wording', async () => {
    const fixture = recomposicao({
      calories_target: 1843,
      calories_consumed: 1407,
      exercise_calories: 467,
      daily_balance: -903,
    })
    const lines = await contextFor(fixture)

    expect(lines).toContain('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 436 kcal')
    expect(lines).toContain(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -903 kcal (negativo=déficit, positivo=superávit) — o crédito do bloco 7700 só é calculado no fechamento do dia (déficit programado − este número); até lá o valor é provisório e NÃO é o que resta para comer',
    )
    // Review round 2: the line called -903 "the number the closing uses in
    // the block"; the credit of that day is 500 − (−903) = 1.403.
    expect(lines.join('\n')).not.toContain('é o número que o fechamento')
    const rule = lines.find((line) => line.startsWith('- REGRA:'))
    expect(rule?.endsWith('o gasto do treino fica à parte (acelera o bloco 7700).')).toBe(true)

    // The phrase of the report says "gastei 322 kcal" and this day stores 467:
    // the answer shows the stored number and says so.
    const h = harness(fixture)
    const output = await flow(h)
    expect(output.text).toBe(
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 1.407 kcal, então restam 436 kcal para comer hoje (meta menos consumido). As 467 kcal de treino registradas hoje aceleram o bloco de 7.700 kcal, mas não entram no que resta para comida. Esse é o valor registrado no app.',
    )
    expect(output.stage).toBe('recomposicao')
    expect(h.llmCalls).toHaveLength(0)

    // Typed with the stored number, the same answer without the note.
    const same = 'Treinei musculacao hoje e gastei 467 kcal. Posso comer 467 kcal a mais?'
    expect((await flow(harness({ ...fixture, text: same }), same)).text).toBe(
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 1.407 kcal, então restam 436 kcal para comer hoje (meta menos consumido). As 467 kcal de treino registradas hoje aceleram o bloco de 7.700 kcal, mas não entram no que resta para comida.',
    )
  })

  it('recomposição, Roberto 2026-05-21 (1301 / 1843 / 565): 542 left, net -1107', async () => {
    const lines = await contextFor(
      recomposicao({
        calories_target: 1843,
        calories_consumed: 1301,
        exercise_calories: 565,
        daily_balance: -1107,
      }),
    )

    expect(lines).toContain('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 542 kcal')
    expect(lines.find((line) => line.includes('COM exercício'))).toContain(': -1107 kcal')
  })

  it('over the target with a workout: an excess stays an excess, the workout does not erase it', async () => {
    const fixture: Fixture = { day: { ...S541, calories_consumed: 3200, daily_balance: -102 } }
    const lines = await contextFor(fixture)

    expect(lines).toContain(
      '- Para COMIDA hoje (consumido − meta, SEM exercício): excedente de 220 kcal acima da meta',
    )
    expect(lines.find((line) => line.includes('COM exercício'))).toContain(': -102 kcal')
    // Review round 2: with an excess the rule asked for "o que resta para
    // comida", a number the context does not have.
    expect(lines.find((line) => line.startsWith('- REGRA:'))).toBe(
      '- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; a linha "Para COMIDA" mostra excedente, então não resta nada para comida hoje. Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso e mostre meta, consumido e o excedente; o gasto do treino fica à parte.',
    )

    const h = harness(fixture)
    expect((await flow(h)).text).toBe(
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 3.200 kcal, então você está 220 kcal acima da meta (consumido menos meta). As 322 kcal de treino registradas hoje ficam à parte e não apagam esse excedente.',
    )
    expect(h.llmCalls).toHaveLength(0)
  })

  it('target met exactly: nothing left, and the workout frees nothing', async () => {
    const h = harness({ day: { ...S541, calories_consumed: 2980, daily_balance: -322 } })

    expect((await flow(h)).text).toBe(
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 2.980 kcal, então você já bateu a meta de hoje. As 322 kcal de treino registradas hoje ficam à parte e não liberam mais comida.',
    )
  })

  it('no workout stored today: the answer uses only the database, not the 322 the patient typed', async () => {
    const fixture: Fixture = { day: { ...S541, exercise_calories: 0, daily_balance: -2439 } }
    const h = harness(fixture)
    const output = await flow(h)

    // The patient typed "treinei… gastei 322 kcal", but the Flow chat stores no
    // workout: the answer says so instead of speaking of "the workout".
    expect(output.text).toBe(
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`,
    )
    expect(output.text).not.toContain('322')
    expect(h.llmCalls).toHaveLength(0)
    // "registrado" in a system text is not a model's write claim: no guard runs.
    expect(events(h, 'llm.fake_write_detected')).toHaveLength(0)
    expect(events(h, 'llm.fake_write_unresolved')).toHaveLength(0)

    const lines = await contextFor(fixture)
    expect(lines).toContain(
      '- Exercício hoje: 0 kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida',
    )
    expect(lines.find((line) => line.includes('COM exercício'))).toContain(': -2439 kcal')
  })

  it('the workout stored is not the one typed (150 stored, "gastei 400 kcal"): the answer says whose number it is', async () => {
    // Review round 2, through this pipeline: the day had a 150 kcal walk
    // stored, the patient wrote about a 400 kcal workout and read "As 150 kcal
    // do treino ficam à parte", with no hint that 150 was the app's number.
    const text = 'Treinei musculação e gastei 400 kcal. Posso comer 400 kcal a mais?'
    const h = harness({
      day: { ...S541, exercise_calories: 150, daily_balance: -2589 },
      text,
      script: [{ content: WRONG_REPLY }],
    })
    const output = await flow(h, text)

    expect(output.text).toBe(
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). As 150 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida. Esse é o valor registrado no app.',
    )
    // Nothing built from what the patient typed, and no claim that the
    // workout he cited is missing.
    expect(output.text).not.toContain('400')
    expect(output.text).not.toContain('Não encontrei treino')
    expect(h.llmCalls).toHaveLength(0)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
  })

  it('recomposição with no workout stored (1301 / 1843 / 0): no claim that the block advanced', async () => {
    // Review 2026-10-04, through this pipeline: the answer said "O gasto do
    // treino acelera o bloco de 7.700 kcal" with exercise_calories 0. The
    // block is credited from the day row's exercise (docs/CALCULO-MPP.md §2b).
    const h = harness(
      recomposicao({
        calories_target: 1843,
        calories_consumed: 1301,
        exercise_calories: 0,
        daily_balance: -542,
      }),
    )
    const output = await flow(h)

    expect(output.text).toBe(
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 1.301 kcal, então restam 542 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`,
    )
    expect(output.text).not.toMatch(/7\.?700|bloco|acelera/)
    expect(output.stage).toBe('recomposicao')
    expect(h.llmCalls).toHaveLength(0)
  })

  it('nothing logged yet today (no day row): food line and rule only, no net balance', async () => {
    // Without a day row the Flow target falls back to the live profile
    // (80.5 kg → 2988 kcal), as in the audit of 2026-10-01.
    const lines = await contextFor({ day: null })

    expect(
      lines.filter((line) => line.startsWith('- Consumo hoje') || ENERGY_LINE.test(line)),
    ).toEqual([
      '- Consumo hoje: 0 kcal (nada registrado ainda)',
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2988 kcal',
      RULE_LINE,
    ])
    expect(lines.join('\n')).not.toContain('COM exercício')
    expect(lines.join('\n')).not.toContain('-2988')

    const h = harness({ day: null })
    const output = await flow(h)
    expect(output.text).toBe(
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 2.988 kcal.\n\nVocê ainda não tem consumo lançado hoje, então restam 2.988 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`,
    )
    expect(events(h, 'pipeline.deterministic_exercise_food')[0]?.properties).toMatchObject({
      has_target: true,
      has_snapshot: false,
    })
  })

  it('day row without a stored target: every number is over the target printed, not the generated column', async () => {
    // The generated column is consumed − COALESCE(target, 0) − exercise = +219.
    // Printing it next to "Meta 2988" gave three numbers that do not add up.
    const fixture: Fixture = {
      day: { ...S541, calories_target: null, protein_target: null, daily_balance: 219 },
    }
    const h = harness({
      ...fixture,
      text: 'Mostre meu progresso recente.',
      script: [{ content: 'Resposta do modelo.' }],
    })
    await flow(h, 'Mostre meu progresso recente.')
    const prompt = flattenSystemPrompt(h.llmCalls[0]?.systemPrompt)
    const lines = numericSection(prompt)

    expect(lines).toContain('- Meta calórica de hoje: **2988 kcal**')
    expect(lines).toContain(
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2447 kcal',
    )
    expect(lines.find((line) => line.includes('COM exercício'))).toContain(': -2769 kcal')
    expect(prompt).not.toContain('219 kcal')
  })

  it('profile without a target (onboarding): no number is invented', async () => {
    const fixture: Fixture = {
      profile: { ...PROFILE, sex: null, weight_kg: null, height_cm: null, current_protocol: null },
      day: null,
    }
    const h = harness(fixture)
    const output = await flow(h)

    expect(output.text).toBe(
      `O treino não aumenta o que você pode comer hoje: a meta do dia não muda com exercício.\n\n${NO_WORKOUT}`,
    )
    expect(output.text).not.toMatch(/\d/)
    expect(h.llmCalls).toHaveLength(0)
    expect(events(h, 'pipeline.deterministic_exercise_food')[0]?.properties).toMatchObject({
      has_target: false,
      protocol: null,
    })
  })

  it.each([
    'manutencao',
    'ganho_massa',
  ])('%s: no block wording in the energy lines nor in the answer', async (protocol) => {
    const fixture: Fixture = { profile: { ...PROFILE, current_protocol: protocol } }
    const energy = (await contextFor(fixture)).filter((line) => ENERGY_LINE.test(line))

    expect(energy).toHaveLength(4)
    expect(energy.join('\n')).not.toMatch(/7\.?700|bloco/)

    const answer = (await flow(harness(fixture))).text
    expect(answer).toBe(ANSWER_541)
    expect(answer).not.toMatch(/7\.?700|bloco/)
  })
})

describe('audit 2026-10-04 RC A — messages the system must NOT answer (the model does)', () => {
  it.each([
    // iPhone round, test 6 (passed) and test 4 (another defect, not this one)
    'Quanto de proteína ainda falta hoje?',
    'Qual foi meu balanço de ontem? Mostre consumido, meta, exercício e a conta',
    // iPhone round, test 7
    'Sugira um cardápio completo para hoje',
    'Mostre meu progresso recente.',
    // exercise in the message, but another question
    'Fiz musculação. Posso comer 30 g de whey a mais hoje?',
    'Treinei pesado hoje. Preciso comer mais proteína pra compensar?',
    'Vou treinar agora. Posso comer uma banana a mais antes?',
    'Hoje gastei muito no mercado. Posso comer um pouco a mais no jantar?',
    // mixed message: the workout question plus another request
    'Treinei e gastei 322 kcal. Posso comer 322 kcal a mais? E quanto de proteína falta?',
    // Review 2026-10-04 — each of these got the system answer through this
    // same pipeline (llmCalls 0) with the first predicate:
    // a workout to create or delete (the patient did not even say he trained)
    'Cria um treino de perna pra mim. Posso comer mais hoje?',
    'Apaga o treino de hoje. Posso comer mais?',
    // a symptom in the same sentence as the workout
    'Treinei hoje e passei mal. Posso comer mais?',
    'Treinei e minha glicemia baixou. Posso comer mais?',
    'Treinei hoje e estou cansado, posso comer mais?',
    // the patient did not train
    'Hoje não deu pra treinar, posso comer mais?',
    // an open question and reported speech
    'Treinei hoje. O que posso comer a mais?',
    'Treinei hoje. Meu nutricionista disse que posso comer mais.',
    // another person
    'Meu filho treinou hoje, ele pode comer mais?',
    // the inverse question and the profile question
    'Posso compensar o excesso de calorias treinando mais?',
    'Aumentei meu treino pra 6 dias. Isso muda minha meta?',
    // a direct question outside the grammar, on purpose (typing error)
    'trenei hoje posso comer mais?',
    // Review 2026-10-04, round 2 — each of these got the system answer
    // through this same pipeline (llmCalls 0):
    // a statement, not a question: capacity, appetite or belief
    'Treinei pesado hoje, consigo comer mais.',
    'Treinei cedo e consigo comer mais hoje',
    'Malhei hoje e consigo comer um pouco mais.',
    'Treinei hoje e consigo comer mais',
    'Treinei hoje e posso comer mais!',
    'Treinei hoje, então posso comer mais.',
    'Treinei hoje, dá pra comer mais.',
    'Treinei hoje e preciso repor as calorias.',
    // "consigo" in a question: outside the grammar on purpose
    'Treinei pesado. Consigo comer mais hoje?',
    // the workout named with no report of today's workout
    'O treino muda minha meta?',
    'Minha meta muda quando eu treino?',
    // "essas N kcal" that does not repeat a burn reported; "certo" as an adverb
    'Treinei hoje. Posso comer essas 500 kcal?',
    'Treinei e gastei 300 kcal. Posso comer essas 500 kcal?',
    'Treinei hoje. Posso comer mais certo?',
  ])('"%s"', async (text) => {
    const h = harness({ text, script: [{ content: 'Resposta do modelo.' }] })
    const output = await flow(h, text)

    expect(output.text).toBe('Resposta do modelo.')
    expect(h.llmCalls).toHaveLength(1)
    expect(h.llmCalls[0]?.messages.at(-1)).toEqual({ role: 'user', content: text })
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(0)
    // …and it still reads the corrected context.
    expect(flattenSystemPrompt(h.llmCalls[0]?.systemPrompt)).toContain(RULE_LINE)
  })
})

describe('audit 2026-10-04 RC A — review rounds 2 and 3: the conversation the patient was in', () => {
  const MODEL_REPLY = 'Resposta do modelo.'
  /** No workout stored today (the Flow chat stores none). */
  const NO_WORKOUT_DAY: Row = { ...S541, exercise_calories: 0, daily_balance: -2439 }

  const expectTheModelAnswered = (h: Harness, output: { text: string }, text: string) => {
    expect(output.text).toBe(MODEL_REPLY)
    expect(h.llmCalls).toHaveLength(1)
    expect(h.llmCalls[0]?.messages.at(-1)).toEqual({ role: 'user', content: text })
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(0)
    expect(flattenSystemPrompt(h.llmCalls[0]?.systemPrompt)).toContain(RULE_LINE)
  }

  it('Flow had asked "Está conseguindo comer nas refeições principais?": "Treinei hoje e consigo comer mais" is appetite, the model answers', async () => {
    // The ganho-de-massa patient reports appetite and read "O treino não
    // aumenta o que você pode comer hoje"; the model never saw the message.
    const text = 'Treinei hoje e consigo comer mais'
    const flowQuestion =
      'Você está 2.439 kcal abaixo da meta de hoje. Está conseguindo comer nas refeições principais?'
    const h = harness({
      text,
      history: [
        row('in', 'Estou com dificuldade de bater a meta', '2026-10-04T14:50:00.000Z', 'a1'),
        row('out', flowQuestion, '2026-10-04T14:50:10.000Z', 'a2'),
      ],
      script: [{ content: MODEL_REPLY }],
    })
    const output = await flow(h, text)

    expectTheModelAnswered(h, output, text)
    // The model reads the reply in its conversation: Flow's question is there.
    expect(h.llmCalls[0]?.messages.at(-2)).toEqual({ role: 'assistant', content: flowQuestion })
  })

  it('after a workout-plan suggestion, "O treino muda minha meta?" is about the plan: the model answers', async () => {
    // It got the day rule plus "Não encontrei treino registrado hoje".
    const text = 'O treino muda minha meta?'
    const h = harness({
      text,
      day: NO_WORKOUT_DAY,
      history: [
        row(
          'in',
          'Monta uma sugestão de treino 5x por semana pra mim',
          '2026-10-04T14:50:00.000Z',
          'b1',
        ),
        row(
          'out',
          'Criei uma sugestão de plano de treino com 5 sessões por semana. Revise e confirme em Revisar sugestão.',
          '2026-10-04T14:50:10.000Z',
          'b2',
        ),
      ],
      script: [{ content: MODEL_REPLY }],
    })
    const output = await flow(h, text)

    expectTheModelAnswered(h, output, text)
    expect(output.text).not.toContain('Não encontrei treino registrado hoje')
  })

  it('"Minha meta muda quando eu treino?" with no workout today is the general rule: the model answers', async () => {
    const text = 'Minha meta muda quando eu treino?'
    const h = harness({ text, day: NO_WORKOUT_DAY, script: [{ content: MODEL_REPLY }] })

    expectTheModelAnswered(h, await flow(h, text), text)
  })

  const ACAI_HISTORY: Row[] = [
    row('in', 'Quantas calorias tem um açaí médio com granola?', '2026-10-04T14:50:00.000Z', 'e1'),
    row(
      'out',
      'Um açaí médio com granola tem cerca de 500 kcal.',
      '2026-10-04T14:50:10.000Z',
      'e2',
    ),
  ]

  it.each([
    'Treinei hoje. Posso comer essas 500 kcal?',
    'Treinei e gastei 300 kcal. Posso comer essas 500 kcal?',
    // Round 3: the same anaphora with no number — each got the system answer.
    'Treinei hoje. Posso comer essas calorias?',
    'Treinei hoje. Posso comer essas calorias a mais?',
    'Treinei hoje. Posso comer as calorias?',
  ])('after "Um açaí médio com granola tem cerca de 500 kcal.", "%s" points at the açaí: the model answers', async (text) => {
    const h = harness({ text, history: ACAI_HISTORY, script: [{ content: MODEL_REPLY }] })

    expectTheModelAnswered(h, await flow(h, text), text)
  })

  it.each([
    // The burn stated in the report, or named in the question, makes "essas
    // calorias" the workout's — the açaí before it changes nothing.
    'Treinei e gastei 322 kcal. Posso comer essas calorias?',
    'Treinei e gastei 322 kcal. Posso comer essas calorias a mais?',
    'Treinei hoje. Posso comer as calorias do treino?',
    'Treinei hoje. Posso comer as calorias que gastei?',
  ])('after the açaí, "%s" says whose calories they are: the system answers', async (text) => {
    const h = harness({ text, history: ACAI_HISTORY, script: [{ content: WRONG_REPLY }] })
    const output = await flow(h, text)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
  })

  // Review round 3 — the history of the reproduction, verbatim.
  const FLOW_QUESTION =
    'Você está 2.439 kcal abaixo da meta de hoje. Está conseguindo comer nas refeições principais?'
  const appetiteHistory = (day: '2026-10-04' | '2026-10-03' = '2026-10-04'): Row[] => [
    row('in', 'Estou com dificuldade de bater a meta', `${day}T14:50:00.000Z`, 'a1'),
    row('out', FLOW_QUESTION, `${day}T14:50:10.000Z`, 'a2'),
  ]
  /** What the system answers on the day of the reproduction (no workout stored). */
  const ANSWER_NO_WORKOUT = `O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`

  it.each([
    'Treinei hoje e dá pra comer mais',
    'Treinei pesado hoje, dá pra comer mais',
    'Treinei hoje e dá pra comer um pouco mais',
    'Treinei hoje e dá pra comer mais hoje',
  ])('Flow had asked "Está conseguindo comer nas refeições principais?": "%s" is the patient answering, the model answers', async (text) => {
    // Round 3, through this pipeline: llmCalls 0 and "O treino não aumenta o
    // que você pode comer hoje… Não encontrei treino registrado hoje." — the
    // ganho-de-massa patient said he can eat more and the model never saw it.
    // "Dá pra" with no final mark is inside the grammar; the conversation is
    // what says it is an answer.
    for (const day of [NO_WORKOUT_DAY, S541]) {
      const h = harness({
        text,
        day,
        history: appetiteHistory(),
        script: [{ content: MODEL_REPLY }],
      })
      const output = await flow(h, text)

      expectTheModelAnswered(h, output, text)
      expect(output.text).not.toContain('O treino não aumenta')
      expect(h.llmCalls[0]?.messages.at(-2)).toEqual({ role: 'assistant', content: FLOW_QUESTION })
    }
  })

  it('the same history, the exact phrase of the report (it has "?"): the system still answers', async () => {
    for (const [text, day, expected] of [
      [PHRASE, S541, ANSWER_541],
      [PHRASE_ACCENTED, S541, ANSWER_541],
      [PHRASE, NO_WORKOUT_DAY, ANSWER_NO_WORKOUT],
      // The reply of round 3 typed as a question is a question.
      ['Treinei hoje e dá pra comer mais?', NO_WORKOUT_DAY, ANSWER_NO_WORKOUT],
    ] as const) {
      const h = harness({
        text,
        day,
        history: appetiteHistory(),
        script: [{ content: WRONG_REPLY }],
      })
      const output = await flow(h, text)

      expect(output.text).toBe(expected)
      expect(h.llmCalls).toHaveLength(0)
      expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
    }
  })

  it.each([
    // Voice style, no "?" and no final mark.
    ['treinei hoje posso comer mais', ANSWER_541],
    ['treinei musculacao hoje e gastei 322 kcal posso comer 322 kcal a mais', ANSWER_541],
    ['treinei hj e gastei 322kcal posso comer 322kcal a mais', ANSWER_541],
    ['Fiz academia hoje posso comer mais né', ANSWER_541],
    // The replies of round 3 themselves, when Flow had asked nothing
    // (declared above: the statement with no final mark keeps the answer).
    ['Treinei hoje e dá pra comer mais', ANSWER_541],
    ['Treinei pesado hoje, dá pra comer mais', ANSWER_541],
  ])('no pending question of Flow, "%s": the system still answers', async (text, expected) => {
    const histories: Row[][] = [
      // First message of the day.
      [],
      // Flow's last reply states something.
      [
        row('in', 'Mostre meu progresso recente.', '2026-10-04T14:40:00.000Z', 'p1'),
        row('out', 'Hoje: 541 kcal consumidas, meta 2.980 kcal.', '2026-10-04T14:40:09.000Z', 'p2'),
      ],
      // Flow asked, the patient answered and Flow replied with a statement.
      [
        ...appetiteHistory(),
        row('in', 'Estou sim', '2026-10-04T14:51:00.000Z', 'a3'),
        row('out', 'Ótimo, siga assim.', '2026-10-04T14:51:08.000Z', 'a4'),
      ],
      // The question of Flow is from yesterday: the real loader dates that
      // row, and a dated question is not pending today.
      appetiteHistory('2026-10-03'),
    ]
    for (const history of histories) {
      const h = harness({ text, history, script: [{ content: WRONG_REPLY }] })
      const output = await flow(h, text)

      expect(output.text).toBe(expected)
      expect(h.llmCalls).toHaveLength(0)
      expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
    }
  })

  it('declared as it is: a dictated question with no "?" right after a question of Flow goes to the model', async () => {
    // The price of the rule above: here the model answers, with the rule and
    // both balances in its context.
    const text = 'treinei hoje posso comer mais'
    const h = harness({ text, history: appetiteHistory(), script: [{ content: MODEL_REPLY }] })

    expectTheModelAnswered(h, await flow(h, text), text)
  })

  it.each([
    // The same questions, next to the report: still the system.
    ['Treinei hoje. O treino muda minha meta?', ANSWER_541],
    ['Treinei e gastei 322 kcal. Posso comer essas 322 kcal?', ANSWER_541],
    ['Treinei hoje, posso comer mais, certo?', ANSWER_541],
    ['Treinei e gastei 322 kcal. Posso comer essas calorias?', ANSWER_541],
    // Declared above: with no final mark, and Flow not having just asked
    // something, the statement still gets the answer.
    ['treinei hoje e posso comer mais', ANSWER_541],
  ])('still answered by the system: "%s"', async (text, expected) => {
    const h = harness({ text, script: [{ content: WRONG_REPLY }] })
    const output = await flow(h, text)

    expect(output.text).toBe(expected)
    expect(h.llmCalls).toHaveLength(0)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
  })
})

describe('audit 2026-10-04 RC A — the patient asks again', () => {
  const SECOND_AT = new Date('2026-10-04T15:04:40.503Z')
  const MODEL_REPLY = 'Resposta do modelo.'

  it('asked twice: the first turn is the system, the second identical question goes to the model', async () => {
    // Review 2026-10-04: the second turn returned the same text byte for
    // byte, model never called — a loop with a fixed text.
    const first = harness({ script: [{ content: MODEL_REPLY }] })
    const firstOutput = await flow(first)
    expect(firstOutput.text).toBe(ANSWER_541)
    expect(first.llmCalls).toHaveLength(0)

    const second = harness({
      history: [
        row('in', PHRASE, NOW.toISOString(), 'first-in'),
        row('out', firstOutput.text, '2026-10-04T15:03:41.000Z', 'first-out'),
      ],
      now: SECOND_AT,
      script: [{ content: MODEL_REPLY }],
    })
    const secondOutput = await flow(second, PHRASE, SECOND_AT)

    // One model call in the two turns, and it is the second turn's.
    expect(first.llmCalls.length + second.llmCalls.length).toBe(1)
    expect(secondOutput.text).toBe(MODEL_REPLY)
    expect(secondOutput.text).not.toBe(firstOutput.text)
    expect(events(second, 'pipeline.deterministic_exercise_food')).toHaveLength(0)
    // The model reads the question, the system answer before it, and the rule.
    const call = second.llmCalls[0]
    expect(call?.messages.at(-1)).toEqual({ role: 'user', content: PHRASE })
    expect(call?.messages.at(-2)).toEqual({ role: 'assistant', content: ANSWER_541 })
    expect(flattenSystemPrompt(call?.systemPrompt)).toContain(RULE_LINE)
  })

  it.each([
    // Review 2026-10-04: each got the identical system text with it already in the history.
    'Mas treinei 2 horas hoje, posso comer mais?',
    'Sei que treino não libera, mas posso comer mais hoje?',
    'Treinei hoje. Você já me disse que não, mas posso comer mais?',
  ])('insisting after the system answer goes to the model: "%s"', async (text) => {
    const h = harness({
      history: [
        row('in', PHRASE, NOW.toISOString(), 'first-in'),
        row('out', ANSWER_541, '2026-10-04T15:03:41.000Z', 'first-out'),
      ],
      now: SECOND_AT,
      text,
      script: [{ content: MODEL_REPLY }],
    })
    const output = await flow(h, text, SECOND_AT)

    expect(output.text).toBe(MODEL_REPLY)
    expect(h.llmCalls).toHaveLength(1)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(0)
  })

  it('same day, numbers changed (consumed 302 → 541): the system answers again, with the new numbers', async () => {
    // Review round 2, through this pipeline, model scripted with the wrong
    // reply of the iPhone: after ONE system answer at 11:00Z ("restam 2.678"),
    // the report phrase at 22:10Z went to the model and the wrong reply came
    // back byte for byte. The text the system gives now is another one.
    const laterAt = new Date('2026-10-04T22:10:00.000Z')
    const h = harness({
      history: [
        row('in', PHRASE, '2026-10-04T11:00:00.000Z', 'c1'),
        row('out', ANSWER_302, '2026-10-04T11:00:01.000Z', 'c2'),
      ],
      now: laterAt,
      script: [{ content: WRONG_REPLY }],
    })
    const output = await flow(h, PHRASE, laterAt)

    expect(output.text).toBe(ANSWER_541)
    expect(output.text).toContain('restam 2.439 kcal')
    expect(output.text).not.toBe(WRONG_REPLY)
    expect(h.llmCalls).toHaveLength(0)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
  })

  it('the previous system answer was to another question and another state: the system answers the report phrase', async () => {
    // Review round 2, second reproduction: "O treino aumenta minha meta?" +
    // the system answer of the 302 state in the history, then the exact
    // phrase of the report → the model's wrong reply was returned.
    const h = harness({
      history: [
        row('in', 'O treino aumenta minha meta?', '2026-10-04T15:00:00.000Z', 'd1'),
        row('out', ANSWER_302, '2026-10-04T15:00:01.000Z', 'd2'),
      ],
      script: [{ content: WRONG_REPLY }],
    })
    const output = await flow(h)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
  })

  it('another form of the grammar first, then the exact phrase with the same state: identical text, so the model answers', async () => {
    const firstText = 'Treinei hoje, posso comer mais?'
    const first = harness({ text: firstText, script: [{ content: MODEL_REPLY }] })
    const firstOutput = await flow(first, firstText)
    expect(firstOutput.text).toBe(ANSWER_541)
    expect(first.llmCalls).toHaveLength(0)

    const second = harness({
      history: [
        row('in', firstText, NOW.toISOString(), 'first-in'),
        row('out', firstOutput.text, '2026-10-04T15:03:41.000Z', 'first-out'),
      ],
      now: SECOND_AT,
      script: [{ content: MODEL_REPLY }],
    })
    const secondOutput = await flow(second, PHRASE, SECOND_AT)

    // The system would send the very same text: the model answers, once.
    expect(secondOutput.text).toBe(MODEL_REPLY)
    expect(second.llmCalls).toHaveLength(1)
    expect(events(second, 'pipeline.deterministic_exercise_food')).toHaveLength(0)
  })

  it('same state, but the second message types a burn that is not the stored one: another text, the system answers', async () => {
    const day: Row = { ...S541, exercise_calories: 150, daily_balance: -2589 }
    const firstText = 'Treinei hoje, posso comer mais?'
    const first = harness({ day, text: firstText, script: [{ content: MODEL_REPLY }] })
    const firstOutput = await flow(first, firstText)
    expect(firstOutput.text.endsWith('não entram no que resta para comida.')).toBe(true)

    const secondText = 'Treinei musculação e gastei 400 kcal. Posso comer 400 kcal a mais?'
    const second = harness({
      day,
      text: secondText,
      history: [
        row('in', firstText, NOW.toISOString(), 'first-in'),
        row('out', firstOutput.text, '2026-10-04T15:03:41.000Z', 'first-out'),
      ],
      now: SECOND_AT,
      script: [{ content: MODEL_REPLY }],
    })
    const secondOutput = await flow(second, secondText, SECOND_AT)

    expect(secondOutput.text).toBe(`${firstOutput.text} Esse é o valor registrado no app.`)
    expect(second.llmCalls).toHaveLength(0)
  })

  it('the rule looks only at the previous Flow reply: after the model answered, the system answers again', async () => {
    const h = harness({
      history: [
        row('in', PHRASE, NOW.toISOString(), 'first-in'),
        row('out', ANSWER_541, '2026-10-04T15:03:41.000Z', 'first-out'),
        row('in', PHRASE, SECOND_AT.toISOString(), 'second-in'),
        row('out', MODEL_REPLY, '2026-10-04T15:04:50.000Z', 'second-out'),
      ],
      now: new Date('2026-10-04T15:20:00.000Z'),
      script: [{ content: MODEL_REPLY }],
    })
    const output = await flow(h, PHRASE, new Date('2026-10-04T15:20:00.000Z'))

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
  })

  it("the system answer of a previous day does not count: today the system answers with today's numbers", async () => {
    // Yesterday's row reaches the prompt dated ("[Mensagem de 03/10/2026, dia
    // anterior…"), so it is not "the previous reply" of this conversation.
    const h = harness({
      history: [
        row('in', PHRASE, '2026-10-03T15:03:40.503Z', 'yesterday-in'),
        row('out', ANSWER_302, '2026-10-03T15:03:41.000Z', 'yesterday-out'),
      ],
      script: [{ content: MODEL_REPLY }],
    })
    const output = await flow(h)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
  })

  it('the IDENTICAL system answer, but of a previous day, does not count either', async () => {
    // Same numbers yesterday and today: the text is the same, but the history
    // loader dates yesterday's row, so it is not this conversation's reply.
    const h = harness({
      history: [
        row('in', PHRASE, '2026-10-03T15:03:40.503Z', 'yesterday-in'),
        row('out', ANSWER_541, '2026-10-03T15:03:41.000Z', 'yesterday-out'),
      ],
      script: [{ content: MODEL_REPLY }],
    })
    const output = await flow(h)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
  })
})

describe('audit 2026-10-04 RC A — consulta_progresso through the Flow pipeline (wiring)', () => {
  it('day row WITHOUT a stored target: the tool result the model reads has energia_hoje over the Flow target, no daily_balance', async () => {
    // Review 2026-10-04: the tool tests below inject `flowDailyTargets` by
    // hand, so the suite stayed green with the pipeline no longer passing it.
    // Then the model read meta_kcal null and no "restam" next to a context
    // saying "Meta 2988 / restam 2447". Here the model itself calls the tool.
    const text = 'Mostre meu progresso recente.'
    const h = harness({
      // Generated column on a row with no target: 541 − 0 − 322 = 219.
      day: { ...S541, calories_target: null, protein_target: null, daily_balance: 219 },
      text,
      script: [
        { toolCalls: [{ id: 'call-1', name: 'consulta_progresso', arguments: '{}' }] },
        { content: 'Resposta do modelo.' },
      ],
    })
    const output = await flow(h, text)

    expect(output.text).toBe('Resposta do modelo.')
    expect(h.llmCalls).toHaveLength(2)
    expect(output.toolCalls.map((call) => call.name)).toEqual(['consulta_progresso'])

    const toolMessages = (h.llmCalls[1]?.messages ?? []).filter(
      (message): message is { role: 'tool'; tool_call_id: string; content: string } =>
        typeof message === 'object' &&
        message !== null &&
        (message as { role?: unknown }).role === 'tool',
    )
    expect(toolMessages).toHaveLength(1)
    expect(toolMessages[0]?.tool_call_id).toBe('call-1')
    const seen = toolMessages[0]?.content ?? ''
    const result = JSON.parse(seen) as { energia_hoje?: Row; hoje?: Row }

    // The same target and food balance the context of this turn prints.
    expect(result.energia_hoje).toMatchObject({
      meta_kcal: 2988,
      consumido_kcal: 541,
      restam_para_comida_kcal: 2447,
      exercicio_kcal: 322,
      balanco_do_dia_com_exercicio_kcal: -2769,
    })
    expect(result.energia_hoje).not.toHaveProperty('excedente_de_comida_kcal')
    expect(seen).not.toContain('daily_balance')
    expect(seen).not.toContain('219')
    expect(numericSection(flattenSystemPrompt(h.llmCalls[0]?.systemPrompt))).toContain(
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2447 kcal',
    )
  })
})

describe('audit 2026-10-04 RC A — consulta_progresso', () => {
  const toolContext = (h: Harness) => ({
    supabase: h.deps.supabase,
    userId: USER_ID,
    userWpp: USER_ID,
    llm: {} as never,
    userTimezone: 'America/Sao_Paulo',
    referenceTimestamp: NOW,
  })
  const progresso = {
    xp: 0,
    nivel: 1,
    sequencia_dias_consecutivos: 0,
    recorde_sequencia: 0,
    blocos_7700_completos: 0,
    deficit_no_bloco_atual: 0,
    conquistas: [],
  }

  it('on the Flow: labeled energy of the day, and the raw net balance is withheld', async () => {
    const h = harness()
    const output = await consultaProgresso.execute(
      {},
      {
        ...toolContext(h),
        assistantIdentity: 'flow',
        flowDailyTargets: { calories_target: 2980, protein_target: 144 },
      },
    )
    const { daily_balance: _net, ...dayWithoutNet } = S541

    expect(output).toEqual({
      progresso,
      hoje: dayWithoutNet,
      energia_hoje: {
        meta_kcal: 2980,
        consumido_kcal: 541,
        restam_para_comida_kcal: 2439,
        exercicio_kcal: 322,
        balanco_do_dia_com_exercicio_kcal: -2761,
        regra:
          'Exercício não libera comida nem apaga excedente: a meta é a mesma com ou sem treino e o que resta para comida é meta − consumido, sem exercício. O gasto do treino fica à parte; balanco_do_dia_com_exercicio_kcal não é o que resta para comer.',
      },
    })
    expect(output.hoje).not.toHaveProperty('daily_balance')
    expect(JSON.stringify(output)).not.toContain('daily_balance')
  })

  it('on the Flow, over the target: an excess key, never a negative "restam"', async () => {
    const h = harness({ day: { ...S541, calories_consumed: 3200, daily_balance: -102 } })
    const output = await consultaProgresso.execute(
      {},
      {
        ...toolContext(h),
        assistantIdentity: 'flow',
        flowDailyTargets: { calories_target: 2980, protein_target: 144 },
      },
    )

    expect(output.energia_hoje).toMatchObject({
      meta_kcal: 2980,
      consumido_kcal: 3200,
      excedente_de_comida_kcal: 220,
      exercicio_kcal: 322,
      balanco_do_dia_com_exercicio_kcal: -102,
    })
    expect(output.energia_hoje).not.toHaveProperty('restam_para_comida_kcal')
  })

  it('on the Flow with no day row: target and food left, no net balance', async () => {
    const h = harness({ day: null })
    const output = await consultaProgresso.execute(
      {},
      {
        ...toolContext(h),
        assistantIdentity: 'flow',
        flowDailyTargets: { calories_target: 2988, protein_target: 144.9 },
      },
    )

    expect(output.hoje).toBeNull()
    expect(output.energia_hoje).toMatchObject({
      meta_kcal: 2988,
      consumido_kcal: 0,
      restam_para_comida_kcal: 2988,
      exercicio_kcal: 0,
    })
    expect(output.energia_hoje).not.toHaveProperty('balanco_do_dia_com_exercicio_kcal')
  })

  it('legacy channel (no Flow identity): the raw row, unchanged', async () => {
    const h = harness()
    const output = await consultaProgresso.execute({}, toolContext(h))

    expect(output).toEqual({ progresso, hoje: S541 })
    expect(output).not.toHaveProperty('energia_hoje')
  })
})
