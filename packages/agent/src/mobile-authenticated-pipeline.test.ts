import { describe, expect, it } from 'vitest'
import type { PipelineDeps } from './pipeline.js'
import {
  MOBILE_FLOW_READ_ONLY_TOOLS,
  MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT,
  mobileFlowSystemPolicy,
  processAuthenticatedMessage,
  processMessage,
  selectPipelineTools,
} from './pipeline.js'

type QueryResult = { data: unknown; error: null }

type PipelineQuery = Promise<QueryResult> & {
  select: () => PipelineQuery
  eq: () => PipelineQuery
  gte: () => PipelineQuery
  like: () => PipelineQuery
  or: () => PipelineQuery
  order: () => PipelineQuery
  limit: () => PipelineQuery
  insert: () => PipelineQuery
  single: () => Promise<QueryResult>
  maybeSingle: () => Promise<QueryResult>
}

function makePipelineQuery(rows: unknown): PipelineQuery {
  const query = Promise.resolve({ data: rows, error: null }) as PipelineQuery
  const chain = () => query
  const singleRow = () => (Array.isArray(rows) ? (rows[0] ?? null) : rows)
  query.select = chain
  query.eq = chain
  query.gte = chain
  query.like = chain
  query.or = chain
  query.order = chain
  query.limit = chain
  query.insert = chain
  query.single = async () => ({ data: singleRow(), error: null })
  query.maybeSingle = async () => ({ data: singleRow(), error: null })
  return query
}

function makePipelineDeps(capture: (systemPrompt: unknown) => void): PipelineDeps {
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
      system_prompt:
        'Você é o **Dr. Roberto Menescal**. Para pacientes em inglês, use Dr. Robert Menescal.',
      allowed_tools: [],
    },
    agent_rules: [],
    global_config: [],
    pending_registrations: [],
  }
  const supabase = {
    from: (table: string) => makePipelineQuery(rowsByTable[table] ?? []),
    rpc: async () => ({ data: 'fixture-user', error: null }),
  } as unknown as PipelineDeps['supabase']
  const llm = {
    complete: async (input: { systemPrompt: unknown }) => {
      capture(input.systemPrompt)
      throw new Error('SYSTEM_PROMPT_CAPTURED')
    },
  } as unknown as PipelineDeps['llm']

  return { supabase, llm }
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

async function captureMobileSystemPrompt(): Promise<string> {
  let captured: unknown
  const deps = makePipelineDeps((systemPrompt) => {
    captured = systemPrompt
  })

  await expect(
    processAuthenticatedMessage(deps, {
      userId: 'fixture-user',
      providerMessageId: 'mobile-message-1',
      text: 'Explique meu contexto atual sem alterar nenhum dado.',
      timestamp: new Date('2026-09-16T12:00:00.000Z'),
    }),
  ).rejects.toThrow('SYSTEM_PROMPT_CAPTURED')

  return flattenSystemPrompt(captured)
}

describe('authenticated mobile Flow policy', () => {
  it('exposes only reviewed read-only tools even when the database allows every tool', () => {
    const tools = selectPipelineTools(null, MOBILE_FLOW_READ_ONLY_TOOLS)

    expect(tools.map((tool) => tool.name)).toEqual([
      'consulta_progresso',
      'consulta_metricas',
      'consulta_resumo_periodo',
      'consulta_reavaliacao_protocolo',
    ])
    expect(tools.some((tool) => tool.name.startsWith('registra_'))).toBe(false)
  })

  it('intersects the server channel allowlist with the database allowlist', () => {
    expect(
      selectPipelineTools(
        ['consulta_metricas', 'registra_refeicao'],
        MOBILE_FLOW_READ_ONLY_TOOLS,
      ).map((tool) => tool.name),
    ).toEqual(['consulta_metricas'])
  })

  it('names Performe AI and Flow and denies chat-triggered health mutations', () => {
    expect(mobileFlowSystemPolicy).toContain('Performe AI')
    expect(mobileFlowSystemPolicy).toContain('Flow')
    expect(mobileFlowSystemPolicy).toContain('não autoriza')
    expect(mobileFlowSystemPolicy).toContain('confirmação')
    expect(MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT).toBe(false)
  })

  it('uses Flow as the public identity in the mobile_flow user context', async () => {
    const systemPrompt = await captureMobileSystemPrompt()

    expect(systemPrompt).toContain('Persona: Flow.')
  })

  it('excludes every observed Roberto identity variant from mobile_flow context', async () => {
    const systemPrompt = await captureMobileSystemPrompt()

    expect(systemPrompt).not.toMatch(/Dr\.\s+Robert(?:o)?(?:\s+Menescal)?/i)
  })

  it('preserves the representative WhatsApp channel legacy identity', async () => {
    let captured: unknown
    const deps = makePipelineDeps((systemPrompt) => {
      captured = systemPrompt
    })

    await expect(
      processMessage(deps, {
        from: 'fixture-sender',
        providerMessageId: 'whatsapp-message-1',
        text: 'Explique meu contexto atual sem alterar nenhum dado.',
        patientText: 'Explique meu contexto atual sem alterar nenhum dado.',
        contentType: 'text',
        provider: 'whatsapp_cloud',
        timestamp: new Date('2026-09-16T12:00:00.000Z'),
      }),
    ).rejects.toThrow('SYSTEM_PROMPT_CAPTURED')

    expect(flattenSystemPrompt(captured)).toContain('Persona: Dr. Roberto Menescal.')
  })
})
