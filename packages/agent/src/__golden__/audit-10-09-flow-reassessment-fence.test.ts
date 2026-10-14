/**
 * Audit 2026-10-09 — package C26a: the legacy reassessment tool is taken off
 * the app's Flow. Rule and pendencies: docs/CALCULO-MPP.md §10r.
 *
 * THE FINDING (read in the code at commit 2d559d4; no print of a patient
 * exists for it). `consulta_reavaliacao_protocolo` (packages/agent/src/tools.ts)
 * was the 4th name of `MOBILE_FLOW_READ_ONLY_TOOLS`. On a Flow turn of a person
 * in ganho de massa or manutenção the model could call it with a weight, a
 * body fat or a number of trainings typed in the chat, and the pipeline
 * handed the raw result back to the model: `safety.action` "pausar_ganho" or
 * "revisar_fase", the ceiling flags, the pace verdict, and the maintenance
 * `adjustmentKcal` of -150 / -300 with a `reason` that spells the rule. Its
 * description ("teto de gordura/IMC, ajuste calórico") also went in the tool
 * schemas of every Flow turn, for the three objectives.
 *
 * WHY IT IS A DEFECT. The owner's decisions of 2026-10-07 (decisions-v1, items
 * 2, 3 and 4) keep those three things switched off until the physician
 * answers: the gain ceilings and the pause (C28), any calorie change in gain
 * (C29) and the maintenance triggers, the -150 per missing training included
 * (C30). The app has no reassessment yet; a pause or a change of phase exists
 * only inside it, with confirmation.
 *
 * THE FENCE (the only production change): the name leaves
 * `MOBILE_FLOW_READ_ONLY_TOOLS` in packages/agent/src/pipeline.ts. The
 * dispatch boundary that already existed then refuses a call by name, nothing
 * of the tool runs and the configured `allowed_tools` cannot bring it back.
 * The tool stays in `ALL_TOOLS`: the legacy entry (`processMessage`) keeps the
 * tool, its schema and its result byte for byte — first block below, green
 * before and after the change. No formula, threshold or wording of the method
 * changed; packages/agent/src/tools.ts and packages/core are not touched.
 *
 * WHAT THE FENCE DOES NOT CLOSE. It closes the tool, not what the model says.
 * Three things still reach the Flow model and are pinned below as they are
 * (third block, green before and after): the "- Decisão automática" line of
 * the per-turn context; any active stage row of `agent_rules`, whole; and the
 * full prompt of the view when the rules cannot be read. No sentence was added
 * to the Flow policy: its wording is the owner's to approve, and it would send
 * the person to a reassessment the app does not have.
 *
 * NUMBERS — no name, weight or height of a patient. The five inputs are the
 * ones of the tests that pin the three primitives
 * (packages/core/src/engine/protocols.test.ts): body fat 15% → 18,1% (+3,1
 * points), BMI +1,6, and 5 → 4, 5 → 3 and 5 → 2 trainings a week. The chat
 * phrases are synthetic. The instant is fixed (2026-10-09T15:00:00.000Z) and
 * the cycle started 14 days before it. The six general rules are the staging
 * versions of the fixture read on 2026-10-08 under authorization; the stage
 * rule of the third block is a synthetic marker with no clinical content. NO
 * database, model or network was used here.
 *
 * Every test runs the REAL pipeline entry against a fake database and a
 * scripted model.
 *
 * Declared pendencies (CLAUDE.md criterion 2; same lines in docs/CALCULO-MPP.md §10r):
 *
 * > RC C26a — cenário pessoa em ganho de massa ou manutenção perguntando ao Flow se deve pausar o ganho, revisar a fase ou cortar calorias variante frase real de uma conversa (não há print: as frases do golden são sintéticas e os números são os dos testes que travam as três contas) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário modelo real afirmando por conta própria pausa do ganho, revisão de fase ou corte de 150 ou 300 kcal, sem a ferramenta variante filtro determinístico na resposta do Flow e rodada com o modelo real no ambiente de teste NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário modelo do Flow, já sem a ferramenta, raciocinando sozinho sobre pausa do ganho, troca de fase ou mudança de calorias no ganho de massa ou na manutenção variante instrução só do Flow proibindo isso (a redação é do Eduardo e mandaria a pessoa a uma reavaliação que o app ainda não tem) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário linha "Decisão automática" do contexto do Flow (protocol=recomposicao, canChoose e blockers de resolveProtocol) lida pelo modelo de quem está em ganho de massa ou manutenção variante retirar a linha do Flow ou trocá-la pelo estado gravado da fase (C26b) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário regras ativas de fase em agent_rules (tipo ganho_massa ou manutencao) entrando inteiras no bloco estável do Flow, e o prompt inteiro da view quando a leitura das regras falha variante leitura dessas regras no banco do ambiente de teste e projeção delas só no Flow (o cabeçalho de packages/core/src/engine/protocols.ts diz que os tetos, a pausa e os −150 kcal por treino vieram das regras do método; nenhum banco foi lido) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário respostas antigas do Flow já gravadas que mandaram pausar o ganho ou cortar 150 ou 300 kcal variante correção do histórico que o app mostra e que o modelo relê NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário ritmo de ganho (0,25% a 0,5% do peso por semana) pedido ao Flow variante resposta com o número calculado (sai do Flow junto com a ferramenta; a volta depende da decisão do Eduardo no C28) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário lista allowed_tools dos estágios de ganho de massa e de manutenção no banco do ambiente de teste variante leitura do valor gravado (a cerca vale com qualquer valor; o valor não foi lido, e um estágio que liste só esta ferramenta deixa o Flow sem ferramenta nenhuma) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C26a — cenário caminho legado (processMessage) chamando consulta_reavaliacao_protocolo variante deixar de devolver pausar_ganho, revisar_fase e −150 ou −300 kcal (o legado fica igual, byte a byte, por decisão) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 */
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import type { PipelineDeps } from '../pipeline.js'
import {
  authorizeToolCall,
  MOBILE_FLOW_READ_ONLY_TOOLS,
  MOBILE_FLOW_TOOLS,
  mobileFlowSystemPolicy,
  processAuthenticatedMessage,
  processMessage,
  selectPipelineTools,
} from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import { consultaReavaliacaoProtocolo } from '../tools.js'

const HERE = dirname(fileURLToPath(import.meta.url))

const TOOL = 'consulta_reavaliacao_protocolo'
/** What the dispatch boundary answers to a name outside the request's set. */
const REFUSAL = '{"success":false,"error":"tool_not_authorized","retry_tool":false}'
/** The tool's description, as the legacy channel sends it (tools.ts). */
const TOOL_DESCRIPTION =
  'Computa as decisões DETERMINÍSTICAS da reavaliação de GANHO DE MASSA ou MANUTENÇÃO (velocidade de ganho, teto de gordura/IMC, ajuste calórico) a partir do baseline do ciclo e dos valores atuais. Use na reavaliação (~14 dias), DEPOIS que o paciente informar peso/BF atuais. Só para ganho_massa/manutencao (recomposição usa a escada de déficit). Os números vêm CALCULADOS — não invente velocidade/ajuste de cabeça.'
/** The tool's OWN read of the profile (tools.ts), column for column. */
const TOOL_OWN_READ =
  'sex, height_cm, current_protocol, training_frequency, cycle_start_weight_kg, cycle_start_bf_percent, cycle_start_training_freq, cycle_start_at'

const NOW = new Date('2026-10-09T15:00:00.000Z') // 12:00 in São Paulo, a Friday
const CYCLE_START = '2026-09-25T15:00:00.000Z' // 14 days before
const USER_ID = 'c26a-synthetic-user'
const FLOW_TURN_ID = `mobile_flow/${USER_ID}/c26a-turn`
const LEGACY_TURN_ID = 'wamid.c26a-turn'
const ANTHROPIC = 'anthropic/test-model'
const NOT_ANTHROPIC = 'openai/test-model'
const VIEW_PROMPT = 'REGRAS COMPARTILHADAS'
const MODEL_ANSWER = 'Resposta do modelo.'

type Row = Record<string, unknown>

const USER: Row = {
  id: USER_ID,
  name: 'Pessoa sintética',
  summary: null,
  last_active_at: null,
  country: 'BR',
  country_confirmed: true,
  country_detected_from_wpp: null,
  locale: 'pt-BR',
  metadata: null,
  timezone: 'America/Sao_Paulo',
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

const BODY: Row = {
  user_id: USER_ID,
  onboarding_completed: true,
  onboarding_completed_at: null,
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: 15,
  activity_level: 'moderado',
  water_intake: 'moderado',
  hunger_level: 'moderada',
  goal_type: null,
  goal_value: null,
  deficit_level: null,
}

/** Ganho de massa: the cycle started at 80 kg and 15% of body fat, 14 days ago. */
const GAIN_PROFILE: Row = {
  ...BODY,
  training_frequency: 4,
  current_protocol: 'ganho_massa',
  cycle_start_weight_kg: 80,
  cycle_start_bf_percent: 15,
  cycle_start_training_freq: 4,
  cycle_start_at: CYCLE_START,
}

/** Manutenção: 5 trainings a week when the cycle started. */
const MAINTENANCE_PROFILE: Row = {
  ...BODY,
  training_frequency: 5,
  current_protocol: 'manutencao',
  cycle_start_weight_kg: 80,
  cycle_start_bf_percent: 15,
  cycle_start_training_freq: 5,
  cycle_start_at: CYCLE_START,
}

const RECOMPOSITION_PROFILE: Row = {
  ...BODY,
  body_fat_percent: 24,
  training_frequency: 3,
  current_protocol: 'recomposicao',
  deficit_level: 500,
}

interface Scenario {
  label: string
  profile: Row
  /** Synthetic chat phrase; never one the Flow answers without the model. */
  text: string
  /** What the model asks the tool with. */
  args: Record<string, number>
  /** What the tool answers on the legacy channel, as the model receives it. */
  result: string
}

const GAIN: Scenario[] = [
  {
    label: 'G1, gordura 15% → 18,1%',
    profile: GAIN_PROFILE,
    text: 'Hoje a balança marcou 80,6 kg e a bioimpedância deu 18,1% de gordura. O que isso muda na minha fase?',
    args: { current_weight_kg: 80.6, current_bf_percent: 18.1 },
    result:
      '{"protocol":"ganho_massa","days_in_cycle":14,"velocity":{"weeklyPctChange":0.37,"minSafeKgWeek":0.2,"maxSafeKgWeek":0.4,"status":"ideal"},"safety":{"bfDelta":3.1,"imcDelta":0.2,"bfCeilingExceeded":true,"imcCeilingExceeded":false,"withinLimits":false,"action":"pausar_ganho"}}',
  },
  {
    label: 'G2, IMC +1,6',
    profile: GAIN_PROFILE,
    text: 'Hoje a balança marcou 85,2 kg e a bioimpedância deu 18,5% de gordura. O que isso muda na minha fase?',
    args: { current_weight_kg: 85.2, current_bf_percent: 18.5 },
    result:
      '{"protocol":"ganho_massa","days_in_cycle":14,"velocity":{"weeklyPctChange":3.25,"minSafeKgWeek":0.2,"maxSafeKgWeek":0.4,"status":"rapido"},"safety":{"bfDelta":3.5,"imcDelta":1.6,"bfCeilingExceeded":true,"imcCeilingExceeded":true,"withinLimits":false,"action":"revisar_fase"}}',
  },
]

const MAINTENANCE: Scenario[] = [
  {
    label: 'M1, treinos 5 → 4',
    profile: MAINTENANCE_PROFILE,
    text: 'Nestas duas semanas fiz musculação 4 vezes por semana, antes eram 5. O que isso muda para mim?',
    args: { current_weight_kg: 80, current_training_freq: 4 },
    result:
      '{"protocol":"manutencao","adjustment":{"adjustmentKcal":-150,"missingTrainings":1,"reason":"1 treino(s) a menos/semana → -150 kcal/dia (−150/treino, cap −300/ciclo)"}}',
  },
  {
    label: 'M2, treinos 5 → 3',
    profile: MAINTENANCE_PROFILE,
    text: 'Nestas duas semanas fiz musculação 3 vezes por semana, antes eram 5. O que isso muda para mim?',
    args: { current_weight_kg: 80, current_training_freq: 3 },
    result:
      '{"protocol":"manutencao","adjustment":{"adjustmentKcal":-300,"missingTrainings":2,"reason":"2 treino(s) a menos/semana → -300 kcal/dia (−150/treino, cap −300/ciclo)"}}',
  },
  {
    label: 'M3, treinos 5 → 2',
    profile: MAINTENANCE_PROFILE,
    text: 'Nestas duas semanas fiz musculação 2 vezes por semana, antes eram 5. O que isso muda para mim?',
    args: { current_weight_kg: 80, current_training_freq: 2 },
    result:
      '{"protocol":"manutencao","adjustment":{"adjustmentKcal":-300,"missingTrainings":3,"reason":"3 treino(s) a menos/semana → -300 kcal/dia (−150/treino, cap −300/ciclo)"}}',
  },
]

const [G1] = GAIN as [Scenario, Scenario]

/** Every field name and verdict only the tool's result carries. */
const GAIN_RESULT_WORDS = [
  'pausar_ganho',
  'revisar_fase',
  'bfCeilingExceeded',
  'imcCeilingExceeded',
  'withinLimits',
  'weeklyPctChange',
  'minSafeKgWeek',
  'maxSafeKgWeek',
  'days_in_cycle',
]
const MAINTENANCE_RESULT_WORDS = [
  'adjustmentKcal',
  'missingTrainings',
  '-150 kcal/dia',
  '-300 kcal/dia',
  '−150/treino',
  'cap −300/ciclo',
]

/** A neutral phrase the model answers (no status, metric or capabilities question). */
const NEUTRAL_TEXT = 'Explique meu contexto atual sem alterar nenhum dado.'

const FLOW_TOOL_NAMES = [
  'consulta_progresso',
  'consulta_metricas',
  'consulta_resumo_periodo',
  'propoe_plano_treino',
  'propoe_plano_dieta',
]

/** The 20 tools of the legacy channel, in the order it sends them. */
const LEGACY_TOOL_NAMES = [
  'cadastra_dados_iniciais',
  'define_protocolo',
  'define_meta_peso',
  'registra_refeicao',
  'registra_treino',
  'consulta_progresso',
  'consulta_metricas',
  'consulta_resumo_periodo',
  'consulta_reavaliacao_protocolo',
  'registra_metrica_diaria',
  'marca_refeicao_pulada',
  'reclassifica_refeicao',
  'atualiza_data_user',
  'encerra_atendimento',
  'delete_user',
  'pausar_agente',
  'retomar_agente',
  'confirma_pais_residencia',
  'gera_dieta',
  'gera_treino',
]

/** The six general rules of staging, as read on 2026-10-08 (C2 fixture). */
const REVIEWED_RULES = (
  JSON.parse(
    readFileSync(resolve(HERE, 'fixtures/c2-staging-reviewed-general-rules-20261008.json'), 'utf8'),
  ) as { rules: Row[] }
).rules

/** The 20 tool schemas the WhatsApp request lock pins (read, never written). */
const LOCKED_LEGACY_TOOLS = (
  JSON.parse(
    readFileSync(resolve(HERE, 'fixtures/audit-10-04-whatsapp-request-lock.json'), 'utf8'),
  ) as { tools: unknown[] }
).tools

interface ScriptedStep {
  content?: string
  toolCalls?: Array<{ id: string; name: string; arguments: string }>
}

interface Fixture {
  channel: 'flow' | 'legacy'
  profile: Row
  text: string
  script: ScriptedStep[]
  model?: string
  /** `v_active_prompts.allowed_tools`; null = every tool. */
  allowedTools?: string[] | null
  /** Active rows of `agent_rules` the stage read returns. */
  rules?: Row[]
  /** `v_active_prompts.system_prompt`. */
  viewPrompt?: string
}

interface ToolSchema {
  type: string
  function: { name: string; description: string; parameters: unknown }
}

interface LlmCall {
  model: string
  systemPrompt: unknown
  tools: ToolSchema[]
  messages: Row[]
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Row }>
  llmCalls: LlmCall[]
  /** The column list of every read of `user_profiles`, in order. */
  profileReads: string[]
}

/**
 * Fake client that honours what the pipeline asks: the profile answers the
 * columns selected, messages are filtered by provider, the prompt row answers
 * the stage asked, and every insert is kept.
 */
function harness(fixture: Fixture): Harness {
  const provider = fixture.channel === 'flow' ? 'mobile_flow' : 'whatsapp_cloud'
  const model = fixture.model ?? ANTHROPIC
  const inserts: Harness['inserts'] = []
  const llmCalls: LlmCall[] = []
  const profileReads: string[] = []
  const stored: Row[] = [
    {
      direction: 'in',
      content: fixture.text,
      content_type: 'text',
      created_at: NOW.toISOString(),
      provider,
      provider_message_id: fixture.channel === 'flow' ? FLOW_TURN_ID : LEGACY_TURN_ID,
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
        return USER
      case 'user_profiles': {
        profileReads.push(read.columns)
        if (read.columns.trim() === '*') return fixture.profile
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), fixture.profile[key.trim()] ?? null]),
        )
      }
      case 'user_progress':
        return PROGRESS
      case 'messages': {
        const rows = stored.filter(
          (row) => read.filters.provider == null || row.provider === read.filters.provider,
        )
        return read.limit == null ? rows : rows.slice(0, read.limit)
      }
      case 'daily_snapshots':
        // No day row yet and no closed day in the 14-day window.
        return read.filters.day_closed === true ? [] : null
      case 'global_config':
        // The model router stays off: the turn keeps the stage's model.
        return read.filters.key === 'router.haiku_enabled' ? { value: false } : []
      case 'v_active_prompts':
        return {
          stage: read.filters.stage ?? null,
          model,
          temperature: 0.2,
          max_tokens: 1200,
          max_tool_iterations: 2,
          system_prompt: fixture.viewPrompt ?? VIEW_PROMPT,
          allowed_tools: fixture.allowedTools ?? null,
        }
      case 'agent_rules':
        return fixture.rules ?? []
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
        inserts.push({ table, row })
        return chain
      }
      chain.single = one
      chain.maybeSingle = one
      return chain
    },
    rpc: async (name: string, params: Row = {}) => {
      if (name === 'get_mobile_signup_body_photo_snapshot') {
        expect(params).toEqual({ p_user_id: USER_ID, p_include_open_photos: false })
        return {
          data: {
            version: 1,
            user_id: USER_ID,
            profile_present: true,
            locale: 'pt-BR',
            timezone: 'America/Sao_Paulo',
            generation_token: {
              onboarding_completed: true,
              onboarding_completed_at: null,
              receipt_count: 0,
            },
            poses: [],
            remaining_uploads: 0,
            consent: null,
            estimate: null,
            candidate: null,
            confirmation: null,
          },
          error: null,
        }
      }
      return {
        data: name === 'match_method_chunks' ? [] : USER_ID,
        error: null,
      }
    },
  } as unknown as PipelineDeps['supabase']

  let call = 0
  const llm = {
    complete: async (input: {
      model: string
      systemPrompt: unknown
      tools: ToolSchema[]
      messages: Row[]
    }) => {
      llmCalls.push(
        JSON.parse(
          JSON.stringify({
            model: input.model,
            systemPrompt: input.systemPrompt,
            tools: input.tools,
            messages: input.messages,
          }),
        ) as LlmCall,
      )
      const step = fixture.script[Math.min(call, fixture.script.length - 1)] ?? {}
      call += 1
      return {
        content: step.content ?? '',
        toolCalls: step.toolCalls ?? [],
        model,
        promptTokens: 1,
        completionTokens: 1,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']

  return { deps: { supabase, llm, maxToolIterations: 3 }, inserts, llmCalls, profileReads }
}

/** The model asks for the tool once, then answers. */
function asksTheTool(args: Record<string, number>): ScriptedStep[] {
  return [
    { toolCalls: [{ id: 'call-1', name: TOOL, arguments: JSON.stringify(args) }] },
    { content: MODEL_ANSWER },
  ]
}

function flow(h: Harness, text: string) {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: FLOW_TURN_ID,
    text,
    timestamp: NOW,
  })
}

function legacy(h: Harness, text: string) {
  return processMessage(h.deps, {
    from: '5511999990000',
    providerMessageId: LEGACY_TURN_ID,
    text,
    contentType: 'text',
    provider: 'whatsapp_cloud',
    timestamp: NOW,
  })
}

function toolMessages(call: LlmCall | undefined): Row[] {
  return (call?.messages ?? []).filter((message) => message.role === 'tool')
}

function toolNames(call: LlmCall | undefined): string[] {
  return (call?.tools ?? []).map((tool) => tool.function.name)
}

/** The two system blocks of an Anthropic request: [stable, per-turn]. */
function systemBlocks(call: LlmCall | undefined): Array<{ text: string; cache?: string }> {
  expect(Array.isArray(call?.systemPrompt)).toBe(true)
  const blocks = call?.systemPrompt as Array<{ text: string; cache?: string }>
  expect(blocks).toHaveLength(2)
  return blocks
}

function deniedEvents(h: Harness): Row[] {
  return h.inserts
    .filter(
      (entry) =>
        entry.table === 'product_events' && entry.row.event === 'pipeline.tool_call_denied',
    )
    .map((entry) => entry.row.properties as Row)
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})
afterEach(() => {
  vi.restoreAllMocks()
  vi.useRealTimers()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})

// ── 1. Legacy entry: identical, before and after ────────────────────────────

describe('audit 2026-10-09 C26a — legado (processMessage): idêntico', () => {
  it.each([
    ...GAIN,
    ...MAINTENANCE,
  ])('$label: a ferramenta roda uma vez e o modelo recebe o resultado inteiro', async (scenario) => {
    const execute = vi.spyOn(consultaReavaliacaoProtocolo, 'execute')
    const h = harness({
      channel: 'legacy',
      profile: scenario.profile,
      text: scenario.text,
      script: asksTheTool(scenario.args),
    })
    const output = await legacy(h, scenario.text)

    expect(h.llmCalls).toHaveLength(2)
    expect(execute).toHaveBeenCalledTimes(1)
    expect(toolMessages(h.llmCalls[1])).toEqual([
      { role: 'tool', tool_call_id: 'call-1', content: scenario.result },
    ])
    expect(output.toolCalls).toEqual([
      { name: TOOL, arguments: scenario.args, result: JSON.parse(scenario.result) },
    ])
    expect(output.text).toBe(MODEL_ANSWER)
    expect(h.profileReads).toContain(TOOL_OWN_READ)
    expect(deniedEvents(h)).toEqual([])
  })

  it('o pedido leva as 20 ferramentas na mesma ordem, e os 20 esquemas são os do request lock do WhatsApp', async () => {
    const h = harness({
      channel: 'legacy',
      profile: GAIN_PROFILE,
      text: NEUTRAL_TEXT,
      script: [{ content: MODEL_ANSWER }],
    })
    await legacy(h, NEUTRAL_TEXT)

    expect(h.llmCalls).toHaveLength(1)
    const [call] = h.llmCalls
    expect(toolNames(call)).toEqual(LEGACY_TOOL_NAMES)
    expect(call?.tools[8]?.function.description).toBe(TOOL_DESCRIPTION)
    expect(call?.tools).toEqual(LOCKED_LEGACY_TOOLS)
  })

  it('o prompt estável não leva a política do Flow, e "todas as ferramentas" continua incluindo a ferramenta', async () => {
    const h = harness({
      channel: 'legacy',
      profile: GAIN_PROFILE,
      text: NEUTRAL_TEXT,
      script: [{ content: MODEL_ANSWER }],
    })
    await legacy(h, NEUTRAL_TEXT)

    const [stable, perTurn] = systemBlocks(h.llmCalls[0])
    expect(stable).toEqual({ text: VIEW_PROMPT, cache: 'ephemeral_1h' })
    expect(perTurn?.text).not.toContain(mobileFlowSystemPolicy)
    expect(selectPipelineTools(null).map((tool) => tool.name)).toEqual(LEGACY_TOOL_NAMES)
    expect(authorizeToolCall(TOOL, selectPipelineTools(null))).toEqual({
      status: 'authorized',
      tool: consultaReavaliacaoProtocolo,
    })
  })

  it('cada palavra vigiada no Flow existe num dos cinco resultados que o legado recebe', () => {
    // So the "does not reach the model" checks of the next block watch real
    // words of the tool's result, not words that could never be there.
    for (const word of GAIN_RESULT_WORDS) {
      expect(
        GAIN.some((scenario) => scenario.result.includes(word)),
        word,
      ).toBe(true)
    }
    for (const word of MAINTENANCE_RESULT_WORDS) {
      expect(
        MAINTENANCE.some((scenario) => scenario.result.includes(word)),
        word,
      ).toBe(true)
    }
  })
})

// ── 2. The fence on the app's Flow ──────────────────────────────────────────

describe('audit 2026-10-09 C26a — Flow do app: a ferramenta de reavaliação fica fora do canal', () => {
  it.each(
    GAIN,
  )('ganho de massa, $label: a ferramenta não roda e o resultado dela não chega ao modelo', async (scenario) => {
    const execute = vi.spyOn(consultaReavaliacaoProtocolo, 'execute')
    const h = harness({
      channel: 'flow',
      profile: scenario.profile,
      text: scenario.text,
      rules: REVIEWED_RULES,
      script: asksTheTool(scenario.args),
    })
    const output = await flow(h, scenario.text)

    // Two model calls: the phrase was answered by the model, not by the system.
    expect(h.llmCalls).toHaveLength(2)
    // What the model receives for its call is the refusal, never the result.
    expect(toolMessages(h.llmCalls[1])).toEqual([
      { role: 'tool', tool_call_id: 'call-1', content: REFUSAL },
    ])
    expect(execute).not.toHaveBeenCalled()
    // The whole second request: system, tool schemas and messages.
    const secondRequest = JSON.stringify(h.llmCalls[1])
    for (const word of GAIN_RESULT_WORDS) expect(secondRequest, word).not.toContain(word)
    expect(output.toolCalls).toEqual([{ name: TOOL, arguments: {}, error: 'tool_not_authorized' }])
    expect(output.text).toBe(MODEL_ANSWER)
  })

  it.each(
    MAINTENANCE,
  )('manutenção, $label: a ferramenta não roda e o resultado dela não chega ao modelo', async (scenario) => {
    const execute = vi.spyOn(consultaReavaliacaoProtocolo, 'execute')
    const h = harness({
      channel: 'flow',
      profile: scenario.profile,
      text: scenario.text,
      rules: REVIEWED_RULES,
      script: asksTheTool(scenario.args),
    })
    const output = await flow(h, scenario.text)

    expect(h.llmCalls).toHaveLength(2)
    expect(toolMessages(h.llmCalls[1])).toEqual([
      { role: 'tool', tool_call_id: 'call-1', content: REFUSAL },
    ])
    expect(execute).not.toHaveBeenCalled()
    const secondRequest = JSON.stringify(h.llmCalls[1])
    for (const word of MAINTENANCE_RESULT_WORDS) expect(secondRequest, word).not.toContain(word)
    expect(output.toolCalls).toEqual([{ name: TOOL, arguments: {}, error: 'tool_not_authorized' }])
    expect(output.text).toBe(MODEL_ANSWER)
  })

  it('a chamada pelo nome grava um pipeline.tool_call_denied com nome, motivo e canal, sem os argumentos; a leitura própria da ferramenta não é feita', async () => {
    const execute = vi.spyOn(consultaReavaliacaoProtocolo, 'execute')
    const h = harness({
      channel: 'flow',
      profile: G1.profile,
      text: G1.text,
      rules: REVIEWED_RULES,
      script: asksTheTool(G1.args),
    })
    await flow(h, G1.text)

    expect(h.llmCalls).toHaveLength(2)
    // The proof that nothing of the tool ran is the spy, not the column lists.
    expect(execute).not.toHaveBeenCalled()
    expect(deniedEvents(h)).toEqual([
      { tool: TOOL, reason: 'tool_not_authorized', channel: 'mobile_flow' },
    ])
    const written = JSON.stringify(h.inserts)
    expect(written).not.toContain('80.6')
    expect(written).not.toContain('18.1')
    // The turn still loads the whole profile row; only the tool's own read is gone.
    expect(h.profileReads).toContain('*')
    expect(h.profileReads).not.toContain(TOOL_OWN_READ)
  })

  it.each([
    ['recomposicao', RECOMPOSITION_PROFILE],
    ['ganho_massa', GAIN_PROFILE],
    ['manutencao', MAINTENANCE_PROFILE],
  ] as const)('%s: o pedido leva 5 ferramentas e nenhuma descreve teto de gordura/IMC ou ajuste calórico', async (_objective, profile) => {
    const h = harness({
      channel: 'flow',
      profile,
      text: NEUTRAL_TEXT,
      rules: REVIEWED_RULES,
      script: [{ content: MODEL_ANSWER }],
    })
    await flow(h, NEUTRAL_TEXT)

    expect(h.llmCalls).toHaveLength(1)
    expect(toolNames(h.llmCalls[0])).toEqual(FLOW_TOOL_NAMES)
    const schemas = JSON.stringify(h.llmCalls[0]?.tools)
    for (const word of ['reavaliacao', 'teto de gordura/IMC', 'ajuste calórico']) {
      expect(schemas, word).not.toContain(word)
    }
  })

  it('a lista do canal não tem a ferramenta e a recusa é pelo nome', () => {
    expect([...MOBILE_FLOW_READ_ONLY_TOOLS]).toEqual([
      'consulta_progresso',
      'consulta_metricas',
      'consulta_resumo_periodo',
    ])
    expect([...MOBILE_FLOW_TOOLS]).toEqual(FLOW_TOOL_NAMES)
    expect(authorizeToolCall(TOOL, selectPipelineTools(null, MOBILE_FLOW_TOOLS))).toEqual({
      status: 'not_authorized',
    })
    expect(selectPipelineTools([TOOL], MOBILE_FLOW_TOOLS)).toEqual([])
  })

  it('allowed_tools do banco nomeando a ferramenta não a devolve ao Flow: o pedido leva só consulta_metricas', async () => {
    const execute = vi.spyOn(consultaReavaliacaoProtocolo, 'execute')
    const h = harness({
      channel: 'flow',
      profile: G1.profile,
      text: G1.text,
      rules: REVIEWED_RULES,
      allowedTools: [TOOL, 'consulta_metricas'],
      script: asksTheTool(G1.args),
    })
    await flow(h, G1.text)

    expect(h.llmCalls).toHaveLength(2)
    expect(toolNames(h.llmCalls[0])).toEqual(['consulta_metricas'])
    expect(execute).not.toHaveBeenCalled()
    expect(toolMessages(h.llmCalls[1])).toEqual([
      { role: 'tool', tool_call_id: 'call-1', content: REFUSAL },
    ])
  })

  it('modelo que não é da Anthropic (prompt de sistema em texto único): as mesmas 5 ferramentas e a mesma recusa', async () => {
    const execute = vi.spyOn(consultaReavaliacaoProtocolo, 'execute')
    const h = harness({
      channel: 'flow',
      profile: G1.profile,
      text: G1.text,
      rules: REVIEWED_RULES,
      model: NOT_ANTHROPIC,
      script: asksTheTool(G1.args),
    })
    await flow(h, G1.text)

    expect(h.llmCalls).toHaveLength(2)
    expect(typeof h.llmCalls[0]?.systemPrompt).toBe('string')
    expect(toolNames(h.llmCalls[0])).toEqual(FLOW_TOOL_NAMES)
    expect(execute).not.toHaveBeenCalled()
    expect(toolMessages(h.llmCalls[1])).toEqual([
      { role: 'tool', tool_call_id: 'call-1', content: REFUSAL },
    ])
  })
})

// ── 3. What the fence does NOT close (pinned as it is, before and after) ────

/** A stage rule with no clinical content: it only marks that the row arrives whole. */
const STAGE_RULE_TEXT =
  'MARCADOR_SINTETICO_C26A: texto sem regra alguma; marca que uma linha ativa da fase chega inteira ao modelo.'

function stageRule(stage: string): Row {
  return {
    slug: 'c26a-marcador-de-fase',
    topic: 'Marcador sintético da fase',
    tipo: stage,
    content: STAGE_RULE_TEXT,
    language: 'pt-BR',
    display_order: 10,
  }
}

describe('audit 2026-10-09 C26a — o que a cerca NÃO fecha (pendências travadas como estão)', () => {
  // The line as the pipeline writes it today for these two synthetic profiles
  // (80 kg, 1,80 m, 15% of body fat; sleep and food organization not stored).
  const DECISION_LINE =
    '- Decisão automática: protocol=recomposicao canChoose=false blockers=[horários de sono não informados; estruturação alimentar não informada] goal=BF=10'

  it.each([
    ['ganho_massa', GAIN_PROFILE],
    ['manutencao', MAINTENANCE_PROFILE],
  ] as const)('%s: a linha "Decisão automática" continua no contexto por turno que o modelo do Flow lê', async (objective, profile) => {
    const h = harness({
      channel: 'flow',
      profile,
      text: NEUTRAL_TEXT,
      rules: REVIEWED_RULES,
      script: [{ content: MODEL_ANSWER }],
    })
    await flow(h, NEUTRAL_TEXT)

    const [stable, perTurn] = systemBlocks(h.llmCalls[0])
    const lines = (perTurn?.text ?? '').split('\n')
    expect(lines).toContain(`- Protocolo atual: ${objective}`)
    expect(lines.filter((line) => line.startsWith('- Decisão automática:'))).toEqual([
      DECISION_LINE,
    ])
    expect(stable?.text).not.toContain('Decisão automática')
  })

  it('modelo que não é da Anthropic: a mesma linha está no texto único de sistema', async () => {
    const h = harness({
      channel: 'flow',
      profile: GAIN_PROFILE,
      text: NEUTRAL_TEXT,
      rules: REVIEWED_RULES,
      model: NOT_ANTHROPIC,
      script: [{ content: MODEL_ANSWER }],
    })
    await flow(h, NEUTRAL_TEXT)

    const system = h.llmCalls[0]?.systemPrompt
    expect(typeof system).toBe('string')
    expect(String(system).split('\n')).toContain(DECISION_LINE)
  })

  it.each([
    'ganho_massa',
    'manutencao',
  ] as const)('%s: uma regra ativa da fase em agent_rules chega inteira ao bloco estável do Flow, com as seis gerais revisadas', async (objective) => {
    const h = harness({
      channel: 'flow',
      profile: objective === 'ganho_massa' ? GAIN_PROFILE : MAINTENANCE_PROFILE,
      text: NEUTRAL_TEXT,
      rules: [...REVIEWED_RULES, stageRule(objective)],
      script: [{ content: MODEL_ANSWER }],
    })
    await flow(h, NEUTRAL_TEXT)

    const [stable, perTurn] = systemBlocks(h.llmCalls[0])
    // The reviewed composition applied (language card present)…
    expect(stable?.text).toContain('### Linguagem do Flow')
    // …and the stage rule is the first thing of the stable block, before the policy.
    expect(stable?.text.startsWith(`## Marcador sintético da fase\n\n${STAGE_RULE_TEXT}`)).toBe(
      true,
    )
    expect(stable?.text.indexOf(STAGE_RULE_TEXT)).toBeLessThan(
      stable?.text.indexOf(mobileFlowSystemPolicy) ?? -1,
    )
    expect(perTurn?.text).not.toContain(STAGE_RULE_TEXT)
  })

  it.each([
    'ganho_massa',
    'manutencao',
  ] as const)('%s: a mesma regra chega inteira quando as seis gerais não são as revisadas', async (objective) => {
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    const h = harness({
      channel: 'flow',
      profile: objective === 'ganho_massa' ? GAIN_PROFILE : MAINTENANCE_PROFILE,
      text: NEUTRAL_TEXT,
      rules: [stageRule(objective)],
      script: [{ content: MODEL_ANSWER }],
    })
    await flow(h, NEUTRAL_TEXT)

    const [stable] = systemBlocks(h.llmCalls[0])
    expect(stable?.text).not.toContain('### Linguagem do Flow')
    expect(stable?.text).toBe(
      `## Marcador sintético da fase\n\n${STAGE_RULE_TEXT}${mobileFlowSystemPolicy}`,
    )
  })

  it('sem regra lida (lista vazia): o prompt inteiro da view é o que chega ao bloco estável do Flow', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    const viewPrompt = `## Marcador sintético da fase\n\n${STAGE_RULE_TEXT}`
    const h = harness({
      channel: 'flow',
      profile: GAIN_PROFILE,
      text: NEUTRAL_TEXT,
      rules: [],
      viewPrompt,
      script: [{ content: MODEL_ANSWER }],
    })
    await flow(h, NEUTRAL_TEXT)

    const [stable] = systemBlocks(h.llmCalls[0])
    expect(stable?.text).toBe(`${viewPrompt}${mobileFlowSystemPolicy}`)
  })
})

// ── 4. Declared pendencies ──────────────────────────────────────────────────

describe('audit 2026-10-09 C26a — pendências declaradas', () => {
  it('every "RC C26a" line of this header is in docs/CALCULO-MPP.md §10r, identical and in the same order', () => {
    const header = readFileSync(fileURLToPath(import.meta.url), 'utf8')
    const doc = readFileSync(resolve(HERE, '../../../../docs/CALCULO-MPP.md'), 'utf8')
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC C26a — .*)$/gm), (match) => match[1])
    const fromDoc = Array.from(doc.matchAll(/^(> RC C26a — .*)$/gm), (match) => match[1])
    expect(fromHeader).toHaveLength(9)
    expect(fromDoc).toEqual(fromHeader)
    for (const line of fromHeader) {
      expect(line).toMatch(
        /^> RC C26a — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-09\)$/,
      )
    }
  })

  it('the 24 "RC E" lines of §10j are still 24 (this change does not touch them)', () => {
    const doc = readFileSync(resolve(HERE, '../../../../docs/CALCULO-MPP.md'), 'utf8')
    expect(Array.from(doc.matchAll(/^> RC E — .*$/gm))).toHaveLength(24)
  })
})
