/**
 * Audit 2026-10-04 — Flow chat (iOS app), cost and speed: the size of ONE
 * model call.
 *
 * The report (staging, QA account A, read 2026-10-04 ~15:45 BRT, public.messages
 * with provider 'mobile_flow'): the turn of 15:21,
 *   "O treino de hoje aumenta minha meta de calorias?"
 * made a single model call (anthropic/claude-sonnet-4.6) with 11,116 prompt
 * tokens for a 65-token answer and cost US$ 0.0495 (cold 1 h cache write); the
 * warm turns of the same day cost US$ 0.018–0.021 with ~11,000 prompt tokens.
 * About 5,060 of those tokens are the cached prefix (tools + rules + Flow
 * policy); the other ~5,900 are paid at full price on every call: ~1,550 of
 * per-turn context and ~4,400 of history (50 lines).
 *
 * Fix, Flow channel only (processAuthenticatedMessage):
 *  1. the model receives every history line of the patient's current
 *     session — the current local day plus the 6 hours before the turn
 *     (MOBILE_FLOW_SESSION_HOURS) — and of what came before it only the
 *     newest lines that fit under 16 lines in all (mobileFlowPromptHistory,
 *     MOBILE_FLOW_PROMPT_HISTORY_LINES). The first version cut at the last 16
 *     lines of any day; the review of 2026-10-04 showed an allergy said 18
 *     lines earlier in the same session leaving the model's sight. The second
 *     version kept the local day only; the second review showed the same
 *     loss at 00:05, for a session that had started before midnight. The
 *     table read is unchanged, so the deterministic exercise/food answer and
 *     its "last reply" rules still see the whole list, and every line of a
 *     previous calendar day keeps its date prefix, inside the session or not;
 *  2. the per-turn context drops what the Flow cannot use: the clauses that
 *     call `confirma_pais_residencia` and `pausar_agente` (tools it does not
 *     have), the meal_type table, the meal suggestion and the replace warning
 *     (meal registration), the two photo rules, and the quote of the last two
 *     answers (already the last lines of the history; the instruction that
 *     pointed at the quote as "acima" now says where the answers are).
 *     Profile, date/time line, language rule and the whole "Dados numéricos
 *     REAIS" block are the same text as before, word for word;
 *  3. one `llm.flow_calls` event per turn with the numbers of each model call
 *     (no text of the patient or of the answer), next to `llm.cache_usage`;
 *     written for a turn that fails too, once.
 * Historical performance baseline (before C1): same tools/stable block, no
 * calculation rule changed, and WhatsApp is byte-identical
 * (audit-10-04-whatsapp-request-lock.test.ts).
 *
 * Every test runs the REAL pipeline entry with a fake database.
 *
 * > RC PERF-1 — cenário histórico e linha do dia REAIS da conta de QA às 15:21 NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A leitura do baseline não trouxe o texto das mensagens nem a linha do dia
 *   daquele minuto: a frase é a exata, o perfil e a linha do dia são os da
 *   leitura de 15:03:40Z do mesmo dia e o histórico do golden é sintético (59
 *   linhas).
 * > RC PERF-2 — cenário qualidade da resposta do MODELO com a janela do histórico e o contexto enxuto NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Não há chave de modelo local. Só uma rodada em staging ou no iPhone com as
 *   mesmas perguntas prova que a resposta não piorou. O modelo vê a sessão atual
 *   inteira (o dia de hoje e as 6 horas antes do turno) e deixa de ver as linhas
 *   anteriores a ela além das que completam 16.
 * > RC PERF-W1 — cenário alergia ou intolerância dita em DIA ANTERIOR há mais de 6 horas, fora da janela (por exemplo, ontem de manhã, com 16 ou mais linhas na sessão atual) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O modelo não lê a linha e o gerador de cardápio recebe "(nenhuma)".
 *   Restrições não são gravadas no perfil; gravar é a solução de fundo e fica
 *   fora desta mudança. Travado como pendência em
 *   `audit-10-04-flow-turn-calls.test.ts`, em dois casos: dita ontem de manhã
 *   com 20 linhas hoje; e dita às 17:50, com o turno às 00:05 e 20 linhas depois
 *   das 23:30. A linha de dia anterior dita nas 6 horas antes do turno está
 *   coberta.
 * > RC PERF-W2 — cenário alergia dita há mais de 49 linhas no MESMO dia NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A leitura do banco traz 50 linhas; o que ficou antes disso nunca chegou ao
 *   modelo, antes ou depois desta mudança.
 * > RC PERF-3 — cenário tokens reais (prompt_tokens cobrados) antes × depois NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Os testes medem caracteres e linhas, e os tokens são estimativa (caracteres
 *   ÷ 3,0). O evento `llm.flow_calls` é o que mede em staging.
 * > RC PERF-4 — cenário linhas "DIA PENDENTE"/"FOTO PENDENTE"/fotos corporais do contexto (mandam chamar marca_refeicao_pulada/registra_refeicao, que o Flow não tem) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O mapa não mediu esses blocos no Flow e eles ficaram como estavam.
 * > RC PERF-5 — cenário paciente do app com país NÃO confirmado NÃO coberto em dado real nesta PR (pendência da audit 2026-10-04).
 *   O contexto deixa de mandar perguntar o país, porque o Flow não tem a tool
 *   que grava a resposta (travado no golden). Não sei se existe conta do app
 *   nesse estado.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import type { PipelineDeps } from '../pipeline.js'
import {
  MOBILE_FLOW_CALLS_EVENT,
  MOBILE_FLOW_PROMPT_HISTORY_LINES,
  MOBILE_FLOW_SESSION_HOURS,
  mobileFlowPromptHistory,
  mobileFlowSystemPolicy,
  processAuthenticatedMessage,
  processMessage,
} from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'

// ── The report ──────────────────────────────────────────────────────────────
/** Exact phrase of the baseline turn (10-04 15:21, single call, 11,116 tokens). */
const PHRASE = 'O treino de hoje aumenta minha meta de calorias?'
/** Last exact readout of the QA account that day (audit RC A). */
const NOW = new Date('2026-10-04T15:03:40.503Z')
const USER_ID = 'qa-a'
const TURN_ID = 'mobile_flow/qa-a/perf-turn'
const MODEL = 'anthropic/claude-sonnet-4.6'

/** The direct question the system answers without the model (audit RC A). */
const DIRECT_QUESTION = 'Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?'
const ANSWER_541 =
  'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.'
const FLOW_QUESTION =
  'Você está 2.439 kcal abaixo da meta de hoje. Está conseguindo comer nas refeições principais?'

type Row = Record<string, unknown>

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

const PROGRESS: Row = {
  current_streak: 0,
  longest_streak: 0,
  xp_total: 0,
  level: 1,
  blocks_completed: 0,
  deficit_block: 0,
  last_active_date: null,
}

const USER: Row = {
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

interface ScriptedStep {
  content?: string
  toolCalls?: Array<{ id: string; name: string; arguments: string }>
  promptTokens?: number
  completionTokens?: number
  cacheRead?: number
  cacheWrite?: number
  costUsd?: number | null
  /** How long the call takes on the (fake) clock. */
  ms?: number
}

interface Fixture {
  channel?: 'flow' | 'whatsapp'
  user?: Row
  day?: Row | null
  history?: Row[]
  text?: string
  script?: ScriptedStep[]
  /** Makes the insert of this event fail: 'throw' or a rejected promise. */
  failEvent?: { name: string; how: 'throw' | 'reject' }
}

interface LlmCall {
  model: string
  systemPrompt: unknown
  tools: unknown[]
  messages: Array<{ role: string; content: string }>
  keys: string[]
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Row }>
  llmCalls: LlmCall[]
  messageReads: Array<{ provider: unknown; limit: number | null }>
}

/**
 * Fake client that honours the filters the pipeline sends: messages are
 * filtered by provider, newest first, cut at the limit asked; the day row
 * answers only the read of its date.
 */
function harness(fixture: Fixture = {}): Harness {
  const provider = fixture.channel === 'whatsapp' ? 'whatsapp' : 'mobile_flow'
  const day = fixture.day === undefined ? S541 : fixture.day
  const text = fixture.text ?? PHRASE
  const script = fixture.script ?? [{ content: 'Resposta do modelo.' }]
  const inserts: Harness['inserts'] = []
  const llmCalls: LlmCall[] = []
  const messageReads: Harness['messageReads'] = []
  const stored: Row[] = [
    ...(fixture.history ?? []).map((row) => ({ ...row, provider })),
    {
      direction: 'in',
      content: text,
      content_type: 'text',
      created_at: NOW.toISOString(),
      provider,
      provider_message_id: TURN_ID,
    },
  ]

  interface Read {
    table: string
    columns: string
    filters: Row
    limit: number | null
  }

  const rowsFor = (read: Read): unknown => {
    switch (read.table) {
      case 'users':
        return fixture.user ?? USER
      case 'user_profiles':
        return PROFILE
      case 'user_progress':
        return PROGRESS
      case 'messages': {
        messageReads.push({ provider: read.filters.provider ?? null, limit: read.limit })
        const rows = stored
          .filter((row) => read.filters.provider == null || row.provider === read.filters.provider)
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
        return read.limit == null ? rows : rows.slice(0, read.limit)
      }
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return []
        if (!day || read.filters.date !== '2026-10-04') return null
        if (read.columns.trim() === '*') return day
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), day[key.trim()] ?? null]),
        )
      }
      case 'global_config':
        // The model router stays off: the turn keeps the stage's model.
        if (read.filters.key === 'router.haiku_enabled') return { value: false }
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
          model: MODEL,
          temperature: 0.2,
          max_tokens: 1200,
          max_tool_iterations: 2,
          system_prompt: 'REGRAS COMPARTILHADAS',
          allowed_tools: null,
        }
      default:
        return []
    }
  }

  const supabase = {
    from(table: string) {
      const read: Read = { table, columns: '', filters: {}, limit: null }
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
      chain.limit = (count: number) => {
        read.limit = count
        return chain
      }
      chain.insert = (row: Row) => {
        if (fixture.failEvent && row.event === fixture.failEvent.name) {
          if (fixture.failEvent.how === 'throw') throw new Error('insert failed')
          return Promise.reject(new Error('insert failed'))
        }
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
    complete: async (input: {
      model: string
      systemPrompt: unknown
      tools: unknown[]
      messages: Array<{ role: string; content: string }>
    }) => {
      llmCalls.push({
        model: input.model,
        systemPrompt: input.systemPrompt,
        tools: input.tools,
        messages: input.messages.map((message) => ({ ...message })),
        keys: Object.keys(input).sort(),
      })
      const step = script[Math.min(call, script.length - 1)] ?? {}
      call += 1
      if (step.ms) vi.advanceTimersByTime(step.ms)
      return {
        content: step.content ?? '',
        toolCalls: step.toolCalls ?? [],
        model: MODEL,
        promptTokens: step.promptTokens ?? 7400,
        completionTokens: step.completionTokens ?? 65,
        cacheReadInputTokens: step.cacheRead ?? 5060,
        cacheCreationInputTokens: step.cacheWrite ?? 0,
        costUsd: step.costUsd === undefined ? 0.0098 : step.costUsd,
      }
    },
  } as unknown as PipelineDeps['llm']

  return { deps: { supabase, llm, maxToolIterations: 3 }, inserts, llmCalls, messageReads }
}

function flow(h: Harness, text: string = PHRASE) {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: TURN_ID,
    text,
    timestamp: NOW,
  })
}

function whatsapp(h: Harness, text: string = PHRASE) {
  return processMessage(h.deps, {
    from: '5511999999999',
    providerMessageId: TURN_ID,
    text,
    contentType: 'text',
    provider: 'whatsapp',
    timestamp: NOW,
  })
}

function events(h: Harness, name: string): Row[] {
  return h.inserts
    .filter((entry) => entry.table === 'product_events' && entry.row.event === name)
    .map((entry) => entry.row)
}

function systemBlocks(call: LlmCall | undefined): Array<{ text: string; cache?: string }> {
  expect(Array.isArray(call?.systemPrompt)).toBe(true)
  return call?.systemPrompt as Array<{ text: string; cache?: string }>
}

/** The per-turn (never cached) system block of a call. */
function variableBlock(call: LlmCall | undefined): string {
  return systemBlocks(call)[1]?.text ?? ''
}

const PREVIOUS_DAY_PREFIX =
  '[Mensagem de 03/10/2026, dia anterior — números do dia e horário citados nela não valem para hoje]\n'

const OUT_SHORT =
  'Hoje você está em 541 kcal de 2.980 kcal, com 59 g de proteína de 144 g. Quer ajuda para pensar no jantar?'
const OUT_PLAIN = 'Sua meta de proteína de hoje é 144 g; você já consumiu 59 g.'
const INS = [
  'Quanto falta de proteína hoje?',
  'Mostre meu progresso recente.',
  'Como foi minha semana?',
  'Tenho intolerância a lactose, lembra disso.',
]

/** Text of the stored line `index` (0 = oldest), before any date prefix. */
function lineText(index: number): string {
  const pair = Math.floor(index / 2)
  if (index % 2 === 0) return `${INS[pair % INS.length] as string} (${index})`
  return `${pair % 2 === 0 ? OUT_PLAIN : OUT_SHORT} (${index})`
}

/**
 * 59 stored Flow lines before the current message, alternating patient/Flow
 * and starting with the patient: the 49 oldest on the previous local day
 * (03/10), the 10 newest today. With the current inbound the channel holds 60
 * rows; the pipeline reads the newest 50 (49 history lines).
 * `lastOut` replaces the text of the newest Flow reply.
 */
function longHistory(lastOut?: string): Row[] {
  const rows: Row[] = []
  for (let index = 0; index < 59; index += 1) {
    const previousDay = index < 49
    const at = previousDay
      ? new Date(Date.parse('2026-10-03T12:00:00.000Z') + index * 60_000).toISOString()
      : new Date(NOW.getTime() - (59 - index) * 60_000).toISOString()
    // 59 lines starting with the patient end with the patient (index 58); the
    // newest Flow reply is index 57.
    const content = index === 57 && lastOut ? lastOut : lineText(index)
    rows.push({
      direction: index % 2 === 0 ? 'in' : 'out',
      content,
      content_type: 'text',
      created_at: at,
      provider_message_id: `mobile_flow/qa-a/h${index}`,
    })
  }
  return rows
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

describe('audit 2026-10-04 Flow cost — history window: 16 lines to the model when today is short, 50 rows read', () => {
  it('the exact baseline phrase with 59 stored lines: the model receives the newest 16 and the current message', async () => {
    const h = harness({ history: longHistory() })
    const output = await flow(h)

    expect(output.text).toBe('Resposta do modelo.')
    expect(h.llmCalls).toHaveLength(1)
    expect(MOBILE_FLOW_PROMPT_HISTORY_LINES).toBe(16)

    const messages = h.llmCalls[0]?.messages ?? []
    expect(messages).toHaveLength(17)
    expect(messages.at(-1)).toEqual({ role: 'user', content: PHRASE })

    // The newest 16 stored lines, oldest first: 43…58. 43–48 are of 03/10.
    const expected = Array.from({ length: 16 }, (_, offset) => {
      const index = 43 + offset
      return {
        role: index % 2 === 0 ? 'user' : 'assistant',
        content: index < 49 ? PREVIOUS_DAY_PREFIX + lineText(index) : lineText(index),
      }
    })
    expect(messages.slice(0, 16)).toEqual(expected)
  })

  it('previous-day lines inside the window keep their date prefix, word for word; lines of today have none', async () => {
    const h = harness({ history: longHistory() })
    await flow(h)

    const history = (h.llmCalls[0]?.messages ?? []).slice(0, -1)
    const dated = history.filter((message) => message.content.startsWith('[Mensagem de'))
    expect(dated).toHaveLength(6)
    for (const message of dated) {
      expect(message.content.startsWith(PREVIOUS_DAY_PREFIX)).toBe(true)
    }
    expect(history[0]?.content).toBe(`${PREVIOUS_DAY_PREFIX}${lineText(43)}`)
    expect(history.slice(6).every((message) => !message.content.includes('dia anterior'))).toBe(
      true,
    )
  })

  it('the table read is the same as before: provider mobile_flow, 50 rows', async () => {
    const h = harness({ history: longHistory() })
    await flow(h)

    expect(h.messageReads).toEqual([{ provider: 'mobile_flow', limit: 50 }])
  })

  it('a short conversation is sent whole: 5 stored lines, 5 history lines', async () => {
    const h = harness({ history: longHistory().slice(-5) })
    await flow(h)

    const messages = h.llmCalls[0]?.messages ?? []
    expect(messages).toHaveLength(6)
    expect(messages.slice(0, 5).map((message) => message.content)).toEqual(
      [54, 55, 56, 57, 58].map(lineText),
    )
  })

  it('the second call of a turn (after a tool) carries the same 16 lines plus the tool exchange', async () => {
    const h = harness({
      history: longHistory(),
      script: [
        { toolCalls: [{ id: 'toolu_perf_01', name: 'consulta_metricas', arguments: '{}' }] },
        { content: 'Sua taxa basal estimada é de 1.836 kcal.' },
      ],
    })
    const output = await flow(h)

    expect(output.text).toBe('As metas oficiais de hoje são 2.980 kcal e 144 g de proteína. Você pode acompanhá-las em Hoje.')
    expect(h.llmCalls).toHaveLength(2)
    const [first, second] = h.llmCalls as [LlmCall, LlmCall]
    expect(second.messages).toHaveLength(19)
    expect(second.messages.slice(0, 17)).toEqual(first.messages)
    expect(second.messages.slice(17).map((message) => message.role)).toEqual(['assistant', 'tool'])
    // Same system blocks in both calls: the cached prefix is read again.
    expect(second.systemPrompt).toEqual(first.systemPrompt)
  })

  it('WhatsApp with the same 59 stored lines still sends all 49 it reads, with no date prefix', async () => {
    const h = harness({ channel: 'whatsapp', history: longHistory() })
    await whatsapp(h)

    const messages = h.llmCalls[0]?.messages ?? []
    expect(messages).toHaveLength(50)
    expect(messages.some((message) => message.content.startsWith('[Mensagem de'))).toBe(false)
    expect(h.messageReads).toEqual([{ provider: null, limit: 50 }])
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)).toHaveLength(0)
  })
})

/**
 * `today` lines of the current local day after `previous` lines of 03/10,
 * alternating patient/Flow, one minute apart, oldest first.
 */
function daySplitHistory(previous: number, today: number): Row[] {
  const total = previous + today
  return Array.from({ length: total }, (_, index) => ({
    direction: index % 2 === 0 ? 'in' : 'out',
    content: lineText(index),
    content_type: 'text',
    created_at:
      index < previous
        ? new Date(Date.parse('2026-10-03T12:00:00.000Z') + index * 60_000).toISOString()
        : new Date(NOW.getTime() - (total - index) * 60_000).toISOString(),
    provider_message_id: `mobile_flow/qa-a/d${index}`,
  }))
}

describe('audit 2026-10-04 Flow cost — the window keeps every line of the current session and cuts only what came before it', () => {
  // The review of 2026-10-04: with a flat cut at 16 lines, an allergy said 18
  // lines earlier in the same session never reached the model (the generator
  // side is locked in audit-10-04-flow-turn-calls.test.ts).
  it.each([
    // previous-day lines, lines of today → lines sent, of which dated
    ['the doc case: 39 of previous days, 10 of today', 39, 10, 16, 6],
    ['49 lines, all of today: the whole session', 0, 49, 49, 0],
    ['29 of previous days, 20 of today: today only', 29, 20, 20, 0],
    ['33 of previous days, 16 of today: today only', 33, 16, 16, 0],
    ['34 of previous days, 15 of today: one dated line fills the window', 34, 15, 16, 1],
    ['49 lines, none of today: the newest 16, all dated', 49, 0, 16, 16],
    ['3 of previous days, 2 of today: everything', 3, 2, 5, 3],
  ])('%s', async (_label, previous, today, sent, dated) => {
    const stored = daySplitHistory(previous, today)
    const h = harness({ history: stored })
    await flow(h)

    const history = (h.llmCalls[0]?.messages ?? []).slice(0, -1)
    expect(history).toHaveLength(sent)
    expect(
      history.filter((message) => message.content.startsWith(PREVIOUS_DAY_PREFIX)),
    ).toHaveLength(dated)
    // The lines sent are the newest ones, in order: nothing in between is dropped.
    const total = previous + today
    expect(history.map((message) => message.content)).toEqual(
      Array.from({ length: sent }, (_, offset) => {
        const index = total - sent + offset
        return index < previous ? PREVIOUS_DAY_PREFIX + lineText(index) : lineText(index)
      }),
    )
    // The telemetry counts what was sent.
    expect(
      (events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as { calls: Row[] }).calls[0],
    ).toMatchObject({ history_lines: sent, messages: sent + 1 })
  })

  // The second review of 2026-10-04: the session was the local day alone, so
  // one that crossed midnight was cut to 16 lines minutes later (the
  // generator side, with the reviewer's exact scenario, is locked in
  // audit-10-04-flow-turn-calls.test.ts). Here the same stored lines are
  // read by a patient whose local midnight was three minutes ago: in Tokyo
  // NOW is 00:03 of 05/10, the 3 newest lines are of that day and the other
  // lines of the last 49 minutes are of 04/10.
  const TOKYO = { ...USER, timezone: 'Asia/Tokyo' }
  const DATED_04 =
    '[Mensagem de 04/10/2026, dia anterior — números do dia e horário citados nela não valem para hoje]\n'

  it('the session reaches 6 hours back', () => {
    expect(MOBILE_FLOW_SESSION_HOURS).toBe(6)
  })

  it.each([
    // older lines (03/10), lines of the last 49 minutes → sent, dated 03/10, dated 04/10
    ['49 lines across midnight: the whole session, 46 of them dated', 0, 49, 49, 0, 46],
    ['20 older lines, 29 across midnight: the session only', 20, 29, 29, 0, 26],
    ['40 older lines, 9 across midnight: older lines fill up to 16', 40, 9, 16, 7, 6],
    ['47 older lines, 2 after midnight: older lines fill up to 16', 47, 2, 16, 14, 0],
  ])('local midnight three minutes ago — %s', async (_label, older, recent, sent, dated03, dated04) => {
    const h = harness({ user: TOKYO, history: daySplitHistory(older, recent) })
    await flow(h)

    const history = (h.llmCalls[0]?.messages ?? []).slice(0, -1)
    expect(history).toHaveLength(sent)
    expect(
      history.filter((message) => message.content.startsWith(PREVIOUS_DAY_PREFIX)),
    ).toHaveLength(dated03)
    expect(history.filter((message) => message.content.startsWith(DATED_04))).toHaveLength(dated04)
    // The newest lines, in order, each with the prefix of its own day.
    const total = older + recent
    expect(history.map((message) => message.content)).toEqual(
      Array.from({ length: sent }, (_, offset) => {
        const index = total - sent + offset
        if (index < older) return PREVIOUS_DAY_PREFIX + lineText(index)
        return total - index > 3 ? DATED_04 + lineText(index) : lineText(index)
      }),
    )
    expect(
      (events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as { calls: Row[] }).calls[0],
    ).toMatchObject({ history_lines: sent, messages: sent + 1 })
  })

  it('lines of today said more than 6 hours before the turn are still the session: 20 at 00:30 and 29 just now, 49 sent', async () => {
    const stored = daySplitHistory(0, 49).map((row, index) =>
      index < 20
        ? {
            ...row,
            // 00:30 to 00:49 in São Paulo on 04/10, 11 hours before NOW.
            created_at: new Date(
              Date.parse('2026-10-04T03:30:00.000Z') + index * 60_000,
            ).toISOString(),
          }
        : row,
    )
    const h = harness({ history: stored })
    await flow(h)

    const history = (h.llmCalls[0]?.messages ?? []).slice(0, -1)
    expect(history.map((message) => message.content)).toEqual(
      Array.from({ length: 49 }, (_, index) => lineText(index)),
    )
  })

  it('WhatsApp across midnight still sends everything it reads, with no date prefix', async () => {
    const h = harness({ channel: 'whatsapp', user: TOKYO, history: daySplitHistory(40, 9) })
    await whatsapp(h)

    const messages = h.llmCalls[0]?.messages ?? []
    expect(messages).toHaveLength(50)
    expect(messages.some((message) => message.content.startsWith('[Mensagem de'))).toBe(false)
  })

  it.each([
    ['all of today', [false, false, false], ['a', 'b', 'c']],
    ['no flags at all: nothing is known to be old, nothing is cut', [], ['a', 'b', 'c']],
  ])('the window function, short lists — %s', (_label, flags, expected) => {
    expect(mobileFlowPromptHistory(['a', 'b', 'c'], flags)).toEqual(expected)
  })

  it('the window function: a line flagged as outside the session between lines of the session is cut like any other old line', () => {
    // 18 lines of the session around one line flagged as outside it (rows
    // are read in time order, so this is not expected; the rule still holds).
    const lines = Array.from({ length: 19 }, (_, index) => `l${index}`)
    const flags = lines.map((_, index) => index === 5)
    expect(mobileFlowPromptHistory(lines, flags)).toEqual(lines.filter((_, index) => index !== 5))
  })

  it('the window function fills from the newest previous-day lines and keeps the order', () => {
    const lines = Array.from({ length: 30 }, (_, index) => index)
    // 20 previous-day lines, then 10 of today.
    const flags = lines.map((index) => index < 20)
    expect(mobileFlowPromptHistory(lines, flags)).toEqual(
      Array.from({ length: MOBILE_FLOW_PROMPT_HISTORY_LINES }, (_, offset) => 14 + offset),
    )
  })

  it('WhatsApp is not windowed by day either: 49 lines of today, 49 lines sent', async () => {
    const h = harness({ channel: 'whatsapp', history: daySplitHistory(0, 49) })
    await whatsapp(h)

    expect(h.llmCalls[0]?.messages).toHaveLength(50)
  })
})

describe('audit 2026-10-04 Flow cost — the deterministic exercise/food answer still reads the last Flow reply', () => {
  it('59 stored lines, direct question: the system answers, the model is never called', async () => {
    const h = harness({ history: longHistory(), text: DIRECT_QUESTION })
    const output = await flow(h, DIRECT_QUESTION)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(1)
    // No model call, no per-call numbers.
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)).toHaveLength(0)
  })

  it('59 stored lines and the last Flow reply is that very answer: the model answers, with 16 lines (9 of today, 7 dated)', async () => {
    // Line 58 (a patient line after the reply) is dropped so the reply is the
    // newest stored line, as right after the system answered.
    const h = harness({ history: longHistory(ANSWER_541).slice(0, 58), text: DIRECT_QUESTION })
    const output = await flow(h, DIRECT_QUESTION)

    expect(output.text).toBe('Resposta do modelo.')
    expect(h.llmCalls).toHaveLength(1)
    const messages = h.llmCalls[0]?.messages ?? []
    expect(messages).toHaveLength(17)
    expect(messages.at(-2)).toEqual({ role: 'assistant', content: ANSWER_541 })
    expect(events(h, 'pipeline.deterministic_exercise_food')).toHaveLength(0)
  })

  it('59 stored lines and Flow had just asked a question: a message with no "?" is the patient answering, the model answers', async () => {
    const text = 'Treinei hoje e dá pra comer mais'
    const h = harness({ history: longHistory(FLOW_QUESTION).slice(0, 58), text })
    const output = await flow(h, text)

    expect(output.text).toBe('Resposta do modelo.')
    expect(h.llmCalls).toHaveLength(1)
    expect(h.llmCalls[0]?.messages.at(-2)).toEqual({ role: 'assistant', content: FLOW_QUESTION })
  })

  it('the same message when Flow had NOT asked anything: the system answers', async () => {
    const text = 'Treinei hoje e dá pra comer mais'
    const h = harness({ history: longHistory(OUT_PLAIN).slice(0, 58), text })
    const output = await flow(h, text)

    expect(output.text).toBe(ANSWER_541)
    expect(h.llmCalls).toHaveLength(0)
  })
})

// ── Lean per-turn context ───────────────────────────────────────────────────

/** The whole per-turn block of the baseline turn, character by character. */
const LEAN_CONTEXT = [
  '',
  '',
  '## Contexto do usuário',
  '### Localização e preferências',
  'País: **BR** (confirmado). Idioma salvo: **pt-BR**. Unidades: **kg / cm (métrico)**. Persona: Flow. NÃO pergunte país de novo. ',
  '',
  '⚠️ **REGRA DE IDIOMA (inviolável):** responda no idioma que o paciente está usando AGORA na última mensagem. Se o paciente pedir explicitamente pra mudar de idioma (ex: "fale em português", "switch to English"), MUDE IMEDIATAMENTE. ',
  '',
  '### Hora local do paciente AGORA',
  '**domingo, 04/10/2026 12:03** (timezone: America/Sao_Paulo, hora local = 12h)',
  '',
  '- Nome: QA A',
  '- Sexo: masculino',
  '- Idade: 26',
  '- Altura: 185 cm',
  '- Peso: 80.5 kg',
  '- Gordura corporal: ?',
  '- Atividade: moderado',
  '- Treinos/semana: 4',
  '- Protocolo atual: ganho_massa',
  '- IMC: 23.5',
  '- Decisão automática: protocol=recomposicao canChoose=false blockers=[horários de sono não informados; estruturação alimentar não informada] goal=IMC=22',
  '',
  '### Dados numéricos REAIS do paciente (use estes, NÃO INVENTE)',
  '⚠️ Estes valores são canônicos — calculados pelo sistema. NUNCA recalcule meta/balanço/streak na cabeça nem invente números diferentes destes.',
  '',
  '- Meta calórica de hoje: **2980 kcal**',
  '- Meta de proteína de hoje: **144 g**',
  '- Consumido hoje: 541 kcal | 59.03 g proteína | 47.32g carbo | 10.27g gordura',
  '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2439 kcal',
  '- Exercício hoje: 322 kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida',
  '- Balanço calórico de hoje (consumido − gasto de referência de 2838 kcal; o exercício já está considerado neste valor e não é somado): -2297 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
  '- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; o que o paciente pode comer é só o que está na linha "Para COMIDA". Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso e mostre meta, consumido e o que resta para comida; o gasto do treino fica à parte.',
  '- Sequência atual: 0 dias consecutivos (recorde 0) | XP: 0 (nível 1)',
  '',
  '### Regras importantes',
  '1. Cadência humana: 1 pergunta por turno. Se for resposta longa, separe em parágrafos com \\n\\n (o sistema quebra em chunks naturais).',
  '2. Não repita o nome do usuário no início de toda resposta — use vocativo no fim ou em momentos de validação emocional, não como prefixo automático.',
  '',
  '## Anti-repetição (CRÍTICO)',
  '→ NÃO repita aberturas, frases âncora ou bullets de balanço se já estão nas suas últimas respostas do histórico.',
  '→ Se nada de novo aconteceu (user só disse "oi" ou similar), responda CURTO. Não force conteúdo.',
  '→ Varie a saudação. Banco de aberturas curtas (escolha uma quando fizer sentido):',
  '   "Boa.", "Show.", "Beleza.", "Pronto.", "Saquei.", "Recebi.", "Hmm.", (sem nada/direto na resposta)',
].join('\n')

/** Nothing of these may reach the Flow's per-turn context. */
const DROPPED = [
  'confirma_pais_residencia',
  'pausar_agente',
  'meal_type',
  'replace=true',
  'Sugestão pra esta refeição',
  'NUNCA invente o conteúdo de uma foto',
  'Foto e legenda no mesmo turno',
  'Pergunte cidade e estado',
  'Suas últimas respostas foram',
  '[1] "',
]

describe('audit 2026-10-04 Flow cost — lean per-turn context', () => {
  it('the baseline turn: exact per-turn text (2,750 after C3; 2,827 after C1; initially 4,719)', async () => {
    const h = harness({ history: longHistory() })
    await flow(h)

    const variable = variableBlock(h.llmCalls[0])
    expect(variable).toBe(LEAN_CONTEXT)
    // C3 removes 26 block-count characters and the 51-character block line.
    expect(variable).toHaveLength(2750)
    for (const dropped of DROPPED) expect(variable, dropped).not.toContain(dropped)
  })

  it('the cached prefix follows the current Flow policy with the same 6 tools', async () => {
    const h = harness({ history: longHistory() })
    await flow(h)

    const call = h.llmCalls[0] as LlmCall
    expect(systemBlocks(call)[0]).toEqual({
      text: `REGRAS COMPARTILHADAS${mobileFlowSystemPolicy}`,
      cache: 'ephemeral_1h',
    })
    expect(
      (call.tools as Array<{ function: { name: string } }>).map((tool) => tool.function.name),
    ).toEqual([
      'consulta_progresso',
      'consulta_metricas',
      'consulta_resumo_periodo',
      'consulta_reavaliacao_protocolo',
      'propoe_plano_treino',
      'propoe_plano_dieta',
    ])
    // The prompt-size part added no argument. The two time-limit arguments
    // came with the next part (audit-10-04-flow-turn-calls.test.ts), and
    // neither is part of the prompt.
    expect(call.keys).toEqual([
      'cacheTools',
      'cacheToolsTtl',
      'maxRetries',
      'maxTokens',
      'messages',
      'metadata',
      'model',
      'requestTimeoutMs',
      'systemPrompt',
      'temperature',
      'tools',
      'userId',
    ])
  })

  it('every context change from the legacy channel is accounted for, including C1 public terminology', async () => {
    const flowRun = harness({ history: longHistory() })
    await flow(flowRun)
    const legacyRun = harness({ channel: 'whatsapp', history: longHistory() })
    await whatsapp(legacyRun)

    const flowLines = variableBlock(flowRun.llmCalls[0]).split('\n')
    // The persona name is the one difference that already existed.
    const legacy = variableBlock(legacyRun.llmCalls[0]).replace(
      'Persona: Dr. Roberto Menescal.',
      'Persona: Flow.',
    )
    const legacyLines = legacy.split('\n')
    expect(legacy).toContain('confirma_pais_residencia')
    expect(legacy).toContain('pausar_agente')

    const numericStart = flowLines.indexOf(
      '### Dados numéricos REAIS do paciente (use estes, NÃO INVENTE)',
    )
    const numericEnd = flowLines.indexOf('### Regras importantes')
    expect(numericStart).toBeGreaterThan(-1)
    expect(numericEnd).toBeGreaterThan(numericStart)

    // The lines cut or reworded from a legacy line, each checked against its origin.
    const cut: Record<string, (line: string) => boolean> = {
      // C1 public terminology, only on Flow; the legacy field is unchanged.
      '- Gordura corporal:': (line) => legacyLines.includes(line.replace('Gordura corporal:', 'BF%:')),
      // Anti-repetition: the legacy instruction, with "acima" (the quoted
      // answers the Flow no longer repeats) named as where they are now.
      '→ NÃO repita aberturas': (line) =>
        line.endsWith(' se já estão nas suas últimas respostas do histórico.') &&
        legacyLines.includes(line.replace('nas suas últimas respostas do histórico.', 'acima.')),
      // Language rule: the legacy sentence up to "MUDE IMEDIATAMENTE".
      '⚠️ **REGRA DE IDIOMA (inviolável):**': (line) =>
        legacyLines.some((legacyLine) =>
          legacyLine.startsWith(
            `${line.slice(0, -2)} e chame \`confirma_pais_residencia\` de novo com o \`language\` atualizado pra persistir.`,
          ),
        ),
      // Heading: the legacy heading without its meal_type parenthesis.
      '### Hora local do paciente AGORA': (line) =>
        legacyLines.includes(`${line} (use pra meal_type — NÃO adivinhe pelos alimentos)`),
      // Rules 2 and 3 of the legacy list, renumbered 1 and 2.
      '1. Cadência humana:': (line) => legacyLines.includes(`2${line.slice(1)}`),
      '2. Não repita o nome do usuário': (line) => legacyLines.includes(`3${line.slice(1)}`),
    }

    const unexplained: string[] = []
    flowLines.forEach((line, index) => {
      // The numeric block differs by design (Flow energy lines, day-row
      // target); it is locked on its own in audit-10-04-flow-exercise-food.
      if (index > numericStart && index < numericEnd) return
      if (legacyLines.includes(line)) return
      const rule = Object.entries(cut).find(([start]) => line.startsWith(start))
      if (rule?.[1](line)) return
      unexplained.push(line)
    })
    expect(unexplained).toEqual([])
  })

  it('the numeric block is the one the exercise/food golden locks, line by line', async () => {
    const h = harness({ history: longHistory() })
    await flow(h)

    const variable = variableBlock(h.llmCalls[0])
    const start = variable.indexOf('### Dados numéricos REAIS')
    const end = variable.indexOf('### Regras importantes')
    expect(variable.slice(start, end).trimEnd().split('\n')).toEqual([
      '### Dados numéricos REAIS do paciente (use estes, NÃO INVENTE)',
      '⚠️ Estes valores são canônicos — calculados pelo sistema. NUNCA recalcule meta/balanço/streak na cabeça nem invente números diferentes destes.',
      '',
      '- Meta calórica de hoje: **2980 kcal**',
      '- Meta de proteína de hoje: **144 g**',
      '- Consumido hoje: 541 kcal | 59.03 g proteína | 47.32g carbo | 10.27g gordura',
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2439 kcal',
      '- Exercício hoje: 322 kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida',
      '- Balanço calórico de hoje (consumido − gasto de referência de 2838 kcal; o exercício já está considerado neste valor e não é somado): -2297 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
      '- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; o que o paciente pode comer é só o que está na linha "Para COMIDA". Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso e mostre meta, consumido e o que resta para comida; o gasto do treino fica à parte.',
      '- Sequência atual: 0 dias consecutivos (recorde 0) | XP: 0 (nível 1)',
    ])
  })

  it('first message of a conversation: no anti-repetition block at all', async () => {
    const h = harness()
    await flow(h)

    const variable = variableBlock(h.llmCalls[0])
    expect(variable).not.toContain('## Anti-repetição')
    expect(variable.endsWith('momentos de validação emocional, não como prefixo automático.')).toBe(
      true,
    )
    expect(h.llmCalls[0]?.messages).toEqual([{ role: 'user', content: PHRASE }])
  })

  it('a patient in the United States writing in English: language default, imperial units and the Brazil note stay; no tool is named', async () => {
    const h = harness({
      user: {
        ...USER,
        country: 'US',
        locale: 'en',
        timezone: 'America/New_York',
        metadata: { unit_system: 'imperial' },
      },
      text: 'Does my workout raise my calorie target?',
    })
    await flow(h, 'Does my workout raise my calorie target?')

    const variable = variableBlock(h.llmCalls[0])
    expect(variable).toContain(
      'País: **US** (confirmado). Idioma salvo: **en**. Unidades: **lb / inch (imperial)**. Persona: Flow. NÃO pergunte país de novo. ',
    )
    expect(variable).toContain(
      'MUDE IMEDIATAMENTE. Idioma salvo é en — use esse por padrão se o paciente continuar nele. ',
    )
    expect(variable).toContain(
      '**Unidades imperial:** quando o paciente informar peso/altura, provavelmente usará lb/inch. Converta internamente pra kg/cm (1 lb=0.4536 kg, 1 inch=2.54 cm) antes de salvar via tool. Devolva metas/balanço em lb/inch. Se ele te der um valor em kg, ACEITE — não peça pra reconverter. ',
    )
    expect(variable).toContain(
      '⚠️ Sistema otimizado pra Brasil (TACO, alimentos locais BR). Comidas regionais de US podem ter macros imprecisos.',
    )
    expect(variable).toContain(
      '### Hora local do paciente AGORA\n**domingo, 04/10/2026 11:03** (timezone: America/New_York, hora local = 11h)',
    )
    for (const dropped of DROPPED) expect(variable, dropped).not.toContain(dropped)
  })

  it('country not confirmed: the status line stays, the order to ask and call the tool does not', async () => {
    const h = harness({
      user: { ...USER, country_confirmed: false, country_detected_from_wpp: 'BR' },
    })
    await flow(h)

    const variable = variableBlock(h.llmCalls[0])
    expect(variable).toContain(
      '## Contexto do usuário\n### País de residência (NÃO confirmado)\nStatus: palpite pelo DDI do WhatsApp: BR.\n\n### Hora local do paciente AGORA\n',
    )
    for (const dropped of DROPPED) expect(variable, dropped).not.toContain(dropped)
    expect(variable).not.toContain('Pergunte explicitamente')
  })
})

// ── Per-call telemetry ──────────────────────────────────────────────────────

const charsOf = (messages: LlmCall['messages']): number =>
  messages.reduce(
    (sum, message) => sum + (typeof message.content === 'string' ? message.content.length : 0),
    0,
  )

describe('audit 2026-10-04 Flow cost — per-call telemetry, numbers only', () => {
  const TWO_CALLS: ScriptedStep[] = [
    {
      toolCalls: [{ id: 'toolu_perf_01', name: 'consulta_metricas', arguments: '{}' }],
      promptTokens: 7421,
      completionTokens: 31,
      cacheRead: 0,
      cacheWrite: 5060,
      costUsd: 0.0379,
      ms: 1800,
    },
    {
      content: 'Sua taxa basal estimada é de 1.836 kcal.',
      promptTokens: 7560,
      completionTokens: 42,
      cacheRead: 5060,
      cacheWrite: 0,
      costUsd: 0.0096,
      ms: 2300,
    },
  ]

  it('a two-call turn writes one llm.flow_calls event with the numbers of each call', async () => {
    const h = harness({ history: longHistory(), script: TWO_CALLS })
    await flow(h)

    const [first, second] = h.llmCalls as [LlmCall, LlmCall]
    const blocks = systemBlocks(first)
    const systemChars = [blocks[0]?.text.length, blocks[1]?.text.length]
    expect(systemChars).toEqual([`REGRAS COMPARTILHADAS${mobileFlowSystemPolicy}`.length, 2750])

    expect(events(h, MOBILE_FLOW_CALLS_EVENT)).toEqual([
      {
        user_id: USER_ID,
        event: 'llm.flow_calls',
        properties: {
          stage: 'ganho_massa',
          call_count: 2,
          tools_chars: JSON.stringify(first.tools).length,
          calls: [
            {
              index: 0,
              model: MODEL,
              prompt_tokens: 7421,
              completion_tokens: 31,
              cache_read_tokens: 0,
              cache_write_tokens: 5060,
              cost_usd: 0.0379,
              ms: 1800,
              history_lines: 16,
              system_chars: systemChars,
              messages: 17,
              messages_chars: charsOf(first.messages),
            },
            {
              index: 1,
              model: MODEL,
              prompt_tokens: 7560,
              completion_tokens: 42,
              cache_read_tokens: 5060,
              cache_write_tokens: 0,
              cost_usd: 0.0096,
              ms: 2300,
              history_lines: 16,
              system_chars: systemChars,
              messages: 19,
              messages_chars: charsOf(second.messages),
            },
          ],
        },
      },
    ])
  })

  it('llm.cache_usage is still written, with the same properties as before', async () => {
    const h = harness({ history: longHistory(), script: TWO_CALLS })
    await flow(h)

    expect(events(h, 'llm.cache_usage')).toEqual([
      {
        user_id: USER_ID,
        event: 'llm.cache_usage',
        properties: {
          model: MODEL,
          stage: 'ganho_massa',
          prompt_tokens: 14981,
          cache_read_tokens: 5060,
          cache_creation_tokens: 5060,
          hit_rate: 0.338,
        },
      },
    ])
  })

  it('the event carries no text: not the patient message, not the answer, not the history, not the name', async () => {
    const h = harness({ history: longHistory(), script: TWO_CALLS })
    const output = await flow(h)

    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    const serialized = JSON.stringify(event)
    for (const text of [
      PHRASE,
      output.text,
      'QA A',
      ...longHistory().map((row) => String(row.content)),
      'taxa basal',
      'proteína',
    ]) {
      expect(serialized, text).not.toContain(text)
    }

    // Every leaf is a number or null, except these identifiers.
    const strings: string[] = []
    const walk = (value: unknown) => {
      if (typeof value === 'string') strings.push(value)
      else if (Array.isArray(value)) value.forEach(walk)
      else if (value && typeof value === 'object') Object.values(value).forEach(walk)
      else expect(value === null || typeof value === 'number').toBe(true)
    }
    walk(event)
    expect(strings.sort()).toEqual([USER_ID, 'llm.flow_calls', 'ganho_massa', MODEL, MODEL].sort())
  })

  it('a turn with no cache tokens still writes the per-call numbers (and no llm.cache_usage)', async () => {
    const h = harness({
      script: [
        { content: 'Resposta do modelo.', cacheRead: 0, cacheWrite: 0, costUsd: null, ms: 900 },
      ],
    })
    await flow(h)

    expect(events(h, 'llm.cache_usage')).toHaveLength(0)
    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(event?.properties).toMatchObject({
      call_count: 1,
      calls: [
        {
          index: 0,
          cache_read_tokens: 0,
          cache_write_tokens: 0,
          cost_usd: null,
          ms: 900,
          history_lines: 0,
          messages: 1,
          messages_chars: PHRASE.length,
        },
      ],
    })
  })

  it.each([
    'throw',
    'reject',
  ] as const)("a failing telemetry write (%s) on a turn that fails does not replace the turn's own error", async (how) => {
    const h = harness({ failEvent: { name: MOBILE_FLOW_CALLS_EVENT, how } })
    h.deps.llm.complete = async () => {
      throw new Error('provider unavailable')
    }

    await expect(flow(h)).rejects.toThrow(new Error('provider unavailable'))
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)).toHaveLength(0)
  })

  it('a turn that fails after writing its numbers does not write them a second time', async () => {
    // The cache event is written right after the per-call numbers; when that
    // write throws, the turn fails with the numbers already stored.
    const h = harness({
      history: longHistory(),
      failEvent: { name: 'llm.cache_usage', how: 'throw' },
    })

    await expect(flow(h)).rejects.toThrow(new Error('insert failed'))
    const written = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(written).toHaveLength(1)
    expect(written[0]?.properties).not.toHaveProperty('turn_failed')
  })

  it('a turn that fails writes its numbers once: the failed call, no text', async () => {
    const h = harness({ history: longHistory() })
    h.deps.llm.complete = async () => {
      vi.advanceTimersByTime(700)
      throw new Error('provider unavailable')
    }

    await expect(flow(h)).rejects.toThrow(new Error('provider unavailable'))
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)).toEqual([
      {
        user_id: USER_ID,
        event: 'llm.flow_calls',
        properties: {
          stage: 'ganho_massa',
          call_count: 1,
          tools_chars: expect.any(Number),
          calls: [
            {
              index: 0,
              model: MODEL,
              prompt_tokens: 0,
              completion_tokens: 0,
              cache_read_tokens: 0,
              cache_write_tokens: 0,
              cost_usd: null,
              ms: 700,
              history_lines: 16,
              system_chars: [`REGRAS COMPARTILHADAS${mobileFlowSystemPolicy}`.length, 2750],
              messages: 17,
              messages_chars: expect.any(Number),
              failed: 1,
            },
          ],
          turn_failed: 1,
        },
      },
    ])
    expect(JSON.stringify(events(h, MOBILE_FLOW_CALLS_EVENT))).not.toContain('provider unavailable')
  })

  it.each([
    'throw',
    'reject',
  ] as const)('a failing telemetry write (%s) never reaches the patient: the answer is returned', async (how) => {
    const h = harness({
      history: longHistory(),
      failEvent: { name: MOBILE_FLOW_CALLS_EVENT, how },
    })
    const output = await flow(h)

    expect(output.text).toBe('Resposta do modelo.')
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)).toHaveLength(0)
    expect(events(h, 'llm.cache_usage')).toHaveLength(1)
  })
})
