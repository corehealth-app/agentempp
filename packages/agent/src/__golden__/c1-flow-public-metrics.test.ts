/** C1: exact Flow questions and projections, real pipeline with synthetic external boundaries. */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import { projectFlowMetricAnswer, projectFlowMetricContext } from '../flow-public-metrics.js'
import type { PipelineDeps } from '../pipeline.js'
import { processAuthenticatedMessage, processMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import { consultaMetricas } from '../tools.js'

const PHRASE = 'O treino de hoje aumenta minha meta de calorias?'
/** Last exact readout of the QA account that day (audit RC A). */
const NOW = new Date('2026-10-04T15:03:40.503Z')
const USER_ID = 'qa-a'
const TURN_ID = 'mobile_flow/qa-a/perf-turn'
const MODEL = 'anthropic/claude-sonnet-4.6'

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
  profile?: Row
  progress?: Row | null
  closedDays?: Row[]
  prompt?: string
  rag?: string
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
        return fixture.profile ?? PROFILE
      case 'user_progress':
        return fixture.progress === undefined ? PROGRESS : fixture.progress
      case 'messages': {
        messageReads.push({ provider: read.filters.provider ?? null, limit: read.limit })
        const rows = stored
          .filter((row) => read.filters.provider == null || row.provider === read.filters.provider)
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
        return read.limit == null ? rows : rows.slice(0, read.limit)
      }
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return fixture.closedDays ?? []
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
          system_prompt: fixture.prompt ?? 'REGRAS COMPARTILHADAS',
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
        data:
          name === 'match_method_chunks'
            ? fixture.rag
              ? [{ page_title: 'Regra', content: fixture.rag }]
              : []
            : USER_ID,
        error: null,
      }
    },
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

  return {
    deps: {
      supabase,
      llm,
      maxToolIterations: 3,
      ...(fixture.rag
        ? { embeddings: { embed: async () => [1] } as unknown as PipelineDeps['embeddings'] }
        : {}),
    },
    inserts,
    llmCalls,
    messageReads,
  }
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

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})
afterEach(() => vi.useRealTimers())

const PUBLIC_TARGETS =
  'As metas oficiais de hoje são 2.980 kcal e 144 g de proteína. Você pode acompanhá-las em Hoje.'
const FORBIDDEN = /\b(?:BMR|TMB|TDEE|LBM|Katch|Mifflin)\b|metabolismo basal|fator de atividade/i

function firstCall(h: Harness): LlmCall {
  const call = h.llmCalls[0]
  if (!call) throw new Error('Expected a model call in this scenario')
  return call
}

function systemText(h: Harness) {
  const prompt = h.llmCalls[0]?.systemPrompt
  return typeof prompt === 'string'
    ? prompt
    : (prompt as Array<{ text: string }>).map((b) => b.text).join('\n')
}

/** C3/C4: this same stored text must be safe in every public Flow boundary. */
const OBJECTIVE_PRESENTATION_FIXTURE = [
  'Evite amendoim por sua alergia.',
  'Consumido: 541 / 2.980 kcal (18%)',
  'Restam para comida: 2.439 kcal',
  'Proteína: 59.0 / 144g (41%)',
  'Exercício: 322 kcal',
  'Bloco 7700: 3.120 / 7.700 kcal (41%)',
  '4 bloco(s) de 7.700 completo(s)',
  'Orçamento 14d: 5.850 / 5.960 kcal (98%) · DAM: 1/2',
  'Reavaliação em 14 dias.',
  'Arroz: 150 g, 195 kcal.',
  'Revisar sugestão',
].join('\n')

describe('C3/C4 — general Flow objective presentation', () => {
  const objectives = ['recomposicao', 'ganho_massa', 'manutencao', null] as const
  const progress = Object.freeze({ ...PROGRESS, xp_total: 1240, level: 2,
    current_streak: 3, longest_streak: 7, blocks_completed: 4, deficit_block: 3120,
    badges_earned: Object.freeze(['Primeiro Bloco', 'Primeira Semana', 'XP Master']) })
  const closedDays = [
    { date: '2026-10-02', calories_consumed: 3100, calories_target: 2980, day_closed: true },
    { date: '2026-10-03', calories_consumed: 2750, calories_target: 2980, day_closed: true },
  ]
  it.each(objectives)('filters structured progress and factual context for %s without changing historical energy', async (currentProtocol) => {
    const text = 'Tenho alergia a amendoim e reavaliação em 14 dias. Explique meus dados.'
    const day: Readonly<Row> = Object.freeze({ ...S541, current_protocol: 'ganho_massa', deficit_accumulated: 3120 })
    const h = harness({ text, day, progress, closedDays,
      profile: { ...PROFILE, current_protocol: currentProtocol },
      script: [
        { content: OBJECTIVE_PRESENTATION_FIXTURE, toolCalls: [{ id: 'progress-1', name: 'consulta_progresso', arguments: '{}' }] },
        { content: 'Evite amendoim. Reavaliação em 14 dias.' },
      ],
    })
    await flow(h, text)
    const lastCall = h.llmCalls.at(-1)
    const toolReply = lastCall?.messages.find((m) => m.role === 'tool')
    expect(toolReply).toBeDefined()
    const { daily_balance: _legacy, deficit_accumulated: _block, ...publicDay } = day
    const expectedProgress = { xp: 1240, nivel: 2, sequencia_dias_consecutivos: 3,
      recorde_sequencia: 7, conquistas: ['Primeira Semana', 'XP Master'],
      ...(currentProtocol === 'recomposicao' ? {
        blocos_7700_completos: 4, deficit_no_bloco_atual: 3120,
        conquistas: ['Primeiro Bloco', 'Primeira Semana', 'XP Master'],
      } : {}),
    }
    expect(JSON.parse(toolReply?.content ?? '')).toEqual({
      progresso: expectedProgress,
      hoje: currentProtocol === 'recomposicao' ? { ...publicDay, deficit_accumulated: 3120 } : publicDay,
      energia_hoje: {
        meta_kcal: 2980, consumido_kcal: 541, restam_para_comida_kcal: 2439,
        exercicio_kcal: 322, gasto_de_referencia_kcal: 2838, balanco_do_dia_sem_exercicio_kcal: -2297,
        regra: 'Exercício não libera comida nem apaga excedente: a meta é a mesma com ou sem treino e o que resta para comida é meta − consumido, sem exercício. O gasto do treino fica à parte; balanco_do_dia_sem_exercicio_kcal é consumido − gasto_de_referencia_kcal (negativo = déficit, positivo = superávit): o exercício já está considerado neste valor e não é somado. Não é o que resta para comer.',
      },
    })
    const context = systemText(h)
    expect(context).toContain('XP: 1240 (nível 2)')
    expect(context).toContain('3 dias consecutivos (recorde 7)')
    expect(context).not.toMatch(/Orçamento 14 dias:|5850 kcal|5960 kcal|DAM: 1\/2/)
    if (currentProtocol !== 'recomposicao') expect(context).not.toMatch(/3120|Blocos 7700 fechados/)
    for (const call of h.llmCalls) {
      expect(call.messages).toContainEqual({ role: 'user', content: text })
      const copies = call.messages.filter((m) => m.role === 'assistant').map((m) => m.content).join('\n')
      expect(copies).not.toMatch(/Orçamento 14d:|DAM: 1\/2|5\.850|5\.960/)
      if (currentProtocol !== 'recomposicao') expect(copies).not.toContain('3.120')
    }
    expect(day.deficit_accumulated).toBe(3120)
    expect(progress.badges_earned).toEqual(['Primeiro Bloco', 'Primeira Semana', 'XP Master'])
  })

  it.each(objectives)('projects the final reconstructed answer for %s', async (currentProtocol) => {
    const text = 'Tenho alergia a amendoim. Explique minhas informações.'
    const h = harness({ text, progress, profile: { ...PROFILE, current_protocol: currentProtocol },
      script: [{ content: OBJECTIVE_PRESENTATION_FIXTURE }] })
    const output = await flow(h, text)
    const kept = [
      'Evite amendoim por sua alergia.', 'Consumido: 541 / 2.980 kcal (18%)',
      'Restam para comida: 2.439 kcal', 'Proteína: 59.0 / 144g (41%)', 'Exercício: 322 kcal',
      ...(currentProtocol === 'recomposicao' ? ['Bloco 7700: 3.120 / 7.700 kcal (41%)', '4 bloco(s) de 7.700 completo(s)'] : []),
      'Reavaliação em 14 dias.', 'Arroz: 150 g, 195 kcal.', 'Revisar sugestão',
    ].join('\n')
    const explanation = currentProtocol === 'ganho_massa' || currentProtocol === 'manutencao'
      ? '\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.' : ''
    expect(output.text).toBe(kept + explanation)
    expect(h.inserts.filter((e) => e.table !== 'product_events')).toEqual([])
  })

  it('does not ask a gain account to report block figures after a premature-completion retry', async () => {
    const text = 'Tenho alergia a amendoim. Explique meu progresso.'
    const h = harness({ text, script: [
      { content: 'Seu bloco 7700 fechou hoje! Bloco 7700: 3120 kcal. Evite amendoim.' },
      { content: 'Evite amendoim. Reavaliação em 14 dias.' },
    ] })
    expect((await flow(h, text)).text).toBe('Evite amendoim. Reavaliação em 14 dias.')
    expect(h.llmCalls).toHaveLength(2)
    const retry = h.llmCalls[1]?.messages.at(-1)?.content ?? ''
    expect(retry).not.toMatch(/X \/ 7\.700|Y%|faltam Z|Reporte o bloco/)
    const copied = h.llmCalls[1]?.messages.filter((m) => m.role === 'assistant').map((m) => m.content).join('\n') ?? ''
    expect(copied).toContain('Evite amendoim.')
    expect(copied).not.toContain('3120')
  })

  it.each(['recomposicao', 'ganho_massa', 'manutencao', null])(
    'projects rules, RAG, summary and assistant copies for the current objective %s',
    async (currentProtocol) => {
      const text = 'Meu bloco 7700 está em 3120? Tenho alergia a amendoim e reavaliação em 14 dias.'
      const profile = Object.freeze({ ...PROFILE, current_protocol: currentProtocol })
      const source = Object.freeze({ ...USER, summary: OBJECTIVE_PRESENTATION_FIXTURE })
      const h = harness({
        text,
        profile,
        user: source,
        prompt: OBJECTIVE_PRESENTATION_FIXTURE,
        rag: OBJECTIVE_PRESENTATION_FIXTURE,
        history: [{
          direction: 'out',
          content: OBJECTIVE_PRESENTATION_FIXTURE,
          created_at: '2026-10-04T14:01:00Z',
        }],
        script: [{ content: 'Evite amendoim por sua alergia. Reavaliação em 14 dias.' }],
      })
      await flow(h, text)
      const context = systemText(h)
      // C4 remains withheld in recomposition too; this is not a formula change.
      expect(context).not.toMatch(/Orçamento 14d:|DAM: 1\/2|5\.850|5\.960/)
      expect(context).toContain('Evite amendoim por sua alergia.')
      expect(context).toContain('Reavaliação em 14 dias.')
      expect(context).toContain('Arroz: 150 g, 195 kcal.')
      expect(context).toContain('Restam para comida: 2.439 kcal')
      expect(context).toContain('Exercício: 322 kcal')
      for (const call of h.llmCalls) {
        expect(call.messages).toContainEqual({ role: 'user', content: text })
        const assistant = call.messages.filter((m) => m.role === 'assistant').map((m) => m.content).join('\n')
        expect(assistant).not.toMatch(/Orçamento 14d:|DAM: 1\/2|5\.850|5\.960/)
        expect(assistant).toContain('Evite amendoim por sua alergia.')
        if (currentProtocol !== 'recomposicao') expect(assistant).not.toContain('3.120')
      }
      if (currentProtocol === 'recomposicao') expect(context).toContain('3.120 / 7.700 kcal (41%)')
      else expect(context).not.toContain('3.120')
      expect(profile.current_protocol).toBe(currentProtocol)
      expect(source.summary).toBe(OBJECTIVE_PRESENTATION_FIXTURE)
      expect(h.inserts.filter((e) => e.table !== 'product_events')).toEqual([])
    },
  )
})

describe('C1 — public Flow metrics', () => {
  it.each([
    'BMR: estimado em 1836 kcal.',
    'BMR — estimado em 1836 kcal.',
    'Lean body mass: estimated at 68 kg.',
    'Lean body mass — estimated at 68 kg.',
  ])('keeps estimated values bound to private labels: %s', async (content) => {
    const h = harness({ text: 'Como estou?', script: [{ content: content + ' Evite amendoim.' }] })
    expect((await flow(h, 'Como estou?')).text).toBe('Evite amendoim.')
    expect(projectFlowMetricContext(content + ' Evite amendoim.')).not.toMatch(/1836|68/)
  })

  it.each([
    'BMR — 1836 kcal.',
    'Fator de atividade - 1,55.',
  ])('keeps a private label and numeric value together across a dash: %s', async (content) => {
    const h = harness({ text: 'Como estou?', script: [{ content }] })
    expect((await flow(h, 'Como estou?')).text).toBe(PUBLIC_TARGETS)
  })

  it.each([
    'Alergia a amendoim: Sua massa magra é 68 kg.',
    'Alergia a amendoim: fator de atividade 1,55.',
  ])('preserves any public prefix before a recognized technical clause: %s', async (content) => {
    expect(projectFlowMetricContext(content)).toBe(
      'Alergia a amendoim: [referência interna omitida]',
    )
    const h = harness({ text: 'Como estou?', script: [{ content }] })
    expect((await flow(h, 'Como estou?')).text).toBe('Alergia a amendoim')
  })
  it('omits English activity table coefficients without dropping public quantities', async () => {
    const h = harness({
      text: 'How am I doing?',
      user: { ...USER, locale: 'en' },
      script: [{ content: 'Activity factors: sedentary 1.2 and moderate 1.55.' }],
    })
    expect((await flow(h, 'How am I doing?')).text).toBe(
      'Today’s official targets are 2,980 kcal and 144 g of protein. You can follow them in Today.',
    )
    expect(
      projectFlowMetricContext('Activity factors: sedentary 1.2 and moderate 1.55.'),
    ).not.toMatch(/1[.,](?:2|55)/)
  })

  it.each([
    'Leve 1,5 L de água para o treino.',
    'Almoço leve: 1,5 g de gordura.',
  ])('does not mistake public quantities for an activity factor: %s', async (content) => {
    const h = harness({ text: 'Como estou?', script: [{ content }] })
    expect((await flow(h, 'Como estou?')).text).toBe(content)
  })
  it('preserves an allergy before a metric across a colon in summary and answer', async () => {
    const content = 'Alergia a amendoim: BMR 1836 kcal.'
    expect(projectFlowMetricContext(content)).toBe(
      'Alergia a amendoim: [referência interna omitida]',
    )
    const h = harness({ text: 'Como estou?', script: [{ content }] })
    expect((await flow(h, 'Como estou?')).text).toBe('Alergia a amendoim')
  })

  it.each([
    'Sua meta é calculada por 10 × peso + 6,25 × altura − 5 × idade + 5, vezes 1,55.',
    'Sua massa magra estimada é 68 kg.',
    'Your lean body mass is 68 kg.',
    'Seu gasto total diário é 2754 kcal.',
    'Sua massa magra é 68 kg.',
    'Fatores de atividade: sedentário 1,2 e moderado 1,55.',
  ])('blocks additional technical assertions without exposing their numbers: %s', async (content) => {
    const h = harness({ text: 'Explique o plano.', script: [{ content }] })
    expect((await flow(h, 'Explique o plano.')).text).toBe(PUBLIC_TARGETS)
  })

  it.each([
    'Meta = BMR × 1,2 − 500. Alergia a amendoim.',
    'Seu BMR estimado é 1836 kcal e evite amendoim.',
    'Alergia a amendoim (BMR: 1836 kcal).',
  ])('removes complete calculations in prompt copies, preserving adjacent restrictions: %s', (text) => {
    const projected = projectFlowMetricContext(text)
    expect(projected).toContain('amendoim')
    expect(projected).not.toMatch(/1836|1,2|500|BMR/)
  })

  it.each([
    'Seu BMR é 1836 kcal — evite amendoim por sua alergia.',
    'Seu BMR é 1836 kcal: evite amendoim por sua alergia.',
  ])('preserves restrictions after a dash or colon: %s', async (content) => {
    const h = harness({ text: 'Como estou?', script: [{ content }] })
    const output = await flow(h, 'Como estou?')
    expect(output.text).toBe('evite amendoim por sua alergia.')
    expect(output.text).not.toMatch(/BMR|1836/)
  })

  it('preserves an allergy before a metric across a dash in the summary', () => {
    expect(projectFlowMetricContext('Alergia a amendoim — BMR: 1836 kcal.')).toBe(
      'Alergia a amendoim — [referência interna omitida]',
    )
  })

  it('preserves public information and an allergy in the same sentence as a private metric', async () => {
    const h = harness({
      text: 'Como estou?',
      script: [
        {
          content:
            'Seu BMR é 1836 kcal e faltam 84,97 g de proteína, mas evite amendoim por sua alergia.',
        },
      ],
    })
    const output = await flow(h, 'Como estou?')
    expect(output.text).toContain('faltam 84,97 g de proteína')
    expect(output.text).toContain('evite amendoim por sua alergia')
    expect(output.text).not.toMatch(/BMR|1836/)
  })

  it.each([
    [
      'Which formula do you use?',
      'pt-BR',
      'Today’s official targets are 2,980 kcal and 144 g of protein. You can follow them in Today.',
    ],
    ['qual fórmula você usa?', 'en', PUBLIC_TARGETS],
  ])('follows the current question language independently of account locale: %s', async (text, locale, expected) => {
    const h = harness({ text, user: { ...USER, locale } })
    expect((await flow(h, text)).text).toBe(expected)
    expect(h.llmCalls).toHaveLength(0)
  })

  it.each([
    ['Seu BF está em 15%.', 'Sua gordura corporal está em 15%.'],
    ['O BF atual é 15%.', 'A gordura corporal atual é 15%.'],
    ['BF%: 15', 'Gordura corporal: 15%'],
  ])('preserves percent meaning when replacing the acronym: %s', async (content, expected) => {
    const h = harness({ text: 'Explique o perfil.', script: [{ content }] })
    expect((await flow(h, 'Explique o perfil.')).text).toBe(expected)
  })

  it('preserves suggestion items, quantities and review CTA with a restricted parenthetical', () => {
    const text =
      'Sugestão de cardápio: arroz, 150 g (BMR: 1836 kcal).\nEvite amendoim por sua alergia.\nRevisar sugestão no app.'
    const result = projectFlowMetricAnswer(
      text,
      { calories_target: 2980, protein_target: 144 },
      'pt-BR',
      true,
    )
    expect(result).toContain('arroz, 150 g')
    expect(result).toContain('Evite amendoim por sua alergia.')
    expect(result).toContain('Revisar sugestão no app.')
    expect(result).not.toMatch(/BMR|1836/)
  })

  it.each([
    'qual é o meu BMR?',
    'qual fórmula você usa?',
    'Qual é a minha TMB?',
    'Qual meu TDEE?',
  ])('answers the exact question deterministically: %s', async (text) => {
    const h = harness({ text, script: [{ content: 'Sua taxa basal estimada é de 1.836 kcal.' }] })
    const output = await flow(h, text)
    expect(output.text).toBe(PUBLIC_TARGETS)
    expect(output.promptTokens).toBe(0)
    expect(output.toolCalls).toEqual([])
    expect(h.llmCalls).toHaveLength(0)
    expect(h.inserts.filter((e) => e.table !== 'product_events')).toEqual([])
  })

  it.each([
    'What is my BMR?',
    'Which formula do you use?',
  ])('answers English accounts: %s', async (text) => {
    const h = harness({ text, user: { ...USER, locale: 'en', country: 'US' } })
    const output = await flow(h, text)
    expect(output.text).toBe(
      'Today’s official targets are 2,980 kcal and 144 g of protein. You can follow them in Today.',
    )
    expect(h.llmCalls).toHaveLength(0)
  })

  it('uses the stored day target instead of recomputing the profile', async () => {
    const text = 'qual é o meu BMR?'
    const h = harness({ text, day: { ...S541, calories_target: 2345, protein_target: '121.00' } })
    expect((await flow(h, text)).text).toBe(
      'As metas oficiais de hoje são 2.345 kcal e 121 g de proteína. Você pode acompanhá-las em Hoje.',
    )
    expect(h.llmCalls).toHaveLength(0)
  })

  it('does not invent numbers when targets are unavailable', async () => {
    const text = 'qual fórmula você usa?'
    const h = harness({
      text,
      day: null,
      profile: { ...PROFILE, weight_kg: null, height_cm: null },
    })
    expect((await flow(h, text)).text).toBe(
      'As metas oficiais de hoje ainda não estão disponíveis. Confira os dados do seu objetivo em Perfil.',
    )
    expect(h.llmCalls).toHaveLength(0)
  })

  it('preserves a mixed request and the patient’s words', async () => {
    const text = 'Qual é o meu BMR? E quanto falta de proteína hoje?'
    const h = harness({ text, script: [{ content: 'Faltam 84,97 g de proteína hoje.' }] })
    expect((await flow(h, text)).text).toBe('Faltam 84,97 g de proteína hoje.')
    expect(h.llmCalls).toHaveLength(1)
    expect(firstCall(h).messages.at(-1)).toEqual({ role: 'user', content: text })
  })

  it('omits private numeric context and projects assistant history, summary, rules and RAG without erasing allergies', async () => {
    const text = 'Como estão minhas metas hoje?'
    const h = harness({
      text,
      profile: {
        ...PROFILE,
        user_id: USER_ID,
        onboarding_completed: true,
        onboarding_completed_at: null,
        body_fat_percent: 15,
      },
      user: { ...USER, summary: 'Alergia a amendoim. BMR: 1836 kcal. Prefere arroz.' },
      prompt: 'Use Mifflin-St Jeor. Mantenha a restrição alimentar.',
      rag: 'BMR: 1836 kcal. Não sugerir amendoim.',
      history: [
        {
          direction: 'in',
          content: 'Meu BMR é 1836? Sou alérgico a amendoim.',
          created_at: '2026-10-04T14:00:00Z',
        },
        {
          direction: 'out',
          content: 'BMR: 1836 kcal. Sua meta é 2980 kcal.',
          created_at: '2026-10-04T14:01:00Z',
        },
      ],
    })
    await flow(h, text)
    const context = systemText(h)
    // The policy can name restricted terms to prohibit disclosure; factual blocks cannot.
    expect(context).not.toContain('- BMR estimado:')
    expect(context).not.toContain('- TDEE estimado:')
    expect(context).not.toContain('- LBM (massa magra):')
    expect(context).not.toContain('1836 kcal')
    expect(context).not.toContain('Mifflin-St Jeor')
    expect(context).toContain('- Gordura corporal: 15%')
    expect(context).toContain('Alergia a amendoim.')
    expect(context).toContain('Prefere arroz.')
    expect(context).toContain('Não sugerir amendoim.')
    expect(
      firstCall(h)
        .messages.filter((m) => m.role === 'assistant')
        .map((m) => m.content)
        .join('\n'),
    ).not.toMatch(FORBIDDEN)
    expect(firstCall(h).messages).toContainEqual({
      role: 'user',
      content: 'Meu BMR é 1836? Sou alérgico a amendoim.',
    })
    expect(h.inserts.filter((e) => e.table === 'messages')).toEqual([])
  })

  it.each([
    'BMR: 1.836 kcal. Sua meta é 2.980 kcal.',
    'TDEE: 2.754 kcal; Sua meta é 2.980 kcal.',
    'A fórmula usada é Katch-McArdle. Sua meta é 2.980 kcal.',
    'Seu metabolismo basal é 1836 kcal. Sua meta é 2.980 kcal.',
    'The activity factor is 1.5. Sua meta é 2.980 kcal.',
  ])('removes only the restricted statement from the final response: %s', async (content) => {
    const h = harness({ text: 'Me explique o plano.', script: [{ content }] })
    const output = await flow(h, 'Me explique o plano.')
    expect(output.text).toBe('Sua meta é 2.980 kcal.')
    expect(output.text).not.toMatch(FORBIDDEN)
    expect(output.text).not.toContain('1.836')
    expect(output.promptTokens).toBe(7400)
  })

  it('renames BF while preserving the exact percentage and unrelated formula words', async () => {
    const h = harness({
      text: 'Explique meu perfil.',
      script: [{ content: 'BF: 15,5%. Confira o rótulo da fórmula infantil.' }],
    })
    expect((await flow(h, 'Explique meu perfil.')).text).toBe(
      'Gordura corporal: 15,5%. Confira o rótulo da fórmula infantil.',
    )
  })

  it('exposes only public fields in the Flow metrics tool, with official snapshot targets', async () => {
    const h = harness()
    const result = await consultaMetricas.execute(
      {},
      {
        supabase: h.deps.supabase,
        userId: USER_ID,
        userWpp: '',
        assistantIdentity: 'flow',
        referenceTimestamp: NOW,
        flowDailyTargets: { calories_target: 2345, protein_target: 121 },
      },
    )
    expect(result).toEqual({
      age_years: 26,
      imc: 23.5,
      body_fat_percent: null,
      calories_target_today: 2345,
      protein_target_today_g: 121,
    })
  })

  it('does not advertise private fields in the Flow tool schema', async () => {
    const h = harness({ text: 'Quanto de proteína devo comer?' })
    await flow(h, 'Quanto de proteína devo comer?')
    const metric = firstCall(h).tools.find((t) => JSON.stringify(t).includes('consulta_metricas'))
    expect(JSON.stringify(metric)).not.toMatch(FORBIDDEN)
    expect(JSON.stringify(metric)).toContain('meta')
  })

  it('keeps the legacy metrics payload exactly unchanged', async () => {
    const h = harness({ channel: 'whatsapp' })
    expect(
      await consultaMetricas.execute(
        {},
        { supabase: h.deps.supabase, userId: USER_ID, userWpp: '', referenceTimestamp: NOW },
      ),
    ).toEqual({
      age_years: 26,
      bmr_kcal: 1836,
      tdee_kcal: 2846,
      imc: 23.5,
      lbm_kg: 80.5,
      calories_target_today: 2988,
      protein_target_today_g: 144.9,
      activity_factor: 1.55,
      formula_used: 'Mifflin-St Jeor',
    })
  })

  it('keeps the legacy question and answer on the model path', async () => {
    const text = 'qual é o meu BMR?'
    const h = harness({
      channel: 'whatsapp',
      text,
      script: [{ content: 'Seu BMR estimado é 1.836 kcal.' }],
    })
    expect((await whatsapp(h, text)).text).toBe('Seu BMR estimado é 1.836 kcal.')
    expect(h.llmCalls).toHaveLength(1)
    expect(systemText(h)).toContain('- BMR estimado: 1836 kcal')
  })
})
