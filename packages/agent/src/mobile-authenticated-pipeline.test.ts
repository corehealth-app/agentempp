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

const legacyPersonaPrompt = `## Persona master

Você é o **Dr. Roberto Menescal**, nutricionista experiente que conduz o **Método MPP (Muscular Power Plant)** via WhatsApp. Você fala em primeira pessoa, com calor humano.

## Tom (regra de ouro)
Direto, próximo, sem firula.

## Markdown — uso parcimonioso
- **Bold** apenas em 1-2 dados críticos por mensagem.

## Decisões e proatividade
Nunca ajuste meta/protocolo sem confirmar.

---

## Regras internas
MPP: cálculos oficiais permanecem no servidor.
Não substitua um nutricionista; recomende acompanhamento profissional quando necessário.`

interface PromptFixtureOptions {
  systemPrompt?: string
  rules?: Array<{ topic: string; content: string; language: string | null }>
  model?: string
  methodChunks?: Array<{ page_title: string; content: string }>
}

function makePipelineDeps(
  capture: (systemPrompt: unknown) => void,
  options: PromptFixtureOptions = {},
): PipelineDeps {
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
      model: options.model ?? 'openai/test-model',
      temperature: 0,
      max_tokens: 64,
      system_prompt:
        options.systemPrompt ??
        'Você é o **Dr. Roberto Menescal**. Para pacientes em inglês, use Dr. Robert Menescal.',
      allowed_tools: [],
    },
    agent_rules: options.rules ?? [],
    global_config: [],
    pending_registrations: [],
  }
  const supabase = {
    from: (table: string) => makePipelineQuery(rowsByTable[table] ?? []),
    rpc: async (name: string) => ({
      data: name === 'match_method_chunks' ? (options.methodChunks ?? []) : 'fixture-user',
      error: null,
    }),
  } as unknown as PipelineDeps['supabase']
  const llm = {
    complete: async (input: { systemPrompt: unknown }) => {
      capture(input.systemPrompt)
      throw new Error('SYSTEM_PROMPT_CAPTURED')
    },
  } as unknown as PipelineDeps['llm']

  const embeddings = options.methodChunks
    ? ({ embed: async () => [0.1, 0.2] } as unknown as PipelineDeps['embeddings'])
    : undefined
  return { supabase, llm, embeddings }
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

async function captureMobileSystemPrompt(options: PromptFixtureOptions = {}): Promise<string> {
  let captured: unknown
  const deps = makePipelineDeps((systemPrompt) => {
    captured = systemPrompt
  }, options)

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

  it.each([
    'openai/test-model',
    'anthropic/test-model',
  ])('replaces the legacy health-professional introduction at the final %s boundary', async (model) => {
    const prompt = await captureMobileSystemPrompt({ systemPrompt: legacyPersonaPrompt, model })

    expect(prompt).toContain('Você é Flow, assistente de IA do Performe AI.')
    expect(prompt).not.toMatch(/Você é[^.\n]*(?:nutricionista|médico|psicólogo)/i)
    expect(prompt).not.toMatch(/Você é[^.\n]*(?:Método MPP|Muscular Power Plant)/i)
    expect(prompt).not.toMatch(/Dr\.?\s+Robert(?:o)?(?:\s+Menescal)?/i)
    expect(prompt).toContain('Não reivindique profissão regulamentada')
    expect(prompt).toContain('Não substitua um nutricionista')
    expect(prompt).toContain('MPP: cálculos oficiais permanecem no servidor.')
    expect(prompt).toContain('Nunca ajuste meta/protocolo sem confirmar.')
    expect(prompt).toContain('Direto, próximo, sem firula.')
  })

  it('projects language-filtered rules, not just the view fallback, into the mobile persona', async () => {
    const prompt = await captureMobileSystemPrompt({
      systemPrompt: 'VIEW_FALLBACK_MUST_NOT_BE_USED',
      rules: [{ topic: 'Persona master', content: legacyPersonaPrompt, language: 'pt-BR' }],
    })

    expect(prompt).not.toContain('VIEW_FALLBACK_MUST_NOT_BE_USED')
    expect(prompt).toContain('Você é Flow, assistente de IA do Performe AI.')
    expect(prompt).not.toMatch(/Você é[^.\n]*nutricionista/i)
  })

  it('removes the English professional identity instruction without banning disclaimers', async () => {
    const prompt = await captureMobileSystemPrompt({
      systemPrompt:
        'You are **Dr. Robert Menescal**, an experienced nutritionist leading the MPP Method. Do not replace a doctor.',
    })

    expect(prompt).not.toMatch(/You are[^.\n]*(?:nutritionist|doctor|MPP)/i)
    expect(prompt).toContain('Do not replace a doctor.')
    expect(prompt).toContain('Você é Flow, assistente de IA do Performe AI.')
  })

  it('never lets the Flow write the method or its author, not even when asked', async () => {
    const prompt = await captureMobileSystemPrompt({ systemPrompt: legacyPersonaPrompt })

    // Audit 2026-10-05: the instruction was "não o apresente espontaneamente",
    // which let the name out when the person asked. It is absolute now.
    expect(prompt).not.toContain('espontaneamente')
    expect(prompt).toContain(
      'Nunca escreva "MPP", "Muscular Power Plant", o nome de quem criou o método\nnem "método do Dr." seguido de nome, nem quando a pessoa perguntar: são\nreferências internas.',
    )
    expect(prompt).toContain(
      'Se perguntarem qual é o método ou quem está por trás\ndele, diga só que as orientações seguem o programa do Performe AI.',
    )
  })

  it('requires plain text and removes the inherited decorative Markdown instruction', async () => {
    const prompt = await captureMobileSystemPrompt({ systemPrompt: legacyPersonaPrompt })

    expect(prompt).toContain('Responda em texto simples, sem Markdown decorativo')
    expect(prompt).toContain('inclusive na apresentação curta')
    expect(prompt).not.toContain('**Bold** apenas')
    expect(prompt).toContain('Nunca ajuste meta/protocolo sem confirmar.')
  })

  it('projects the same known persona introduction if method retrieval reintroduces it', async () => {
    const prompt = await captureMobileSystemPrompt({
      systemPrompt: 'Mantenha os números oficiais.',
      methodChunks: [{ page_title: 'Referência interna', content: legacyPersonaPrompt }],
    })

    expect(prompt).toContain('## Método relevante (recuperado da base')
    expect(prompt).not.toMatch(/Você é[^\n]*(?:nutricionista experiente|Método MPP)/i)
    expect(prompt).not.toMatch(/Dr\.?\s+Robert(?:o)?(?:\s+Menescal)?/i)
    expect(prompt).not.toContain('**Bold** apenas')
    expect(prompt).toContain('MPP: cálculos oficiais permanecem no servidor.')
  })

  it('preserves the next retrieved calculation chunk after a trailing persona Markdown section', async () => {
    const prompt = await captureMobileSystemPrompt({
      systemPrompt: 'Mantenha os números oficiais.',
      methodChunks: [
        {
          page_title: 'Persona legada',
          content: '## Markdown — uso parcimonioso\n**Bold** apenas em destaques.',
        },
        {
          page_title: 'Cálculo oficial',
          content: 'MPP: use somente o cálculo determinístico do servidor. Nunca invente metas.',
        },
      ],
    })

    expect(prompt).not.toContain('**Bold** apenas')
    expect(prompt).toContain('### Cálculo oficial')
    expect(prompt).toContain(
      'MPP: use somente o cálculo determinístico do servidor. Nunca invente metas.',
    )
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

  it('preserves the full legacy persona and Markdown instructions on WhatsApp', async () => {
    let captured: unknown
    const deps = makePipelineDeps(
      (prompt) => {
        captured = prompt
      },
      {
        systemPrompt: legacyPersonaPrompt,
        methodChunks: [{ page_title: 'Referência legada', content: legacyPersonaPrompt }],
      },
    )

    await expect(
      processMessage(deps, {
        from: 'fixture-sender',
        providerMessageId: 'legacy-fixture',
        text: 'Olá',
        contentType: 'text',
        provider: 'whatsapp_cloud',
        timestamp: new Date('2026-09-16T12:00:00Z'),
      }),
    ).rejects.toThrow('SYSTEM_PROMPT_CAPTURED')

    const prompt = flattenSystemPrompt(captured)
    expect(prompt.startsWith(legacyPersonaPrompt)).toBe(true)
    expect(prompt).toContain(`### Referência legada\n${legacyPersonaPrompt}`)
    expect(prompt).not.toContain('Responda em texto simples, sem Markdown decorativo')
  })
})
