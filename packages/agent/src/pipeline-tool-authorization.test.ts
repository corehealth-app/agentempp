import { afterEach, describe, expect, it, vi } from 'vitest'
import type { PipelineDeps } from './pipeline.js'
import {
  authorizeToolCall,
  fakeWriteRetryAllowed,
  MOBILE_FLOW_READ_ONLY_TOOLS,
  processAuthenticatedMessage,
  processMessage,
  selectPipelineTools,
} from './pipeline.js'
import {
  consultaMetricas,
  consultaProgresso,
  deleteUser,
  geraDieta,
  geraTreino,
  propoePlanoTreino,
  registraRefeicao,
} from './tools.js'

// A provider response is scripted per test: the model "asks" for tools by
// name and the pipeline must decide, at the dispatch boundary, what runs.
// No paid LLM call, no network, no staging.

type QueryResult = { data: unknown; error: null }

interface Recorded {
  inserts: Array<{ table: string; row: unknown }>
  rpcs: string[]
  calls?: unknown[][]
}

type Query = Promise<QueryResult> & Record<string, unknown>

function makeQuery(table: string, rows: unknown, recorded: Recorded): Query {
  const query = Promise.resolve({ data: rows, error: null }) as Query
  const chain = () => query
  const singleRow = () => (Array.isArray(rows) ? (rows[0] ?? null) : rows)
  for (const method of ['select', 'eq', 'neq', 'gte', 'lte', 'lt', 'gt', 'in', 'is', 'like', 'ilike', 'or', 'order', 'limit', 'update', 'upsert', 'delete', 'not']) {
    query[method] = chain
  }
  query.insert = (row: unknown) => {
    recorded.inserts.push({ table, row })
    return query
  }
  query.single = async () => ({ data: singleRow(), error: null })
  query.maybeSingle = async () => ({ data: singleRow(), error: null })
  return query
}

interface ScriptedCall {
  toolCalls: Array<{ id: string; name: string; arguments: string }>
  content?: string
}

function makeDeps(script: ScriptedCall[], allowedTools: string[] | null, recorded: Recorded): PipelineDeps {
  const rowsByTable: Record<string, unknown> = {
    users: {
      id: 'fixture-user',
      name: 'Pessoa sintética',
      summary: null,
      last_active_at: null,
      country: 'BR',
      country_confirmed: true,
      country_detected_from_wpp: null,
      locale: 'pt-BR',
      metadata: null,
      timezone: 'America/Sao_Paulo',
    },
    user_profiles: {
      sex: null,
      birth_date: null,
      height_cm: null,
      weight_kg: null,
      body_fat_percent: null,
      activity_level: null,
      training_frequency: null,
      water_intake: null,
      hunger_level: null,
      current_protocol: 'manutencao',
      goal_type: null,
      goal_value: null,
      deficit_level: null,
    },
    messages: [],
    daily_snapshots: [],
    user_progress: {
      current_streak: 0,
      longest_streak: 0,
      xp_total: 0,
      level: 1,
      blocks_completed: 0,
      deficit_block: 0,
      last_active_date: null,
    },
    product_events: [],
    v_active_prompts: {
      stage: 'manutencao',
      model: 'openai/test-model',
      temperature: 0,
      max_tokens: 64,
      system_prompt: 'Contexto sintético.',
      allowed_tools: allowedTools,
    },
    agent_rules: [],
    global_config: [],
    pending_registrations: [],
  }
  const supabase = {
    from: (table: string) => makeQuery(table, rowsByTable[table] ?? [], recorded),
    rpc: async (name: string) => {
      recorded.rpcs.push(name)
      return { data: name === 'match_method_chunks' ? [] : 'fixture-user', error: null }
    },
  } as unknown as PipelineDeps['supabase']
  let call = 0
  const llm = {
    complete: async (input: { messages?: unknown[] }) => {
      recorded.calls = recorded.calls ?? []
      recorded.calls.push(JSON.parse(JSON.stringify(input.messages ?? [])))
      const step = script[Math.min(call, script.length - 1)] ?? { toolCalls: [] }
      call += 1
      return {
        content: step.content ?? '',
        toolCalls: step.toolCalls,
        model: 'openai/test-model',
        promptTokens: 1,
        completionTokens: 1,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']
  return { supabase, llm, maxToolIterations: 4 }
}

function toolCall(id: string, name: string, args: Record<string, unknown> = {}) {
  return { id, name, arguments: JSON.stringify(args) }
}

// Valid for the tools' own schemas, so only authorization can stop them.
const healthArguments = { weight_kg: 81.4, restrictions: ['lactose'], note: 'dado sensível' }
const trainingArguments = {
  available_equipment: ['halteres'],
  location: 'casa',
  days_per_week: 3,
  training_level: 'iniciante',
  limitations: ['dor no joelho'],
}

function spyExecutes() {
  const stub = async () => ({ success: true, stub: true })
  return {
    geraTreino: vi.spyOn(geraTreino, 'execute').mockImplementation(stub),
    geraDieta: vi.spyOn(geraDieta, 'execute').mockImplementation(stub),
    registraRefeicao: vi.spyOn(registraRefeicao, 'execute').mockImplementation(stub),
    deleteUser: vi.spyOn(deleteUser, 'execute').mockImplementation(stub),
    consultaMetricas: vi.spyOn(consultaMetricas, 'execute').mockImplementation(stub),
    consultaProgresso: vi.spyOn(consultaProgresso, 'execute').mockImplementation(stub),
  }
}

function mobileMessage(deps: PipelineDeps) {
  return processAuthenticatedMessage(deps, {
    userId: 'fixture-user',
    providerMessageId: 'mobile_flow/fixture-user/key-0001',
    text: 'Monte meu treino e minha dieta agora.',
    timestamp: new Date('2026-09-27T12:00:00.000Z'),
  })
}

function deniedEvents(recorded: Recorded) {
  return recorded.inserts
    .filter((entry) => entry.table === 'product_events')
    .map((entry) => entry.row as { event: string; properties: Record<string, unknown> })
    .filter((row) => row.event === 'pipeline.tool_call_denied')
}

afterEach(() => {
  vi.restoreAllMocks()
})

describe('tool authorization at the dispatch boundary', () => {
  it('mobile Flow refuses gera_treino and gera_dieta by name with zero execution and zero writes', async () => {
    const spies = spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        {
          toolCalls: [
            toolCall('call-1', 'gera_treino', trainingArguments),
            toolCall('call-2', 'gera_dieta', healthArguments),
          ],
        },
        { toolCalls: [], content: 'Para criar um plano, use o fluxo de confirmação do app.' },
      ],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(spies.geraTreino).not.toHaveBeenCalled()
    expect(spies.geraDieta).not.toHaveBeenCalled()
    expect(recorded.rpcs).not.toContain('save_training_plan_atomic')
    const writtenTables = recorded.inserts.map((entry) => entry.table)
    expect(writtenTables).not.toContain('training_plans')
    expect(writtenTables).not.toContain('prescriptions')
    expect(output.toolCalls.filter((tc) => tc.name.startsWith('gera_'))).toEqual([
      { name: 'gera_treino', arguments: {}, error: 'tool_not_authorized' },
      { name: 'gera_dieta', arguments: {}, error: 'tool_not_authorized' },
    ])
  })

  it('mobile Flow runs the proposal tool and still refuses gera_treino in the same turn', async () => {
    const spies = spyExecutes()
    const propose = vi
      .spyOn(propoePlanoTreino, 'execute')
      .mockImplementation(async () => ({ success: true, draft_id: 'draft-1', domain: 'training' }))
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        {
          toolCalls: [
            toolCall('call-1', 'propoe_plano_treino', trainingArguments),
            toolCall('call-2', 'gera_treino', trainingArguments),
          ],
        },
        { toolCalls: [], content: 'Sua proposta está pronta para revisão no app.' },
      ],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(propose).toHaveBeenCalledTimes(1)
    expect(propose.mock.calls[0]?.[1]).toMatchObject({
      userId: 'fixture-user',
      providerMessageId: 'mobile_flow/fixture-user/key-0001',
      assistantIdentity: 'flow',
    })
    expect(spies.geraTreino).not.toHaveBeenCalled()
    expect(recorded.rpcs).not.toContain('save_training_plan_atomic')
    expect(recorded.rpcs.filter((name) => /confirm/i.test(name))).toEqual([])
    expect(output.toolCalls).toContainEqual({
      name: 'gera_treino',
      arguments: {},
      error: 'tool_not_authorized',
    })
    expect(output.text).toBe('Sua proposta está pronta para revisão no app.')
  })

  it('WhatsApp refuses the proposal tools by name', async () => {
    const propose = vi
      .spyOn(propoePlanoTreino, 'execute')
      .mockImplementation(async () => ({ success: true }))
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        { toolCalls: [toolCall('call-1', 'propoe_plano_treino', trainingArguments)] },
        { toolCalls: [], content: 'Certo.' },
      ],
      null,
      recorded,
    )

    const output = await processMessage(deps, {
      from: '5511999990000',
      providerMessageId: 'wamid.fixture-1',
      text: 'Monte meu treino.',
      contentType: 'text',
      provider: 'whatsapp_cloud',
      timestamp: new Date('2026-09-27T12:00:00.000Z'),
    })

    expect(propose).not.toHaveBeenCalled()
    expect(recorded.rpcs).not.toContain('create_plan_draft_atomic')
    expect(output.toolCalls).toContainEqual({
      name: 'propoe_plano_treino',
      arguments: {},
      error: 'tool_not_authorized',
    })
  })

  it('mobile Flow refuses a write tool before the deferred-pending path can run', async () => {
    const spies = spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        {
          toolCalls: [
            toolCall('call-1', 'registra_refeicao', {
              meal_type: 'almoco',
              items: [{ food_name: 'arroz', quantity_g: 120 }],
            }),
          ],
        },
        { toolCalls: [], content: 'Registre pelo fluxo do app.' },
      ],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(spies.registraRefeicao).not.toHaveBeenCalled()
    expect(recorded.rpcs).not.toContain('replace_pending_registration_atomic')
    expect(recorded.inserts.map((entry) => entry.table)).not.toContain('pending_registrations')
    expect(recorded.inserts.map((entry) => entry.table)).not.toContain('meal_logs')
    expect(output.toolCalls).toContainEqual({
      name: 'registra_refeicao',
      arguments: {},
      error: 'tool_not_authorized',
    })
  })

  it('an authorized mobile read tool still runs', async () => {
    const spies = spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        { toolCalls: [toolCall('call-1', 'consulta_metricas')] },
        { toolCalls: [], content: 'Aqui estão suas métricas.' },
      ],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(spies.consultaMetricas).toHaveBeenCalledTimes(1)
    expect(output.toolCalls).toContainEqual(
      expect.objectContaining({ name: 'consulta_metricas', result: { success: true, stub: true } }),
    )
    expect(deniedEvents(recorded)).toEqual([])
  })

  it('a known tool the configuration withdrew does not run, even inside the channel set', async () => {
    const spies = spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        {
          toolCalls: [
            toolCall('call-1', 'consulta_metricas'),
            toolCall('call-2', 'consulta_progresso'),
          ],
        },
        { toolCalls: [], content: 'ok' },
      ],
      ['consulta_progresso'],
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(spies.consultaMetricas).not.toHaveBeenCalled()
    expect(spies.consultaProgresso).toHaveBeenCalledTimes(1)
    expect(output.toolCalls).toContainEqual({
      name: 'consulta_metricas',
      arguments: {},
      error: 'tool_not_authorized',
    })
  })

  it('an unknown tool name fails in a controlled way and the turn completes', async () => {
    spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        { toolCalls: [toolCall('call-1', 'apaga_tudo', healthArguments)] },
        { toolCalls: [], content: 'Não posso fazer isso.' },
      ],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(output.text).toContain('Não posso fazer isso.')
    expect(output.toolCalls).toContainEqual({ name: 'apaga_tudo', arguments: {}, error: 'tool_unknown' })
  })

  it('repeated and batched calls across iterations never get through', async () => {
    const spies = spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        {
          toolCalls: [
            toolCall('call-1', 'gera_treino', trainingArguments),
            toolCall('call-2', 'consulta_metricas'),
            toolCall('call-3', 'gera_treino', trainingArguments),
          ],
        },
        {
          toolCalls: [
            toolCall('call-4', 'gera_treino', trainingArguments),
            toolCall('call-5', 'delete_user'),
            toolCall('call-6', 'GERA_TREINO', trainingArguments),
          ],
        },
        { toolCalls: [], content: 'ok' },
      ],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(spies.geraTreino).not.toHaveBeenCalled()
    expect(spies.deleteUser).not.toHaveBeenCalled()
    expect(spies.consultaMetricas).toHaveBeenCalledTimes(1)
    const denied = output.toolCalls.filter((tc) => tc.error)
    expect(denied.map((tc) => [tc.name, tc.error])).toEqual([
      ['gera_treino', 'tool_not_authorized'],
      ['gera_treino', 'tool_not_authorized'],
      ['gera_treino', 'tool_not_authorized'],
      ['delete_user', 'tool_not_authorized'],
      ['GERA_TREINO', 'tool_unknown'],
    ])
  })

  it('denial telemetry carries the tool name, reason and channel but never the arguments', async () => {
    spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        { toolCalls: [toolCall('call-1', 'gera_dieta', healthArguments)] },
        { toolCalls: [], content: 'ok' },
      ],
      null,
      recorded,
    )

    await mobileMessage(deps)

    const events = deniedEvents(recorded)
    expect(events).toHaveLength(1)
    expect(events[0]?.properties).toEqual({
      tool: 'gera_dieta',
      reason: 'tool_not_authorized',
      channel: 'mobile_flow',
    })
    const serialized = JSON.stringify(recorded.inserts)
    expect(serialized).not.toContain('81.4')
    expect(serialized).not.toContain('lactose')
    expect(serialized).not.toContain('dado sensível')
  })

  it('WhatsApp keeps exactly its configured tools: configured ones run, the rest do not', async () => {
    const spies = spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        {
          toolCalls: [
            toolCall('call-1', 'consulta_metricas'),
            toolCall('call-2', 'gera_treino', trainingArguments),
          ],
        },
        { toolCalls: [], content: 'ok' },
      ],
      ['consulta_metricas', 'registra_refeicao'],
      recorded,
    )

    const output = await processMessage(deps, {
      from: 'fixture-sender',
      providerMessageId: 'wamid.fixture-1',
      text: 'Como estou?',
      contentType: 'text',
      provider: 'whatsapp_cloud',
      timestamp: new Date('2026-09-27T12:00:00.000Z'),
    })

    expect(spies.consultaMetricas).toHaveBeenCalledTimes(1)
    expect(spies.geraTreino).not.toHaveBeenCalled()
    expect(output.toolCalls).toContainEqual({
      name: 'gera_treino',
      arguments: {},
      error: 'tool_not_authorized',
    })
  })

  it('WhatsApp without a configured list keeps its documented all-tools semantics', async () => {
    const spies = spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        { toolCalls: [toolCall('call-1', 'gera_treino', trainingArguments)] },
        { toolCalls: [], content: 'ok' },
      ],
      null,
      recorded,
    )

    await processMessage(deps, {
      from: 'fixture-sender',
      providerMessageId: 'wamid.fixture-2',
      text: 'Pode gerar meu treino.',
      contentType: 'text',
      provider: 'whatsapp_cloud',
      timestamp: new Date('2026-09-27T12:00:00.000Z'),
    })

    expect(spies.geraTreino).toHaveBeenCalledTimes(1)
  })

  it('a fake-write retry never tells a channel to call a tool it cannot run', () => {
    const mobileSet = selectPipelineTools(null, MOBILE_FLOW_READ_ONLY_TOOLS)
    const whatsappAll = selectPipelineTools(null)

    for (const kind of ['registration', 'correction', 'diet_fake', 'training_fake', 'skip'] as const) {
      expect(fakeWriteRetryAllowed(kind, mobileSet)).toBe(false)
      expect(fakeWriteRetryAllowed(kind, whatsappAll)).toBe(true)
    }
    expect(fakeWriteRetryAllowed('diet_fake', selectPipelineTools(['registra_refeicao']))).toBe(false)
    expect(fakeWriteRetryAllowed(null, whatsappAll)).toBe(false)
  })

  it('a model-supplied tool name is kept bounded and sanitized in the call summary', async () => {
    spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const hostile = `gera_treino ${'x'.repeat(300)} <script>`
    const deps = makeDeps(
      [{ toolCalls: [toolCall('call-1', hostile)] }, { toolCalls: [], content: 'ok' }],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(output.toolCalls).toContainEqual({
      name: 'invalid_tool_name',
      arguments: {},
      error: 'tool_unknown',
    })
    expect(JSON.stringify(output.toolCalls)).not.toContain('<script>')
  })

  it('on mobile, a false "registered" claim is retracted instead of prompting a write tool', async () => {
    spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const card = '🔥 Consumido: 1.433 / 1.843 kcal\n🎯 Restam: 410 kcal\n📊 Bloco 7700: 5.757 / 7.700'
    const deps = makeDeps(
      [
        { toolCalls: [], content: `Almoço registrado.\n\n${card}` },
        { toolCalls: [], content: 'Nada foi registrado pelo chat; use o registro do app para confirmar.' },
      ],
      null,
      recorded,
    )

    const output = await mobileMessage(deps)

    expect(output.text).toContain('Nada foi registrado pelo chat')
    const retry = JSON.stringify(recorded.calls?.[1] ?? [])
    expect(retry).toContain('SISTEMA (não é o paciente)')
    expect(retry).toContain('nada é registrado')
    expect(retry).not.toMatch(/Chame\s+(a tool\s+)?`?(registra_|gera_|marca_)/)
  })

  it('a channel without write tools that is not the app gets a retraction that never mentions the app', async () => {
    spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const card = '🔥 Consumido: 1.433 / 1.843 kcal\n🎯 Restam: 410 kcal\n📊 Bloco 7700: 5.757 / 7.700'
    const deps = makeDeps(
      [
        { toolCalls: [], content: `Almoço registrado.\n\n${card}` },
        { toolCalls: [], content: 'Ainda não registrei nada.' },
      ],
      ['consulta_metricas'],
      recorded,
    )

    await processMessage(deps, {
      from: 'fixture-sender',
      providerMessageId: 'wamid.fixture-3',
      text: 'Comi arroz no almoço',
      contentType: 'text',
      provider: 'whatsapp_cloud',
      timestamp: new Date('2026-09-27T12:00:00.000Z'),
    })

    const secondCall = (recorded.calls?.[1] ?? []) as Array<{ role: string; content: string }>
    const retry = secondCall.filter((message) => message.role === 'user').at(-1)?.content ?? ''
    expect(retry).toContain('SISTEMA (não é o paciente)')
    expect(retry).toContain('NÃO foi salvo')
    expect(retry).not.toMatch(/\bapp\b/)
    expect(retry).not.toMatch(/Chame\s+(a tool\s+)?`?(registra_|gera_|marca_)/)
  })

  it('on mobile, the false-duplication nudge never asks to register the items', async () => {
    spyExecutes()
    const recorded: Recorded = { inserts: [], rpcs: [] }
    const deps = makeDeps(
      [
        { toolCalls: [], content: 'Parece que sua mensagem veio duplicada.' },
        { toolCalls: [], content: 'São dois itens diferentes.' },
      ],
      null,
      recorded,
    )

    await processAuthenticatedMessage(deps, {
      userId: 'fixture-user',
      providerMessageId: 'mobile_flow/fixture-user/key-0002',
      text: '45 min musculação e 19 min bicicleta',
      timestamp: new Date('2026-09-27T12:00:00.000Z'),
    })

    const nudge = JSON.stringify(recorded.calls?.[1] ?? [])
    expect(nudge).toContain('itens DISTINTOS')
    expect(nudge).not.toContain('registre TODOS')
  })

  it('authorizeToolCall resolves only inside the request set; the registry never authorizes', () => {
    const mobileSet = selectPipelineTools(null, ['consulta_metricas'])

    expect(authorizeToolCall('consulta_metricas', mobileSet)).toEqual({
      status: 'authorized',
      tool: consultaMetricas,
    })
    expect(authorizeToolCall('gera_treino', mobileSet)).toEqual({ status: 'not_authorized' })
    expect(authorizeToolCall('apaga_tudo', mobileSet)).toEqual({ status: 'unknown' })
    expect(authorizeToolCall('consulta_metricas', [])).toEqual({ status: 'not_authorized' })
  })
})
