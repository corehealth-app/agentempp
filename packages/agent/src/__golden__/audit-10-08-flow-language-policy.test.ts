/** C2: exact six staging rule versions read under explicit authorization.
 * Real Flow entry + synthetic account/provider; no live model or database.
 */
import { readFileSync } from 'node:fs'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import type { PipelineDeps } from '../pipeline.js'
import { processAuthenticatedMessage } from '../pipeline.js'

beforeEach(() => clearCalcConfigCache())

type QueryResult = { data: unknown; error: unknown }

afterEach(() => vi.restoreAllMocks())

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

function makePipelineQuery(rows: unknown, error: unknown = null): PipelineQuery {
  const query = Promise.resolve({ data: rows, error }) as PipelineQuery
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
  query.single = async () => ({ data: singleRow(), error })
  query.maybeSingle = async () => ({ data: singleRow(), error })
  return query
}

interface PromptFixtureOptions {
  systemPrompt?: string
  rules?: Array<{ topic: string; content: string; language: string | null }>
  protocol?: 'recomposicao' | 'ganho_massa' | 'manutencao' | null
  rulesError?: unknown
  capture?: (prompt: unknown) => void
  onRulesRead?: () => void
  history?: Array<Record<string, unknown>>
  model?: string
  methodChunks?: Array<{ page_title: string; content: string }>
  userId?: string
  locale?: string
  day?: Record<string, unknown>
  coachPreference?: (owner: string, columns: string) => Promise<QueryResult>
}

function makePipelineDeps(
  capture: (systemPrompt: unknown) => void,
  options: PromptFixtureOptions = {},
): PipelineDeps {
  const rowsByTable: Record<string, unknown> = {
    users: {
      id: options.userId ?? 'fixture-user',
      name: 'Pessoa sintética',
      summary: null,
      last_active_at: null,
      country: 'BR',
      country_confirmed: true,
      country_detected_from_wpp: null,
      locale: options.locale ?? 'pt-BR',
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
      current_protocol: options.protocol === undefined ? 'manutencao' : options.protocol,
      goal_type: null,
      goal_value: null,
      deficit_level: null,
    },
    messages: options.history ?? [],
    daily_snapshots: options.day ? [options.day] : [],
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
    from: (table: string) => {
      if (table === 'agent_rules') {
        options.onRulesRead?.()
        if (options.rulesError) return makePipelineQuery(null, options.rulesError)
      }
      if (table !== 'user_coach_preferences') return makePipelineQuery(rowsByTable[table] ?? [])
      let owner = ''
      let columns = ''
      const query = makePipelineQuery(null)
      query.select = (value?: string) => {
        columns = value ?? ''
        return query
      }
      query.eq = (column?: string, value?: unknown) => {
        expect(column).toBe('user_id')
        owner = String(value)
        return query
      }
      query.insert = () => {
        throw new Error('preference must never be written by chat')
      }
      query.maybeSingle = async () =>
        options.coachPreference?.(owner, columns) ?? { data: null, error: null }
      return query
    },
    rpc: async (name: string) => ({
      data:
        name === 'match_method_chunks'
          ? (options.methodChunks ?? [])
          : (options.userId ?? 'fixture-user'),
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
    options.capture?.(systemPrompt)
  }, options)

  await expect(
    processAuthenticatedMessage(deps, {
      userId: options.userId ?? 'fixture-user',
      providerMessageId: 'mobile-message-1',
      text: 'Explique meu contexto atual sem alterar nenhum dado.',
      timestamp: new Date('2026-09-16T12:00:00.000Z'),
    }),
  ).rejects.toThrow('SYSTEM_PROMPT_CAPTURED')

  return flattenSystemPrompt(captured)
}

const fixture = JSON.parse(
  readFileSync(
    new URL('./fixtures/c2-staging-reviewed-general-rules-20261008.json', import.meta.url),
    'utf8',
  ),
) as {
  rules: Array<{
    slug: string
    topic: string
    tipo: string
    content: string
    language: string | null
    display_order: number
  }>
}
const reviewed = fixture.rules
const fullView = reviewed.map((r) => `## ${r.topic}\n\n${r.content}`).join('\n\n---\n\n')

// Fail if the Flow keeps the six incompatible legacy versions in its request.
describe('audit 2026-10-08 C2: exact reviewed staging rules at the real Flow boundary', () => {
  it('replaces all six reviewed bodies with the Flow language card without reviving a view fallback', async () => {
    const prompt = await captureMobileSystemPrompt({
      rules: reviewed,
      systemPrompt: `VIEW_MUST_NOT_RETURN: ${fullView}`,
    })
    expect(prompt).toContain('### Linguagem do Flow')
    expect(prompt).toContain(
      'Quatro proibições: não transferir cálculos ao usuário; não julgar ou moralizar; não encher a resposta de termos técnicos; não ameaçar nem fazer terrorismo.',
    )
    expect(prompt).not.toContain('VIEW_MUST_NOT_RETURN')
    for (const legacy of [
      'country_detected_from_wpp',
      'confirma_pais_residencia(country:',
      'Persona pelo país',
      'Antes de chamar tools que mudam estado',
      'refinei pra 16%',
      'na 1ª msg após 06h00',
    ]) {
      expect(prompt, legacy).not.toContain(legacy)
    }
    expect(prompt).toContain(
      'Uma mensagem enviada no chat não autoriza alteração de dados de saúde.',
    )
    expect(prompt).toContain('Não reivindique profissão regulamentada')
  })

  it.each([
    ['recomposicao', 'Objetivo registrado: recomposição corporal.'],
    ['ganho_massa', 'Objetivo registrado: ganho de massa.'],
    ['manutencao', 'Objetivo registrado: manutenção.'],
  ] as const)('uses only the current %s phase label and keeps the base within 2700 characters', async (protocol, label) => {
    const prompt = await captureMobileSystemPrompt({ rules: reviewed, protocol })
    expect(prompt).toContain(`### Fase atual do Flow\n${label}`)
    const start = prompt.indexOf('### Linguagem do Flow')
    const end = prompt.indexOf('### Fase atual do Flow')
    expect(start).toBeGreaterThanOrEqual(0)
    expect(end).toBeGreaterThan(start)
    expect(prompt.slice(start, end).trimEnd().length).toBeLessThanOrEqual(2700)
    expect(prompt.match(/### Fase atual do Flow/g)).toHaveLength(1)
    expect(prompt).not.toContain('### Nota de botão')
  })

  it('does not invent a phase when the persisted objective is absent', async () => {
    const prompt = await captureMobileSystemPrompt({ rules: reviewed, protocol: null })
    expect(prompt).toContain('### Linguagem do Flow')
    expect(prompt).not.toContain('### Fase atual do Flow')
  })

  it.each([
    'body',
    'topic',
    'language',
    'tipo',
    'slug',
    'duplicate',
    'missing',
    'new-general',
  ] as const)('keeps the previous composition and marks C2 unapplied on %s drift', async (kind) => {
    const rules = structuredClone(reviewed)
    const first = rules[0]
    if (!first) throw new Error('missing reviewed source fixture')
    if (kind === 'body')
      first.content += '\nNOVA_RESTRICAO: alergia a amendoim; não alterar objetivo.'
    if (kind === 'topic') first.topic = 'Changed topic'
    if (kind === 'language') first.language = null
    if (kind === 'tipo') first.tipo = 'manutencao'
    if (kind === 'slug') first.slug = 'different-slug'
    if (kind === 'duplicate') rules.push(structuredClone(first))
    if (kind === 'missing') rules.pop()
    if (kind === 'new-general')
      rules.push({
        ...first,
        slug: 'new-general',
        topic: 'Nova regra',
        content: 'NOVA_RESTRICAO: alergia a amendoim; não alterar objetivo.',
      })
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const prompt = await captureMobileSystemPrompt({ rules })
    expect(prompt).not.toContain('### Linguagem do Flow')
    expect(prompt).not.toContain('### Fase atual do Flow')
    // This retained paragraph exists in the first rule even when the last
    // rule was deliberately removed from the input fixture.
    expect(prompt).toContain('Frases curtas. Conversa de amigo, não relatório.')
    if (kind === 'body' || kind === 'new-general')
      expect(prompt).toContain('NOVA_RESTRICAO: alergia a amendoim; não alterar objetivo.')
    expect(warn).toHaveBeenCalledWith(
      '[mobile-flow] language_card_unapplied',
      expect.objectContaining({ reason: expect.any(String) }),
    )
    expect(JSON.stringify(warn.mock.calls)).not.toContain('amendoim')
  })

  it('preserves a whole phase rule even when its body quotes a reviewed block after the view separator', async () => {
    const greeting = reviewed.find((row) => row.slug === 'saudacoes-variadas')
    if (!greeting) throw new Error('missing reviewed greeting fixture')
    const content = `RESTRICAO_ADJACENTE: alergia a amendoim.\n\n---\n\n## Saudações e aberturas variadas\n\n${greeting.content}\nFIM_DA_REGRA: sem mudar metas.`
    const rules = [
      ...reviewed,
      {
        ...greeting,
        slug: 'phase-rule',
        topic: 'Conduta confirmada',
        tipo: 'manutencao',
        content,
      },
    ]
    const prompt = await captureMobileSystemPrompt({ rules })
    expect(prompt).toContain('### Linguagem do Flow')
    expect(prompt).toContain(content)
  })

  it.each([
    false,
    true,
  ])('only uses a <=200-character situation with proven assistant history (%s)', async (hasHistory) => {
    const prompt = await captureMobileSystemPrompt({
      rules: reviewed,
      history: hasHistory
        ? [
            {
              direction: 'out',
              content: 'Tudo certo.',
              created_at: '2026-09-16T11:59:00Z',
              provider_message_id: 'mobile_flow/fixture-user/old',
            },
          ]
        : [],
    })
    const heading = '### Situação deste turno\n'
    expect(prompt.includes(heading)).toBe(hasHistory)
    if (hasHistory)
      expect(prompt.slice(prompt.indexOf(heading)).trimEnd().length).toBeLessThanOrEqual(200)
    expect(prompt).not.toContain('### Nota de botão')
  })

  it.each([
    'empty',
    'error',
  ] as const)('preserves the old view fallback on %s, without pretending C2 applied', async (kind) => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const prompt = await captureMobileSystemPrompt({
      rules: [],
      rulesError: kind === 'error' ? { message: 'synthetic denied' } : undefined,
      systemPrompt: 'FALLBACK_SAFETY: preserve alergia a amendoim.',
    })
    expect(prompt).toContain('FALLBACK_SAFETY: preserve alergia a amendoim.')
    expect(prompt).not.toContain('### Linguagem do Flow')
    expect(warn).toHaveBeenCalledWith(
      '[mobile-flow] language_card_unapplied',
      expect.objectContaining({ reason: expect.any(String) }),
    )
  })
})

describe('C2: calls, cached prefix and persisted coach style', () => {
  it.each([
    'reviewed',
    'changed',
    'empty',
    'error',
  ] as const)('does not re-query rules on %s and preserves the prior fallback availability', async (kind) => {
    let reads = 0
    const rules = kind === 'empty' || kind === 'error' ? [] : structuredClone(reviewed)
    const first = rules[0]
    if (kind === 'changed' && first) first.content += '\nChanged source version.'
    await captureMobileSystemPrompt({
      rules,
      rulesError: kind === 'error' ? { code: 'synthetic-read-failure' } : undefined,
      onRulesRead: () => {
        reads += 1
      },
    })
    expect(reads).toBe(1)
  })

  it('keeps a stable cached C2 prefix across Focus, Impulse and Zen, with locale and style only in the variable block', async () => {
    const prefixes: string[] = []
    for (const code of ['focus', 'impulse', 'zen'] as const) {
      let blocks: Array<{ text: string; cache?: string }> = []
      const prompt = await captureMobileSystemPrompt({
        rules: reviewed,
        model: 'anthropic/test-model',
        locale: 'en',
        capture: (value) => {
          blocks = value as typeof blocks
        },
        coachPreference: async (owner) => ({
          data: { user_id: owner, personality_code: code },
          error: null,
        }),
      })
      expect(blocks).toHaveLength(2)
      expect(blocks[0]?.cache).toBe('ephemeral_1h')
      expect(blocks[0]?.text).toContain('### Linguagem do Flow')
      expect(blocks[0]?.text).not.toMatch(/Tom (Focus|Impulse|Zen):/)
      expect(blocks[1]?.text).toContain(`Tom ${code[0]?.toUpperCase()}${code.slice(1)}:`)
      expect(blocks[1]?.text).toContain('Idioma salvo: **en**')
      expect(prompt).not.toContain('Persona pelo país')
      prefixes.push(blocks[0]?.text ?? '')
    }
    expect(prefixes[1]).toBe(prefixes[0])
    expect(prefixes[2]).toBe(prefixes[0])
  })
})
