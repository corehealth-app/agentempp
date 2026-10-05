/**
 * WhatsApp REQUEST lock — audit 2026-10-04 (Flow cost and speed work).
 *
 * The Flow chat (iOS app) is being made cheaper and faster: a shorter history
 * window, a leaner per-turn context, per-call telemetry, and later fewer model
 * calls and Flow-only time limits. Every one of those changes lives in
 * packages/agent, the SAME code that serves the WhatsApp pipeline that is live
 * in production. audit-10-04-whatsapp-context-lock.test.ts pins only the
 * numeric section of the WhatsApp context; this file pins the WHOLE request.
 *
 * For two representative WhatsApp turns, run through the real entry point
 * (processMessage) against a fake database, it locks byte for byte:
 *   - every argument of every llm.complete call: model, both system blocks
 *     and their cache marks, the 20 tool schemas, every message, temperature,
 *     max tokens, cache flags, user id, metadata — and therefore also the
 *     ABSENCE of any new argument (a per-call timeout, a retry count…);
 *   - the output handed to the sender (text, interactive payload, tool calls,
 *     model, tokens, cost);
 *   - the ordered list of database calls (table, every chained method and its
 *     arguments, inserted rows) and of embedding calls.
 *
 * Turn A — an established patient (recomposição, 60 stored rows, day row with
 *   a pending close, 14-day window, patient summary, RAG chunks): a read tool,
 *   then a claimed registration with no tool (phantom-write retry), then the
 *   answer. Three model calls.
 * Turn B — a new patient in onboarding (no protocol, country not confirmed,
 *   no history, no day row): one model call, answered with onboarding buttons.
 *
 * The expected value is the committed fixture next to this file, generated
 * from commit 7062816 BEFORE any Flow performance change, plus the SHA-256 of
 * it pinned below. A leak of a Flow-only change into the request, the output
 * or the database calls of THESE TWO TURNS changes at least one byte and
 * fails here with a readable diff: the history window, the lean context, the
 * anti-repetition wording, the per-call telemetry, the time-limit arguments.
 *
 * It does not catch every leak. These two turns have no status question, no
 * run of tool iterations past the Flow's cap and no plan generator, so four
 * Flow-only changes can leak with this file still green (checked by
 * mutation): the iteration cap, the closing call with the tools switched
 * off, the plain-text status answer and the metered client handed to the
 * tools. Those are caught by the WhatsApp tests of
 * audit-10-04-flow-turn-calls.test.ts.
 *
 * Regenerating (only when WhatsApp is changed ON PURPOSE, with its own audit):
 *   UPDATE_WHATSAPP_REQUEST_LOCK=1 pnpm --filter @mpp/agent test whatsapp-request-lock
 * rewrites the fixture and prints the new hash; the test stays red until the
 * hash constant below is updated by hand. Two deliberate acts, never one.
 * The fixture is compared as parsed JSON, so its on-disk formatting is free.
 *
 * > RC LOCK — cenário turno de WhatsApp com foto/áudio, registro com botões, correção (replace), reavaliação, "bom dia" e modelos não-Anthropic (system em string única) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Estes dois turnos travam o caminho de texto; os demais continuam cobertos
 *   só pelos testes que já existiam.
 * > RC LOCK — cenário regras reais de produção (agent_rules) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O banco é falso: as regras são três linhas de exemplo, não as do Notion.
 */
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import type { PipelineDeps } from '../pipeline.js'
import { processMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'

const FIXTURE_PATH = fileURLToPath(
  new URL('./fixtures/audit-10-04-whatsapp-request-lock.json', import.meta.url),
)
/** SHA-256 of the captured value as canonical JSON (JSON.stringify, no spacing). */
const FIXTURE_SHA256 = '68ba7844b1919808b42a1aecffce2d2225aebaec52552889569f75feff244e3e'

const NOW = new Date('2026-10-04T15:03:40.503Z') // 12:03 in São Paulo, a Sunday
const USER_ID = '7d0c2a44-5b1e-4c57-9a3e-0f6b1c2d3e4f'
const TURN_ID = 'wamid.request-lock-turn'

type Row = Record<string, unknown>
type Json = string | number | boolean | null | Json[] | { [key: string]: Json }

interface ScriptedStep {
  content?: string
  toolCalls?: Array<{ id: string; name: string; arguments: string }>
  model?: string
}

interface Fixture {
  user: Row
  profile: Row
  day: Row | null
  progress: Row
  closedDays: Row[]
  /** Stored rows of the patient, any order; the current inbound row is added. */
  history: Row[]
  text: string
  from: string
  ragChunks: Array<{ page_title: string; content: string }>
  script: ScriptedStep[]
}

interface DbCall {
  target: string
  ops: Json[]
}

interface Captured {
  calls: Json[]
  output: Json
  db: DbCall[]
  embeddings: string[]
}

/** What JSON keeps of a value — the bytes a request would carry. */
const jsonOf = (value: unknown): Json => JSON.parse(JSON.stringify(value ?? null)) as Json

// Rules of the fake database. The persona introduction and the Markdown
// section are exactly what the Flow projection rewrites and removes
// (mobileFlowPromptContext): if that projection ever reached WhatsApp, the
// stable block below would change.
const AGENT_RULES: Row[] = [
  {
    topic: 'Persona',
    content:
      'Você é o Dr. Roberto Menescal, médico nutrólogo. Direto, próximo, sem firula.\n\n## Markdown — uso parcimonioso\n**Bold** apenas para números do card.\n\n## Decisões\nNunca ajuste meta/protocolo sem confirmar.',
    language: null,
  },
  {
    topic: 'Balanço',
    content: 'Os números vêm do sistema. Nunca recalcule meta, balanço ou bloco 7700 de cabeça.',
    language: 'pt-BR',
  },
  {
    topic: 'English tone',
    content: 'When the patient writes in English, answer in English.',
    language: 'en',
  },
]

async function run(fx: Fixture): Promise<Captured> {
  const calls: Json[] = []
  const db: DbCall[] = []
  const embeddings: string[] = []
  const messages: Row[] = [
    ...fx.history,
    {
      direction: 'in',
      content: fx.text,
      content_type: 'text',
      created_at: NOW.toISOString(),
      provider: 'whatsapp',
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
      case 'subscriptions':
        return { status: 'active', current_period_end: null, trial_ends_at: null }
      case 'users':
        return fx.user
      case 'user_profiles':
        if (read.columns.trim() === '*') return fx.profile
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), fx.profile[key.trim()] ?? null]),
        )
      case 'user_progress':
        return fx.progress
      case 'messages': {
        const rows = messages
          .filter((row) => read.filters.provider == null || row.provider === read.filters.provider)
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
          .map(({ provider: _provider, ...row }) => row)
        return read.limit == null ? rows : rows.slice(0, read.limit)
      }
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return fx.closedDays
        if (!fx.day || read.filters.date !== '2026-10-04') return null
        if (read.columns.trim() === '*') return fx.day
        const day = fx.day
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), day[key.trim()] ?? null]),
        )
      }
      case 'global_config':
        // No router flag row: the code default applies (as on a fresh database).
        if (read.filters.key === 'router.haiku_enabled') return null
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
          stage: read.filters.stage ?? null,
          model: 'anthropic/claude-sonnet-4.6',
          temperature: 0.2,
          max_tokens: 1200,
          max_tool_iterations: 5,
          system_prompt: 'VIEW_FALLBACK_MUST_NOT_BE_USED',
          allowed_tools: null,
        }
      case 'agent_rules':
        return AGENT_RULES
      default:
        // product_events (reads), pending_registrations, meal_logs, …: empty.
        return []
    }
  }

  const supabase = {
    from(table: string) {
      const call: DbCall = { target: table, ops: [] }
      db.push(call)
      const read: Read = { table, columns: '', filters: {}, limit: null }
      const result = () => ({ data: rowsFor(read), error: null })
      const one = async () => {
        const { data } = result()
        return { data: Array.isArray(data) ? (data[0] ?? null) : data, error: null }
      }
      const chain = Promise.resolve().then(result) as Promise<{ data: unknown; error: null }> &
        Record<string, unknown>
      const record = (method: string, args: unknown[]) => {
        call.ops.push([method, ...args.map(jsonOf)])
      }
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
        'insert',
      ]) {
        chain[method] = (...args: unknown[]) => {
          record(method, args)
          return chain
        }
      }
      chain.select = (...args: unknown[]) => {
        record('select', args)
        if (typeof args[0] === 'string') read.columns = args[0]
        return chain
      }
      chain.eq = (key: string, value: unknown) => {
        record('eq', [key, value])
        read.filters[key] = value
        return chain
      }
      chain.limit = (count: number) => {
        record('limit', [count])
        read.limit = count
        return chain
      }
      chain.single = () => {
        record('single', [])
        return one()
      }
      chain.maybeSingle = () => {
        record('maybeSingle', [])
        return one()
      }
      return chain
    },
    rpc: async (name: string, args: unknown) => {
      db.push({ target: `rpc:${name}`, ops: [jsonOf(args)] })
      return { data: name === 'match_method_chunks' ? fx.ragChunks : USER_ID, error: null }
    },
  } as unknown as PipelineDeps['supabase']

  let step = 0
  const llm = {
    complete: async (input: unknown) => {
      calls.push(jsonOf(input))
      const scripted = fx.script[Math.min(step, fx.script.length - 1)] ?? {}
      step += 1
      return {
        content: scripted.content ?? '',
        toolCalls: scripted.toolCalls ?? [],
        model: scripted.model ?? (input as { model: string }).model,
        promptTokens: 40_000 + step,
        completionTokens: 100 + step,
        totalTokens: 40_100 + 2 * step,
        cacheReadInputTokens: step === 1 ? 0 : 38_000,
        cacheCreationInputTokens: step === 1 ? 38_000 : 0,
        costUsd: 0.01 * step,
        finishReason: scripted.toolCalls?.length ? 'tool_calls' : 'stop',
        latencyMs: 0,
      }
    },
  } as unknown as PipelineDeps['llm']

  const embedder = {
    embed: async (text: string) => {
      embeddings.push(text)
      return [0.25, -0.5, 0.125]
    },
  } as unknown as NonNullable<PipelineDeps['embeddings']>

  const output = await processMessage(
    { supabase, llm, embeddings: embedder },
    {
      from: fx.from,
      providerMessageId: TURN_ID,
      text: fx.text,
      contentType: 'text',
      provider: 'whatsapp',
      timestamp: NOW,
    },
  )
  return { calls, output: jsonOf(output), db, embeddings }
}

// ── Turn A: an established patient ──────────────────────────────────────────

const wpp = (
  direction: 'in' | 'out',
  content: string,
  at: string,
  index: number,
  type = 'text',
): Row => ({
  direction,
  content,
  content_type: type,
  created_at: at,
  provider: 'whatsapp',
  provider_message_id: `wamid.request-lock-h${index}`,
})

const CARD_OUT =
  'Almoço registrado.\n\n🔥 Consumido: **1.240 / 1.650 kcal (75%)**\n🎯 Restam: **410 kcal**\n💪 Proteína: **96 / 130g (74%)**\n📊 Bloco 7700: **3.120 / 7.700 kcal (41%)**'
const SHORT_OUT = 'Boa. Como foi o treino de hoje?'
const INS = [
  'Almocei arroz, feijão e frango grelhado',
  'Fiz 40 min de musculação',
  'Quanto falta de proteína hoje?',
  'Jantei omelete de 3 ovos com queijo',
  'Bom dia',
  'Como foi minha semana?',
]

/**
 * 59 stored rows before the current one: 40 on the two previous local days,
 * 19 today. One inbound is a photo, one is a raw button tap (never sent to the
 * model). With the current inbound the table holds 60 rows; the pipeline reads
 * the newest 50.
 */
function establishedHistory(): Row[] {
  const rows: Row[] = []
  for (let index = 0; index < 59; index += 1) {
    const previousDay = index < 40
    const at = previousDay
      ? new Date(Date.parse('2026-10-02T13:00:00.000Z') + index * 47 * 60_000).toISOString()
      : new Date(NOW.getTime() - (59 - index) * 4 * 60_000).toISOString()
    const inbound = index % 2 === 0
    const pair = Math.floor(index / 2)
    if (index === 44) {
      rows.push(
        wpp('in', '[Foto] Prato com arroz, feijão, bife e salada de alface', at, index, 'image'),
      )
    } else if (index === 50) {
      rows.push(wpp('in', 'confirm_123e4567-e89b-42d3-a456-426614174000', at, index, 'interactive'))
    } else if (inbound) {
      rows.push(wpp('in', INS[pair % INS.length] as string, at, index))
    } else {
      rows.push(wpp('out', pair % 3 === 0 ? CARD_OUT : SHORT_OUT, at, index))
    }
  }
  return rows
}

const TURN_A: Fixture = {
  from: '5511988887777',
  text: 'Almocei 150g de arroz, 100g de feijão e 120g de frango grelhado',
  user: {
    id: USER_ID,
    name: 'Luciana',
    summary:
      'Paciente em recomposição desde agosto. Treina musculação 4x por semana. Costuma pular o lanche da tarde.',
    last_active_at: NOW.toISOString(),
    country: 'BR',
    country_confirmed: true,
    country_detected_from_wpp: 'BR',
    locale: 'pt-BR',
    // No timezone_confirmed: Brazil has several time zones, so the context
    // carries the "ask city and state" instruction.
    metadata: null,
    timezone: 'America/Sao_Paulo',
  },
  profile: {
    sex: 'feminino',
    birth_date: '1988-03-12',
    height_cm: 165,
    weight_kg: 78.4,
    body_fat_percent: 34,
    activity_level: 'leve',
    training_frequency: 4,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    current_protocol: 'recomposicao',
    goal_type: 'bf_percent',
    goal_value: 28,
    deficit_level: 500,
    bedtime: '23:00',
    wake_time: '06:30',
    food_organization: 'sim',
  },
  day: {
    date: '2026-10-04',
    calories_target: 1650,
    protein_target: '130.00',
    calories_consumed: 420,
    protein_g: '31.50',
    carbs_g: '48.20',
    fat_g: '11.10',
    exercise_calories: 280,
    daily_balance: -1510,
    deficit_accumulated: 3120,
    day_status: 'pending_close',
    day_closed: false,
    gap_reminder_sent_at: '2026-10-04T14:00:00.000Z',
  },
  progress: {
    current_streak: 6,
    longest_streak: 11,
    xp_total: 840,
    level: 3,
    blocks_completed: 1,
    deficit_block: 3120,
    last_active_date: '2026-10-03',
  },
  closedDays: Array.from({ length: 6 }, (_, index) => ({
    calories_consumed: 1500 + index * 60,
    calories_target: 1650,
    day_closed: true,
  })),
  history: establishedHistory(),
  ragChunks: [
    {
      page_title: 'Bloco 7700',
      content:
        'O bloco só credita no fechamento do dia. Exercício acelera o bloco, não libera comida.',
    },
    { page_title: 'Proteína', content: 'Distribua a proteína ao longo das refeições do dia.' },
  ],
  script: [
    {
      toolCalls: [{ id: 'toolu_request_lock_01', name: 'consulta_metricas', arguments: '{}' }],
    },
    {
      content:
        'Almoço registrado! ✅\n\n- Arroz 150g\n- Feijão 100g\n- Frango grelhado 120g\n\nTotal refeição: 520 kcal',
    },
    { content: 'Pra eu anotar certinho: o frango era grelhado sem óleo?' },
  ],
}

// ── Turn B: a new patient in onboarding ─────────────────────────────────────

const TURN_B: Fixture = {
  from: '14155550123',
  text: 'Oi, quero começar',
  user: {
    id: USER_ID,
    name: null,
    summary: null,
    last_active_at: null,
    country: 'US',
    country_confirmed: false,
    country_detected_from_wpp: 'US',
    locale: null,
    metadata: null,
    timezone: 'America/New_York',
  },
  profile: {
    sex: null,
    birth_date: null,
    height_cm: null,
    weight_kg: null,
    body_fat_percent: null,
    activity_level: null,
    training_frequency: null,
    water_intake: null,
    hunger_level: null,
    current_protocol: null,
    goal_type: null,
    goal_value: null,
    deficit_level: null,
  },
  day: null,
  progress: {
    current_streak: 0,
    longest_streak: 0,
    xp_total: 0,
    level: 1,
    blocks_completed: 0,
    deficit_block: 0,
    last_active_date: null,
  },
  closedDays: [],
  history: [],
  ragChunks: [],
  script: [
    {
      content:
        'Bem-vindo! Pra começar, qual é o seu sexo?\n\n[BTN:sex:Masculino=masculino|Feminino=feminino]',
    },
  ],
}

/**
 * The locked value. The tool schemas are the same in every call; they are
 * kept once and each call points to them, so the fixture stays readable.
 */
function locked(turns: Record<string, Captured>): Json {
  const firstCall = Object.values(turns)[0]?.calls[0] as { tools?: Json } | undefined
  const tools = firstCall?.tools ?? null
  const sameTools = JSON.stringify(tools)
  return {
    tools,
    turns: Object.fromEntries(
      Object.entries(turns).map(([name, turn]) => [
        name,
        {
          calls: turn.calls.map((call) => {
            const { tools: callTools, ...rest } = call as { [key: string]: Json }
            return JSON.stringify(callTools ?? null) === sameTools
              ? { ...rest, tools: '<same as the top-level tools>' }
              : { ...rest, tools: callTools ?? null }
          }),
          output: turn.output,
          db: turn.db as unknown as Json,
          embeddings: turn.embeddings,
        },
      ]),
    ),
  }
}

async function capture(): Promise<Record<string, Captured>> {
  const reset = () => {
    clearCalcConfigCache()
    resetRouterFlagCacheForTests()
  }
  reset()
  const a = await run(TURN_A)
  reset()
  const b = await run(TURN_B)
  return { A_established_patient: a, B_onboarding: b }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  // Production reads the subscription gate; the lock includes that read.
  vi.stubEnv('NODE_ENV', 'production')
  vi.stubEnv('SUBSCRIPTION_GATE', 'on')
})
afterEach(() => {
  vi.unstubAllEnvs()
  vi.useRealTimers()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})

describe('audit 2026-10-04 — WhatsApp request lock (system blocks, tools, messages, params, output, database order)', () => {
  it('two representative WhatsApp turns produce, byte for byte, the requests of the committed fixture', async () => {
    const actual = locked(await capture())
    const canonical = JSON.stringify(actual)
    const sha256 = createHash('sha256').update(canonical).digest('hex')

    if (process.env.UPDATE_WHATSAPP_REQUEST_LOCK === '1') {
      mkdirSync(dirname(FIXTURE_PATH), { recursive: true })
      writeFileSync(FIXTURE_PATH, `${JSON.stringify(actual, null, 2)}\n`)
      // eslint-disable-next-line no-console
      console.log(`[whatsapp-request-lock] fixture rewritten; FIXTURE_SHA256 = '${sha256}'`)
    }

    expect(existsSync(FIXTURE_PATH), 'the committed fixture is missing').toBe(true)
    const expected = JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) as Json
    // Readable diff first; the hash then pins the fixture itself.
    expect(actual).toEqual(expected)
    expect(
      sha256,
      'same values as the fixture but other bytes (key order), or the fixture was edited by hand',
    ).toBe(FIXTURE_SHA256)
  })

  it('the locked turns are the ones described: 3 calls with a tool and a guard retry, 1 call with buttons', async () => {
    const turns = await capture()
    const a = turns.A_established_patient as Captured
    const b = turns.B_onboarding as Captured

    type Call = {
      model: string
      systemPrompt: Array<{ text: string; cache?: string }>
      tools: Array<{ function: { name: string } }>
      messages: Array<{ role: string; content: string }>
    }
    const callsA = a.calls as unknown as Call[]
    const callsB = b.calls as unknown as Call[]
    expect(callsA).toHaveLength(3)
    expect(callsB).toHaveLength(1)

    // WhatsApp keeps its window: 50 rows read, minus the current inbound and
    // the raw button tap = 48 history lines, then the current message.
    const first = callsA[0] as Call
    expect(first.messages).toHaveLength(49)
    expect(first.messages.at(-1)).toEqual({ role: 'user', content: TURN_A.text })
    // No Flow date prefix on WhatsApp history, previous day or not.
    expect(first.messages.some((m) => m.content.startsWith('[Mensagem de'))).toBe(false)
    expect(first.tools).toHaveLength(20)

    // Both system blocks, the first one cached for 1 h, persona untouched.
    expect(first.systemPrompt).toHaveLength(2)
    expect(first.systemPrompt[0]?.cache).toBe('ephemeral_1h')
    expect(first.systemPrompt[0]?.text).toContain('Você é o Dr. Roberto Menescal')
    expect(first.systemPrompt[0]?.text).toContain('## Markdown — uso parcimonioso')
    const variable = first.systemPrompt[1]?.text ?? ''
    // Every block the Flow context drops is still here for WhatsApp.
    for (const marker of [
      '## Método relevante (recuperado da base — siga estas regras)',
      '### Resumo do paciente',
      'chame `confirma_pais_residencia` de novo com o `language` atualizado',
      'Pergunte cidade e estado/região de residência e chame `confirma_pais_residencia`',
      '### Hora local do paciente AGORA (use pra meal_type — NÃO adivinhe pelos alimentos)',
      '- 11h–14h59 → `almoco`',
      '❌ NÃO use `replace=true` em foto NOVA',
      '- Balanço calórico de hoje: -1510 kcal (negativo=déficit, positivo=superávit)',
      '1. NUNCA invente o conteúdo de uma foto.',
      '4. Se usuário pedir "pausar / férias / parar uns dias", chame a tool pausar_agente.',
      '5. Foto e legenda no mesmo turno descrevem a MESMA refeição.',
      '## Anti-repetição (CRÍTICO)\nSuas últimas respostas foram:\n[1] "',
    ]) {
      expect(variable, marker).toContain(marker)
    }

    // Call 2 carries the tool exchange; call 3 the WhatsApp phantom-write retry.
    const second = callsA[1] as Call
    expect(second.messages).toHaveLength(51)
    expect(second.messages.at(-1)?.role).toBe('tool')
    const third = callsA[2] as Call
    expect(third.messages).toHaveLength(53)
    expect(third.messages.at(-1)?.content).toMatch(
      /^SISTEMA \(não é o paciente\): você afirmou ter registrado a refeição\/treino MAS não chamou a tool/,
    )
    expect((a.output as { text: string }).text).toBe(
      'Pra eu anotar certinho: o frango era grelhado sem óleo?',
    )

    // Turn B: country not confirmed, onboarding buttons instead of text.
    const onboarding = callsB[0] as Call
    expect(onboarding.messages).toEqual([{ role: 'user', content: TURN_B.text }])
    expect(onboarding.systemPrompt[1]?.text).toContain('### País de residência (NÃO confirmado)')
    expect(onboarding.systemPrompt[1]?.text).not.toContain('## Anti-repetição')
    expect(b.output).toMatchObject({
      text: '',
      interactive: {
        body: 'Bem-vindo! Pra começar, qual é o seu sexo?',
        buttons: [{ title: 'Masculino' }, { title: 'Feminino' }],
      },
    })

    // No Flow telemetry and no Flow tool on this channel.
    const inserted = [...a.db, ...b.db].flatMap((call) =>
      call.ops
        .filter((op): op is Json[] => Array.isArray(op) && op[0] === 'insert')
        .map((op) => String((op[1] as { event?: unknown } | null)?.event ?? call.target)),
    )
    expect(inserted.filter((name) => name.startsWith('llm.flow'))).toEqual([])
    expect(first.tools.map((tool) => tool.function.name)).not.toContain('propoe_plano_dieta')
  })

  it('the capture is deterministic: two runs give the same bytes', async () => {
    const one = JSON.stringify(locked(await capture()))
    const two = JSON.stringify(locked(await capture()))
    expect(two).toBe(one)
  })
})
