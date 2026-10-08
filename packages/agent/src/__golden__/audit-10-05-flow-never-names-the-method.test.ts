/**
 * Audit 2026-10-05 — the Flow (app Performe AI) never names the method.
 *
 * The finding (read-only map of 2026-10-05, inventory.json, items
 * pipeline.ts:559 and :576-583): the app's public name is Performe AI and its
 * assistant is Flow, but the Flow's policy only said "MPP é uma referência
 * interna: não o apresente ESPONTANEAMENTE como método, marca, identidade ou
 * credencial", the rules loaded from the database and the manual excerpts
 * retrieved for the turn reach the model with "MPP" and "Muscular Power
 * Plant" in their text, and the model's answer was not filtered. A person who
 * ASKS for the method could be told its name and the physician's.
 *
 * Fix, Flow channel only (processAuthenticatedMessage):
 *  1. the instruction is absolute (mobileFlowSystemPolicy): never write
 *     "MPP", "Muscular Power Plant", the author's name or "método do Dr. …",
 *     not even when asked; asked which method or who is behind it, the
 *     guidance follows the Performe AI programme;
 *  2. a deterministic last line of defence on the text the app receives
 *     (flow-public-names.ts, applied in processAuthenticatedMessage to every
 *     way a turn can end), and the turn writes
 *     `llm.flow_internal_name_replaced` with counts only.
 *
 * The adversarial review of this change (2026-10-05, verdict NOT_YET) ran the
 * first filter and found it renaming the PERSON: "Bom treino, Dr. Roberto!"
 * came out as "Bom treino, Flow!", "Fale com seu médico, o Dr. Roberto
 * Silva." as "o Performe AI Silva.", "Dra. Roberta Menescal" as "Dra. Roberta
 * Performe AI", and a URL as "https://example.com/Performe AI/guia". The
 * filter is now a CLOSED VOCABULARY with structural guards and no reading of
 * the wording around a name (RC FN-4 lists it, word for word):
 *  - the method's spellings become "Performe AI", never inside a URL, a path
 *    or an identifier;
 *  - the physician's name is replaced ONLY when the surname is present
 *    ("Flow" right after a closed list of self-introduction leads, "Performe
 *    AI" anywhere else); "Dr. Roberto" without the surname is never replaced
 *    (RC FN-7), nor is another person who carries the surname;
 *  - an account whose registered name contains "Menescal" keeps the
 *    physician's name untouched for the turn (the name is the one the Flow
 *    context already loads: no extra query);
 *  - the "signature" rules (after the last comma, alone on the last line) are
 *    gone.
 * Section 5 runs every sentence of that decision, exactly as written, through
 * the real entry point.
 *
 * An answer with none of those names is the very string the model wrote and
 * writes no event. The legacy WhatsApp entry (processMessage) is untouched:
 * its two locks (audit-10-04-whatsapp-request-lock, -context-lock) stay green
 * and unedited, and section 7 pins that it still delivers the names.
 *
 * The three questions are the exact ones of the task of 2026-10-05. Every
 * pipeline test runs the REAL entry point with a fake database and a scripted
 * model; the shared rules are the persona line of
 * supabase/migrations/20260502130000_persona_amigo_coach.sql:48.
 *
 * > RC FN-1 — cenário resposta do MODELO REAL às três perguntas ("Qual é o método que vocês usam?", "Isso é o MPP?", "Quem é o Dr. Roberto?") NÃO coberto nesta PR (pendência da audit 2026-10-05). O modelo é roteirizado: o golden prova que a instrução absoluta vai no pedido e o que o filtro troca e não troca quando um nome escapa, não que o modelo real obedece nem como ele redige a resposta. Em staging, `llm.flow_internal_name_replaced` conta quantas vezes o filtro agiu (`method_names`, `persona_self`, `persona_other`) e quantas vezes viu título + primeiro nome sem o sobrenome e não trocou (`persona_first_name_only`).
 * > RC FN-2 — cenário frase SOBRE o médico em terceira pessoa NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro troca nomes, não afirmações nem a redação em volta: "O Dr. Roberto Menescal é o médico que criou o método." chega como "O Performe AI é o médico que criou o método." e "Método MPP (Muscular Power Plant)" chega como "Método Performe AI (Performe AI)". Sem os nomes, mas a frase fica estranha e continua dizendo que há um médico por trás. Travado como pendência no golden.
 * > RC FN-3 — cenário nome dentro do RASCUNHO gravado de uma sugestão de plano (o que a tela "Revisar sugestão" mostra) NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro cobre o texto da sugestão que vai para o chat; o rascunho é gravado como o gerador escreveu. O prompt dos geradores no app já proíbe citar método e profissional. Travado como pendência no golden (treino com a regra de progressão citando o método).
 * > RC FN-4 — cenário nome FORA do vocabulário fechado do filtro NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro troca só estas grafias. Do método, por "Performe AI": "MPP" e "MPPs" em qualquer caixa; as formas em maiúsculas "M.P.P.", "M. P. P." e "M P P"; "Muscular Power Plant" em qualquer caixa, com espaço, espaço não separável, hífen ou nada entre as palavras. Do médico, só com o sobrenome: título opcional (Dr., Dr, Dra., Doutor, Doctor) + primeiro nome opcional (Roberto, Robert) + "Menescal", por "Flow" logo depois de "sou o", "sou", "aqui é o", "aqui é", "me chamo", "meu nome é", "I am", "I'm" ou "this is", e por "Performe AI" no resto. Passam sem troca, de propósito: a grafia colada a / . @ - _ ou a letra ou número, que é trecho de endereço, caminho ou identificador ("https://example.com/mpp/guia", "https://mpp.example.com/guia", "docs/CALCULO-MPP.md", "MPP-2", "@mpp/agent", "mppx", "agentempp", "mpp_mensal_v1", e também "MPP/Muscular Power Plant" e "__MPP__"); outra pessoa com o sobrenome, isto é, "Menescal" logo depois de uma palavra capitalizada que não seja Roberto/Robert ("Dra. Roberta Menescal", "Ana Menescal", e também "Segundo Menescal, …" no começo de frase); e todo o nome do médico quando o nome cadastrado da conta contém "Menescal", sem diferença de maiúscula ou acento (a pessoa pode ser ele; os nomes do método continuam trocados). Passam sem troca por estarem fora da lista: "Menescau", "Dr. Róberto", "m.p.p.", "M P Pereira", "Método do Dr. Fulano"; e a apresentação com outra abertura ("Soy el Dr. Roberto Menescal." vira "Soy el Performe AI.", não "Soy el Flow."). Limites conhecidos, sem correção nesta PR: na consulta ou na âncora de um endereço, e em caminho com barra invertida, a sigla ainda é trocada e o link chega quebrado ("https://example.com/guia?ref=mpp" vira "https://example.com/guia?ref=Performe AI", "https://example.com/guia#mpp" vira "https://example.com/guia#Performe AI", "utm_source=mpp" vira "utm_source=Performe AI"); a sigla seguida de ponto e letra, sem espaço, passa ("É o MPP.Sim"); depois de "não", "nao", "nem", "nunca" ou "jamais" a abertura não conta como apresentação ("Não sou o Dr. Roberto Menescal." vira "Não sou o Performe AI."); o nome do médico colado a / - _ passa inteiro ("Dr. Roberto Menescal/CRM 123", "_Dr. Roberto Menescal_"); e "Menescal" sem uma palavra capitalizada logo antes é trocado mesmo sendo outra pessoa ("Sra. Menescal" vira "Sra. Performe AI"), enquanto qualquer palavra capitalizada logo antes o preserva ("Professor Menescal"). Travado no golden e em `packages/agent/src/flow-public-names.test.ts`.
 * > RC FN-5 — cenário contexto ENVIADO ao modelo sem "MPP" NÃO coberto nesta PR (pendência da audit 2026-10-05). As regras do banco e os trechos do manual continuam chegando ao Flow com "MPP" e "Muscular Power Plant" no corpo (só a apresentação e o nome do médico já eram trocados). Reescrever essas regras é conteúdo clínico no banco e fica para decisão do dono.
 * > RC FN-6 — cenário respostas JÁ gravadas no histórico antes desta mudança NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro age na resposta do turno; uma linha antiga com o nome continua como foi gravada e o app a mostra ao abrir a conversa. Nenhum banco foi lido para saber se existe alguma.
 * > RC FN-7 — cenário "Flow escreve 'Dr. Roberto' sem o sobrenome" variante NÃO coberta pelo filtro nesta PR (fica só a instrução ao modelo; pendência da audit 2026-10-05). Título e/ou primeiro nome sem "Menescal" ("Dr. Roberto", "Doutor Roberto", "Roberto") nunca são trocados, porque podem ser o nome de quem usa o app ou de outra pessoa: "Bom treino, Dr. Roberto!" e "Fale com seu médico, o Dr. Roberto Silva." chegam como o modelo escreveu. Por isso "O Dr. Roberto é o médico que criou o método." (uma resposta possível a "Quem é o Dr. Roberto?") também chega inteira, com o título e o primeiro nome do médico. O turno só conta a ocorrência de título + primeiro nome em `persona_first_name_only`, sem texto. Travado como pendência no golden.
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import { projectFlowPublicNames } from '../flow-public-names.js'
import type { PipelineDeps } from '../pipeline.js'
import {
  MOBILE_FLOW_PUBLIC_NAMES_EVENT,
  mobileFlowSystemPolicy,
  processAuthenticatedMessage,
  processMessage,
} from '../pipeline.js'
import { trainingSuggestionText } from '../plan-suggestion-text.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'

// ── The report ──────────────────────────────────────────────────────────────
/** The three exact questions. */
const ASKS_METHOD = 'Qual é o método que vocês usam?'
const ASKS_ACRONYM = 'Isso é o MPP?'
const ASKS_PHYSICIAN = 'Quem é o Dr. Roberto?'

/** What the Flow is told to say: the wording of the instruction itself. */
const COMPLIANT_ANSWER = 'As orientações seguem o programa do Performe AI.'

/** The closed vocabulary: no spelling of it reaches the app in a plain sentence. */
const FORBIDDEN = /MPP|Muscular[\s-]*Power[\s-]*Plant|Menescal/i
/** RC FN-7 (pendency): the title + first name, which the filter does not replace. */
const TITLE_AND_FIRST_NAME = /(?:Dra?\.?|Doutor|Doctor)\s*Robert/i

/** The properties of `llm.flow_internal_name_replaced` when nothing was seen. */
const NO_NAMES = {
  method_names: 0,
  persona_self: 0,
  persona_other: 0,
  persona_first_name_only: 0,
}

/** An account whose registered name carries the physician's surname. */
const MENESCAL_ACCOUNT_NAME = 'Roberto Menescal'

/** The persona line of the shared rules (migration 20260502130000, line 48). */
const SHARED_RULES = `## Persona master

Você é o **Dr. Roberto Menescal**, nutricionista experiente que conduz o **Método MPP (Muscular Power Plant)** via WhatsApp. Você fala em **primeira pessoa**, com calor humano, como um amigo coach que entende fisiologia e respeita o tempo do paciente.

## Regras internas
MPP: cálculos oficiais permanecem no servidor.`

/** A manual excerpt as the retrieval returns it. */
const METHOD_CHUNK = {
  page_title: 'Método MPP — visão geral',
  content: 'O Método MPP (Muscular Power Plant) organiza a alimentação em blocos de 7700 kcal.',
}

const NOW = new Date('2026-10-05T15:00:00.000Z') // 12:00 in São Paulo
const USER_ID = 'qa-a'
const TURN_ID = 'mobile_flow/qa-a/never-names-the-method'
const MODEL = 'anthropic/claude-sonnet-4.6'
const GENERATOR_MODEL = 'anthropic/claude-sonnet-4.5'

type Row = Record<string, unknown>

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

const DAY: Row = {
  date: '2026-10-05',
  calories_target: 2980,
  protein_target: '144.00',
  calories_consumed: 541,
  protein_g: '59.03',
  carbs_g: '47.32',
  fat_g: '10.27',
  exercise_calories: 0,
  water_consumed_ml: 500,
  daily_balance: -2439,
  deficit_accumulated: 0,
  day_status: null,
  day_closed: false,
  gap_reminder_sent_at: null,
}

const PROGRESS: Row = {
  current_streak: 3,
  longest_streak: 5,
  xp_total: 1240,
  level: 2,
  blocks_completed: 0,
  deficit_block: 0,
  last_active_date: null,
}

/** The device workout turn of 09-30 (audit-10-04-flow-turn-calls): phrase and arguments. */
const WORKOUT_PHRASE = 'Pode ser equilibrado no geral.'
const WORKOUT_ARGS = {
  available_equipment: ['equipamentos completos de academia'],
  location: 'academia_completa',
  days_per_week: 3,
  training_level: 'iniciante',
}
const exercise = (name: string, muscle_group: string) => ({
  name,
  muscle_group,
  sets: 3,
  reps_range: '12-15',
  rpe_target: '7-8',
  rest_seconds: 90,
})
const workoutDay = (day: string, focus: string) => ({
  day,
  focus,
  duration_min: 60,
  exercises: [
    exercise('Agachamento livre', 'quadríceps/glúteos'),
    exercise('Supino reto com barra', 'peitoral'),
    exercise('Puxada frontal', 'dorsal'),
    exercise('Desenvolvimento com halteres', 'ombros'),
  ],
})
/** A generator that ignored its own prompt and cited the method and its author. */
const WORKOUT_OUTPUT_WITH_NAMES = JSON.stringify({
  plan_type: 'full_body',
  weekly_schedule: [
    workoutDay('Segunda-feira', 'Full Body A'),
    workoutDay('Quarta-feira', 'Full Body B'),
    workoutDay('Sexta-feira', 'Full Body C'),
  ],
  progression_rule:
    'Progressão em escada do Método MPP (Muscular Power Plant), como o Dr. Roberto Menescal recomenda: aumente a carga ao completar o ciclo.',
})

// ── Harness (the one of audit-10-04-flow-turn-calls, without the clock) ─────
interface Fixture {
  channel?: 'flow' | 'whatsapp'
  /** What the model answers, call after call (the last one repeats). */
  chat: Array<{
    content?: string
    toolCalls?: Array<{ id: string; name: string; arguments: string }>
  }>
  generator?: string
  user?: Row
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Row }>
  rpcs: Array<{ name: string; params: Row }>
  /** The system prompt of each chat call, flattened to text. */
  systemPrompts: string[]
  chatCalls: number
  /** Every table read or written, in order (one entry per `from`). */
  tables: string[]
}

function flatten(value: unknown): string {
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

function harness(fixture: Fixture): Harness {
  const provider = fixture.channel === 'whatsapp' ? 'whatsapp' : 'mobile_flow'
  const inserts: Harness['inserts'] = []
  const rpcs: Harness['rpcs'] = []
  const state: Harness = {
    deps: {} as PipelineDeps,
    inserts,
    rpcs,
    systemPrompts: [],
    chatCalls: 0,
    tables: [],
  }
  const turnRow: Row = {
    id: 'message-turn-0001',
    direction: 'in',
    content: '',
    content_type: 'text',
    created_at: NOW.toISOString(),
    provider,
    provider_message_id: TURN_ID,
  }

  interface Read {
    table: string
    columns: string
    filters: Row
    within: Record<string, unknown[]>
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
      case 'messages':
        if (read.filters.provider != null && read.filters.provider !== provider) return []
        return [turnRow]
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return []
        if (read.filters.date !== '2026-10-05') return null
        if (read.columns.trim() === '*') return DAY
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), DAY[key.trim()] ?? null]),
        )
      }
      case 'plan_drafts':
        return typeof read.filters.request_key === 'string' ? null : []
      case 'global_config':
        if (read.filters.key === 'router.haiku_enabled') return { value: false }
        return []
      case 'v_active_prompts':
        return {
          stage: read.filters.stage ?? 'ganho_massa',
          model: MODEL,
          temperature: 0.2,
          max_tokens: 1200,
          max_tool_iterations: 2,
          system_prompt: SHARED_RULES,
          allowed_tools: null,
        }
      default:
        return []
    }
  }

  const supabase = {
    from(table: string) {
      state.tables.push(table)
      const read: Read = { table, columns: '', filters: {}, within: {}, limit: null }
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
      chain.in = (key: string, values: unknown[]) => {
        read.within[key] = values
        return chain
      }
      chain.limit = (count: number) => {
        read.limit = count
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
    rpc: async (name: string, params: Row = {}) => {
      rpcs.push({ name, params })
      if (name === 'create_plan_draft_atomic') {
        return { data: { id: 'draft-0001', status: params.p_status, inserted: true }, error: null }
      }
      return { data: name === 'match_method_chunks' ? [METHOD_CHUNK] : USER_ID, error: null }
    },
  } as unknown as PipelineDeps['supabase']

  const llm = {
    complete: async (input: { systemPrompt?: unknown; metadata?: Record<string, string> }) => {
      const stage = input.metadata?.Stage
      if (stage === 'diet-generator' || stage === 'training-generator') {
        return {
          content: fixture.generator ?? '',
          toolCalls: [],
          model: GENERATOR_MODEL,
          finishReason: 'stop',
          promptTokens: 900,
          completionTokens: 2600,
          costUsd: 0.0417,
        }
      }
      const step = fixture.chat[Math.min(state.chatCalls, fixture.chat.length - 1)] ?? {}
      state.chatCalls += 1
      state.systemPrompts.push(flatten(input.systemPrompt))
      return {
        content: step.content ?? '',
        toolCalls: step.toolCalls ?? [],
        model: MODEL,
        finishReason: 'stop',
        promptTokens: 7400,
        completionTokens: 60,
        cacheReadInputTokens: 0,
        cacheCreationInputTokens: 0,
        costUsd: 0.0098,
      }
    },
  } as unknown as PipelineDeps['llm']

  // The retrieval is on: the manual excerpt reaches the turn as on staging.
  const embeddings = { embed: async () => [0.1, 0.2] } as unknown as PipelineDeps['embeddings']
  state.deps = { supabase, llm, embeddings }
  return state
}

function flow(h: Harness, text: string) {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: TURN_ID,
    text,
    timestamp: NOW,
  })
}

function whatsapp(h: Harness, text: string) {
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

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

// ── 1. The instruction is absolute ──────────────────────────────────────────
describe('audit 2026-10-05 Flow names — the instruction the model receives', () => {
  it('says never, not even when asked, and what to say instead', async () => {
    const h = harness({ chat: [{ content: COMPLIANT_ANSWER }] })
    await flow(h, ASKS_METHOD)

    expect(h.systemPrompts).toHaveLength(1)
    const prompt = h.systemPrompts[0] ?? ''
    expect(prompt).toContain(mobileFlowSystemPolicy)
    expect(prompt).toContain(
      'Nunca escreva "MPP", "Muscular Power Plant", o nome de quem criou o método\nnem "método do Dr." seguido de nome, nem quando a pessoa perguntar: são\nreferências internas. Se perguntarem qual é o método ou quem está por trás\ndele, diga só que as orientações seguem o programa do Performe AI.',
    )
    // The line of HEAD, which let the name out on request, is gone.
    expect(prompt).not.toContain('espontaneamente')
    expect(prompt).not.toContain('MPP é uma referência interna')
    // The physician is not named to the model, as before.
    expect(prompt).not.toMatch(/Menescal|Dr\.?\s+Robert/i)
  })

  it('RC FN-5 (pendency): the rules and the manual excerpt still reach the model with the acronym', async () => {
    const h = harness({ chat: [{ content: COMPLIANT_ANSWER }] })
    await flow(h, ASKS_METHOD)

    const prompt = h.systemPrompts[0] ?? ''
    expect(prompt).toContain('MPP: cálculos oficiais permanecem no servidor.')
    // C3 projects the block-only body for gain; the raw RAG remains unchanged.
    expect(prompt).toContain(`### ${METHOD_CHUNK.page_title}\n[referência interna omitida]`)
    expect(prompt).not.toContain(METHOD_CHUNK.content)
    expect(METHOD_CHUNK.content).toBe('O Método MPP (Muscular Power Plant) organiza a alimentação em blocos de 7700 kcal.')
  })
})

// ── 2. The three questions ──────────────────────────────────────────────────
describe('audit 2026-10-05 Flow names — the three questions, with a model that names everything', () => {
  it.each([
    {
      question: ASKS_METHOD,
      leaked:
        'Usamos o Método MPP (Muscular Power Plant), criado pelo Dr. Roberto Menescal. Ele organiza sua alimentação e seus treinos.',
      // RC FN-2 (pendency): each name is replaced where it stands.
      delivered:
        'Usamos o Método Performe AI (Performe AI), criado pelo Performe AI. Ele organiza sua alimentação e seus treinos.',
      counts: { ...NO_NAMES, method_names: 2, persona_other: 1 },
    },
    {
      question: ASKS_ACRONYM,
      leaked: 'Sim, isso é o MPP: o método por trás das suas metas.',
      delivered: 'Sim, isso é o Performe AI: o método por trás das suas metas.',
      counts: { ...NO_NAMES, method_names: 1 },
    },
    {
      question: ASKS_PHYSICIAN,
      // RC FN-2 (pendency): the name goes, the claim about a physician stays.
      leaked: 'O Dr. Roberto Menescal é o médico que criou o método.',
      delivered: 'O Performe AI é o médico que criou o método.',
      counts: { ...NO_NAMES, persona_other: 1 },
    },
  ])('"$question": no name of the closed vocabulary reaches the app', async ({
    question,
    leaked,
    delivered,
    counts,
  }) => {
    const h = harness({ chat: [{ content: leaked }] })
    const output = await flow(h, question)

    expect(h.chatCalls).toBe(1)
    expect(output.text).not.toMatch(FORBIDDEN)
    expect(output.text).not.toMatch(TITLE_AND_FIRST_NAME)
    expect(output.text).toBe(delivered)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toEqual([
      {
        user_id: USER_ID,
        event: 'llm.flow_internal_name_replaced',
        properties: { stage: 'ganho_massa', ...counts },
      },
    ])
  })

  it(`RC FN-7 (pendency): "${ASKS_PHYSICIAN}" answered with "Dr. Roberto" and no surname is delivered as written, and counted`, async () => {
    const leaked = 'O Dr. Roberto é o médico que criou o método.'
    const h = harness({ chat: [{ content: leaked }] })
    const output = await flow(h, ASKS_PHYSICIAN)

    // The filter does not cover this variant: only the instruction does.
    expect(output.text).toBe(leaked)
    expect(output.text).toMatch(TITLE_AND_FIRST_NAME)
    expect(output.text).not.toMatch(FORBIDDEN)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toEqual([
      {
        user_id: USER_ID,
        event: 'llm.flow_internal_name_replaced',
        properties: { stage: 'ganho_massa', ...NO_NAMES, persona_first_name_only: 1 },
      },
    ])
  })

  it.each([
    ASKS_METHOD,
    ASKS_ACRONYM,
    ASKS_PHYSICIAN,
  ])('"%s": a model that follows the instruction is delivered as written, with no event', async (question) => {
    const h = harness({ chat: [{ content: COMPLIANT_ANSWER }] })
    const output = await flow(h, question)

    expect(output.text).toBe(COMPLIANT_ANSWER)
    expect(output.text).not.toMatch(FORBIDDEN)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toHaveLength(0)
  })
})

// ── 3. The last line of defence ─────────────────────────────────────────────
describe('audit 2026-10-05 Flow names — an answer that still carries a name', () => {
  it('"método MPP" and "Dr. Roberto Menescal" are delivered without them, and the event has counts only', async () => {
    const leaked =
      'Pelo método MPP, sua meta de hoje é 2.980 kcal. O Dr. Roberto Menescal recomenda dividir a proteína ao longo do dia.'
    const h = harness({ chat: [{ content: leaked }] })
    const output = await flow(h, 'Como funciona minha meta?')

    expect(output.text).toBe(
      'Pelo método Performe AI, sua meta de hoje é 2.980 kcal. O Performe AI recomenda dividir a proteína ao longo do dia.',
    )
    expect(output.text).not.toMatch(FORBIDDEN)

    const written = events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)
    expect(written).toHaveLength(1)
    const properties = written[0]?.properties as Row
    expect(properties).toEqual({
      stage: 'ganho_massa',
      ...NO_NAMES,
      method_names: 1,
      persona_other: 1,
    })
    // Counts and the stage: no word of the answer or of the question.
    for (const [key, value] of Object.entries(properties)) {
      if (key !== 'stage') expect(typeof value).toBe('number')
    }
    expect(JSON.stringify(written)).not.toMatch(FORBIDDEN)
    expect(JSON.stringify(written)).not.toMatch(TITLE_AND_FIRST_NAME)
  })

  it("the model calling ITSELF by the physician's name is Flow", async () => {
    const h = harness({
      chat: [{ content: 'Oi! Sou o Dr. Roberto Menescal e vou te acompanhar por aqui.' }],
    })
    const output = await flow(h, 'Oi, quem é você?')

    expect(output.text).toBe('Oi! Sou o Flow e vou te acompanhar por aqui.')
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)[0]?.properties).toEqual({
      stage: 'ganho_massa',
      ...NO_NAMES,
      persona_self: 1,
    })
  })

  it('the tokens, the cost, the model and the tool calls of the turn are untouched', async () => {
    const leaked = 'Isso é o MPP.'
    const clean = 'Isso é o programa.'
    const withName = await flow(harness({ chat: [{ content: leaked }] }), ASKS_ACRONYM)
    const without = await flow(harness({ chat: [{ content: clean }] }), ASKS_ACRONYM)

    expect({ ...withName, text: '', latencyMs: 0 }).toEqual({ ...without, text: '', latencyMs: 0 })
  })
})

// ── 4. Ordinary answers ─────────────────────────────────────────────────────
describe('audit 2026-10-05 Flow names — an ordinary answer is the string the model wrote', () => {
  it.each([
    'Sua meta de hoje é 2.980 kcal e 144 g de proteína.',
    'Você é quem decide: a sugestão só vale depois que você confirmar no app.',
    // The first name alone is a person's name, not the physician.
    'Boa, Roberto! Treinar hoje ajuda no seu objetivo. Qualquer dúvida, fale com seu médico.',
    'O Performe AI organiza suas metas; eu sou o Flow.',
    '',
  ])('%j is delivered byte for byte and writes no event', async (answer) => {
    const h = harness({
      chat: [{ content: answer }],
      user: { ...USER, name: 'Roberto' },
    })
    const output = await flow(h, 'Como está meu dia até agora?')

    expect(output.text).toBe(answer)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toHaveLength(0)
    expect(projectFlowPublicNames(answer).text).toBe(answer)
  })
})

// ── 5. The decision of 2026-10-05, sentence by sentence ─────────────────────
// Every answer below is an exact sentence of the decision that closed the
// review (the ones the first filter got wrong, and the ones it must still
// replace). `counts: null` = the turn writes no event at all.
describe('audit 2026-10-05 Flow names — the closed vocabulary, on the real entry point', () => {
  const FIRST_NAME_ONLY = { ...NO_NAMES, persona_first_name_only: 1 }

  it.each([
    // The person, or someone else, with the title: never renamed (RC FN-7).
    { answer: 'Bom treino, Dr. Roberto!', counts: FIRST_NAME_ONLY },
    { answer: 'Perfeito, Dr. Roberto. Registrei seu almoço.', counts: FIRST_NAME_ONLY },
    { answer: 'Dr. Roberto\nSeu almoço foi registrado.', counts: FIRST_NAME_ONLY },
    { answer: 'Fale com seu médico, o Dr. Roberto Silva.', counts: FIRST_NAME_ONLY },
    { answer: 'Dr. Roberto Carlos, seu cardiologista', counts: FIRST_NAME_ONLY },
    // Another person who carries the surname.
    { answer: 'Dra. Roberta Menescal', counts: null },
    // Not his name.
    { answer: 'Roberto Carlos canta bem.', counts: null },
    { answer: 'Boa, Roberto!', counts: null },
    { answer: 'Dr. Robertson', counts: null },
    { answer: 'Dr. Roberta cuida disso.', counts: null },
    { answer: 'M P Pereira', counts: null },
    // Outside the closed vocabulary (RC FN-4).
    { answer: 'Menescau', counts: null },
    { answer: 'Dr. Róberto', counts: null },
    { answer: 'Método do Dr. Fulano', counts: null },
    // A segment of a URL, of a path or of an identifier.
    { answer: 'https://example.com/mpp/guia', counts: null },
    { answer: 'https://mpp.example.com/guia', counts: null },
    { answer: 'docs/CALCULO-MPP.md', counts: null },
    { answer: 'MPP-2', counts: null },
    { answer: '@mpp/agent', counts: null },
    { answer: 'mppx', counts: null },
    { answer: 'agentempp', counts: null },
    { answer: 'mpp_mensal_v1', counts: null },
  ])('$answer is delivered as the model wrote it', async ({ answer, counts }) => {
    const h = harness({ chat: [{ content: answer }] })
    const output = await flow(h, 'Como está meu dia até agora?')

    expect(output.text).toBe(answer)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT).map((event) => event.properties)).toEqual(
      counts ? [{ stage: 'ganho_massa', ...counts }] : [],
    )
  })

  it.each([
    {
      answer: 'Sou o Dr. Roberto Menescal.',
      delivered: 'Sou o Flow.',
      counts: { ...NO_NAMES, persona_self: 1 },
    },
    {
      answer: 'O método foi criado pelo Dr. Roberto Menescal.',
      delivered: 'O método foi criado pelo Performe AI.',
      counts: { ...NO_NAMES, persona_other: 1 },
    },
    {
      answer: 'É o M.P.P., sim.',
      delivered: 'É o Performe AI, sim.',
      counts: { ...NO_NAMES, method_names: 1 },
    },
    {
      answer: 'É o M.P.P.',
      delivered: 'É o Performe AI.',
      counts: { ...NO_NAMES, method_names: 1 },
    },
    {
      answer: 'É o M. P. P.',
      delivered: 'É o Performe AI.',
      counts: { ...NO_NAMES, method_names: 1 },
    },
    {
      answer: 'É o M P P',
      delivered: 'É o Performe AI',
      counts: { ...NO_NAMES, method_names: 1 },
    },
    { answer: 'MPPs', delivered: 'Performe AI', counts: { ...NO_NAMES, method_names: 1 } },
    {
      answer: 'Muscular-Power-Plant',
      delivered: 'Performe AI',
      counts: { ...NO_NAMES, method_names: 1 },
    },
    {
      answer: 'MuscularPowerPlant',
      delivered: 'Performe AI',
      counts: { ...NO_NAMES, method_names: 1 },
    },
    {
      answer: 'MPP (Muscular Power Plant)',
      delivered: 'Performe AI (Performe AI)',
      counts: { ...NO_NAMES, method_names: 2 },
    },
  ])('$answer is delivered as $delivered', async ({ answer, delivered, counts }) => {
    const h = harness({ chat: [{ content: answer }] })
    const output = await flow(h, 'Como está meu dia até agora?')

    expect(output.text).toBe(delivered)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT).map((event) => event.properties)).toEqual([
      { stage: 'ganho_massa', ...counts },
    ])
  })

  // The account guard: the registered name is the one the Flow context loads.
  const GREETING = 'Bom dia, Roberto Menescal! Vamos registrar o almoço?'

  it(`an account registered as "${MENESCAL_ACCOUNT_NAME}" is greeted by its own name, with no event`, async () => {
    const h = harness({
      chat: [{ content: GREETING }],
      user: { ...USER, name: MENESCAL_ACCOUNT_NAME },
    })
    const output = await flow(h, 'Bom dia!')

    expect(h.systemPrompts[0]).toContain(`- Nome: ${MENESCAL_ACCOUNT_NAME}`)
    expect(output.text).toBe(GREETING)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toHaveLength(0)
  })

  it.each([
    'ROBERTO MENESCAL',
    'Roberto Menéscal',
    'Dr. Roberto Menescal Filho',
  ])('the account guard ignores case and accents: registered as %j', async (name) => {
    const h = harness({ chat: [{ content: GREETING }], user: { ...USER, name } })
    const output = await flow(h, 'Bom dia!')

    expect(output.text).toBe(GREETING)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toHaveLength(0)
  })

  it.each([
    'QA A',
    'Roberto',
    null,
  ])('any other account (registered as %j) does not receive the name', async (name) => {
    const h = harness({ chat: [{ content: GREETING }], user: { ...USER, name } })
    const output = await flow(h, 'Bom dia!')

    expect(output.text).toBe('Bom dia, Performe AI! Vamos registrar o almoço?')
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT).map((event) => event.properties)).toEqual([
      { stage: 'ganho_massa', ...NO_NAMES, persona_other: 1 },
    ])
  })

  it('on that account the method names are still replaced', async () => {
    const h = harness({
      chat: [
        {
          content:
            'Bom dia, Dr. Roberto Menescal! Pelo método MPP (Muscular Power Plant), sua meta de hoje é 2.980 kcal.',
        },
      ],
      user: { ...USER, name: MENESCAL_ACCOUNT_NAME },
    })
    const output = await flow(h, 'Bom dia!')

    expect(output.text).toBe(
      'Bom dia, Dr. Roberto Menescal! Pelo método Performe AI (Performe AI), sua meta de hoje é 2.980 kcal.',
    )
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT).map((event) => event.properties)).toEqual([
      { stage: 'ganho_massa', ...NO_NAMES, method_names: 2 },
    ])
  })

  it('on that account "Dr. Roberto" is the person: delivered as written and not even counted', async () => {
    const h = harness({
      chat: [{ content: 'Bom treino, Dr. Roberto!' }],
      user: { ...USER, name: MENESCAL_ACCOUNT_NAME },
    })
    const output = await flow(h, 'Vou treinar agora.')

    expect(output.text).toBe('Bom treino, Dr. Roberto!')
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toHaveLength(0)
  })

  it('the guard adds no query: the same reads with and without a name to replace', async () => {
    // Each turn starts with the config caches empty, as the first one does.
    const turn = async (fixture: Fixture) => {
      clearCalcConfigCache()
      resetRouterFlagCacheForTests()
      const h = harness(fixture)
      await flow(h, 'Bom dia!')
      return h
    }
    const clean = await turn({ chat: [{ content: 'Bom dia! Vamos registrar o almoço?' }] })
    const other = await turn({ chat: [{ content: GREETING }] })
    const own = await turn({
      chat: [{ content: GREETING }],
      user: { ...USER, name: MENESCAL_ACCOUNT_NAME },
    })

    const reads = (h: Harness) => h.tables.filter((table) => table !== 'product_events')
    expect(reads(clean)).toContain('users')
    expect(reads(other)).toEqual(reads(clean))
    expect(reads(own)).toEqual(reads(clean))
    // The only difference is the one telemetry row of the turn that replaced.
    const writes = (h: Harness) => h.tables.filter((table) => table === 'product_events').length
    expect(writes(other)).toBe(writes(clean) + 1)
    expect(writes(own)).toBe(writes(clean))
  })
})

// ── 6. A plan suggestion ────────────────────────────────────────────────────
describe('audit 2026-10-05 Flow names — a plan suggestion whose generator cited the method', () => {
  it('the chat text is filtered; RC FN-3 (pendency): the stored draft is not', async () => {
    const h = harness({
      chat: [
        {
          toolCalls: [
            { id: 'call-1', name: 'propoe_plano_treino', arguments: JSON.stringify(WORKOUT_ARGS) },
          ],
        },
      ],
      generator: WORKOUT_OUTPUT_WITH_NAMES,
    })
    const output = await flow(h, WORKOUT_PHRASE)

    const stored = h.rpcs.filter((call) => call.name === 'create_plan_draft_atomic')
    expect(stored).toHaveLength(1)
    const payload = stored[0]?.params.p_payload as Parameters<typeof trainingSuggestionText>[0]
    const suggestion = trainingSuggestionText(payload)
    // The stored draft and its text carry the names, as the generator wrote.
    expect(JSON.stringify(payload)).toMatch(FORBIDDEN)
    expect(suggestion).toContain(
      'Progressão: Progressão em escada do Método MPP (Muscular Power Plant), como o Dr. Roberto Menescal recomenda',
    )
    // The chat does not.
    expect(output.text).not.toMatch(FORBIDDEN)
    expect(output.text).toContain(
      'Progressão: Progressão em escada do Método Performe AI (Performe AI), como o Performe AI recomenda: aumente a carga ao completar o ciclo.',
    )
    expect(output.text).toContain('• Agachamento livre — 3×12-15, descanso 90 s')
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)[0]?.properties).toEqual({
      stage: 'ganho_massa',
      ...NO_NAMES,
      method_names: 2,
      persona_other: 1,
    })
  })
})

// ── 7. The legacy WhatsApp entry is not changed in this lot ─────────────────
describe('audit 2026-10-05 Flow names — processMessage (legacy) keeps its behaviour', () => {
  it('delivers the same answer with the names, writes no such event and keeps its persona', async () => {
    const leaked =
      'Pelo método MPP, sua meta de hoje é 2.980 kcal. O Dr. Roberto Menescal recomenda dividir a proteína ao longo do dia.'
    const h = harness({ channel: 'whatsapp', chat: [{ content: leaked }] })
    const output = await whatsapp(h, ASKS_METHOD)

    expect(output.text).toBe(leaked)
    expect(events(h, MOBILE_FLOW_PUBLIC_NAMES_EVENT)).toHaveLength(0)
    const prompt = h.systemPrompts[0] ?? ''
    expect(prompt.startsWith(SHARED_RULES)).toBe(true)
    expect(prompt).not.toContain('Nunca escreva "MPP"')
  })
})

// ── 8. The declared pendencies are the doc's ────────────────────────────────
describe('audit 2026-10-05 Flow names — declared pendencies', () => {
  const header = readFileSync(fileURLToPath(import.meta.url), 'utf8')
  const fromHeader = Array.from(header.matchAll(/^ \* (> RC FN-\d+ — .*)$/gm), (match) => match[1])

  it('every "RC FN" line of this header is in docs/mobile/api-v1.md, identical', () => {
    const doc = readFileSync(
      fileURLToPath(new URL('../../../../docs/mobile/api-v1.md', import.meta.url)),
      'utf8',
    )
    const fromDoc = Array.from(doc.matchAll(/^(> RC FN-\d+ — .*)$/gm), (match) => match[1])
    expect(fromHeader).toHaveLength(7)
    expect(fromHeader.map((entry) => entry?.slice(0, 9))).toEqual([
      '> RC FN-1',
      '> RC FN-2',
      '> RC FN-3',
      '> RC FN-4',
      '> RC FN-5',
      '> RC FN-6',
      '> RC FN-7',
    ])
    expect(fromDoc).toEqual(fromHeader)
    // The project's mandatory wording of a pendency, then at least a sentence.
    for (const entry of fromHeader) {
      expect(entry).toMatch(
        /^> RC FN-\d+ — cenário .+ (?:NÃO coberto nesta PR \(pendência da audit 2026-10-05\)|variante NÃO coberta pelo filtro nesta PR \(fica só a instrução ao modelo; pendência da audit 2026-10-05\))\. \S/,
      )
    }
  })

  it('RC FN-7 is the pendency of the decision, word for word', () => {
    const decided = `> RC FN-7 — cenário "Flow escreve 'Dr. Roberto' sem o sobrenome" variante NÃO coberta pelo filtro nesta PR (fica só a instrução ao modelo; pendência da audit 2026-10-05)`
    expect(fromHeader[6]?.slice(0, decided.length)).toBe(decided)
  })

  it('RC FN-3 (the stored plan draft) is still declared as not covered', () => {
    expect(fromHeader[2]).toContain('RASCUNHO gravado de uma sugestão de plano')
    expect(fromHeader[2]).toContain('NÃO coberto nesta PR')
  })

  it('RC FN-4 names every spelling the filter knows, and the filter agrees with it', () => {
    const covered = fromHeader[3] ?? ''
    // Each spelling the block says is replaced is replaced…
    for (const spelling of ['MPP', 'MPPs', 'M.P.P.', 'M. P. P.', 'M P P', 'Muscular Power Plant']) {
      expect(covered).toContain(`"${spelling}"`)
      expect(projectFlowPublicNames(`É o ${spelling}`).text, spelling).not.toMatch(
        /MPP|M\.|M P|Muscular/,
      )
    }
    for (const lead of [
      'sou o',
      'sou',
      'aqui é o',
      'aqui é',
      'me chamo',
      'meu nome é',
      'I am',
      "I'm",
      'this is',
    ]) {
      expect(covered).toContain(`"${lead}"`)
      expect(projectFlowPublicNames(`${lead} Dr. Roberto Menescal`).text, lead).toBe(`${lead} Flow`)
    }
    for (const title of ['Dr.', 'Dr', 'Dra.', 'Doutor', 'Doctor']) {
      expect(covered).toContain(title)
      expect(projectFlowPublicNames(`Com ${title} Roberto Menescal`).text, title).toBe(
        'Com Performe AI',
      )
    }
    // …and each one it says goes through, goes through.
    for (const untouched of [
      'https://example.com/mpp/guia',
      'https://mpp.example.com/guia',
      'docs/CALCULO-MPP.md',
      'MPP-2',
      '@mpp/agent',
      'mppx',
      'agentempp',
      'mpp_mensal_v1',
      'MPP/Muscular Power Plant',
      '__MPP__',
      'Dra. Roberta Menescal',
      'Ana Menescal',
      'Segundo Menescal, …',
      'Menescau',
      'Dr. Róberto',
      'm.p.p.',
      'M P Pereira',
      'Método do Dr. Fulano',
    ]) {
      expect(covered).toContain(`"${untouched}"`)
      expect(projectFlowPublicNames(untouched).text).toBe(untouched)
    }
    expect(covered).toContain('"Soy el Dr. Roberto Menescal." vira "Soy el Performe AI."')
    expect(projectFlowPublicNames('Soy el Dr. Roberto Menescal.').text).toBe('Soy el Performe AI.')
  })

  it('RC FN-4 declares the known limits of the review of 2026-10-05, and the filter behaves as declared', () => {
    const covered = fromHeader[3] ?? ''
    expect(covered).toContain('Limites conhecidos, sem correção nesta PR')
    for (const [written, received] of [
      ['https://example.com/guia?ref=mpp', 'https://example.com/guia?ref=Performe AI'],
      ['https://example.com/guia#mpp', 'https://example.com/guia#Performe AI'],
      ['utm_source=mpp', 'utm_source=Performe AI'],
      ['Não sou o Dr. Roberto Menescal.', 'Não sou o Performe AI.'],
      ['Sra. Menescal', 'Sra. Performe AI'],
    ] as const) {
      expect(covered).toContain(`"${written}" vira "${received}"`)
      expect(projectFlowPublicNames(written).text, written).toBe(received)
    }
    for (const untouched of [
      'É o MPP.Sim',
      'Dr. Roberto Menescal/CRM 123',
      '_Dr. Roberto Menescal_',
      'Professor Menescal',
    ]) {
      expect(covered).toContain(`"${untouched}"`)
      expect(projectFlowPublicNames(untouched).text, untouched).toBe(untouched)
    }
    // The backslash path is named in words only (no example in the block).
    expect(projectFlowPublicNames('C:\\docs\\MPP\\guia').text).toBe('C:\\docs\\Performe AI\\guia')
  })
})
