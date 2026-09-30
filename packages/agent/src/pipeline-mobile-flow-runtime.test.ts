import { afterEach, describe, expect, it, vi } from 'vitest'
import { dietSystemPrompt } from './diet-generator.js'
import { flattenLegacyTagsForApp } from './onboarding-button.js'
import type { PipelineDeps } from './pipeline.js'
import { processAuthenticatedMessage, processMessage } from './pipeline.js'
import { trainingSystemPrompt } from './training-plan-generator.js'
import { consultaProgresso, geraDieta, geraTreino } from './tools.js'

// Mobile Flow runtime: legacy WhatsApp tags never reach the app as syntax or
// as an empty reply, and the plan generators speak as Flow only when the
// server-controlled mobile context says so. Scripted provider, no paid call.

type QueryResult = { data: unknown; error: null }
type Query = Promise<QueryResult> & Record<string, unknown>

interface Recorded {
  inserts: Array<{ table: string; row: unknown }>
}

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

// sha256 of the prompt constants as released at HEAD 51f999af (git show).
const LEGACY_TRAINING_PROMPT_SHA256 = '19bb8a14a93e85d499497c8cb7a0e9c25ce12bab11b7d03dcd36ba4d45f84f5c'
const LEGACY_DIET_PROMPT_SHA256 = '2716e6e972f2d699b76b47ee9e1853624c7ba7fb83f6e2c70255ab2ba2ca9476'

interface ScriptedStep {
  toolCalls: Array<{ id: string; name: string; arguments: string }>
  content?: string
}

function makeDeps(replies: string[], recorded: Recorded): PipelineDeps {
  return makeScriptedDeps(replies.map((content) => ({ toolCalls: [], content })), recorded)
}

function makeScriptedDeps(
  steps: ScriptedStep[],
  recorded: Recorded,
  overrides: {
    messages?: unknown[]
    onComplete?: (input: { messages: unknown[] }) => void
    maxToolIterations?: number
  } = {},
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
    messages: overrides.messages ?? [],
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
      allowed_tools: null,
    },
    agent_rules: [],
    global_config: [],
    pending_registrations: [],
  }
  const supabase = {
    from: (table: string) => makeQuery(table, rowsByTable[table] ?? [], recorded),
    rpc: async (name: string) => ({ data: name === 'match_method_chunks' ? [] : 'fixture-user', error: null }),
  } as unknown as PipelineDeps['supabase']
  let call = 0
  const llm = {
    complete: async (input: { messages: unknown[] }) => {
      overrides.onComplete?.(input)
      const step = steps[Math.min(call, steps.length - 1)] ?? { toolCalls: [] }
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
  return { supabase, llm, maxToolIterations: overrides.maxToolIterations ?? 3 }
}

const timestamp = new Date('2026-09-27T12:00:00.000Z')

function mobile(reply: string, recorded: Recorded = { inserts: [] }) {
  return processAuthenticatedMessage(makeDeps([reply], recorded), {
    userId: 'fixture-user',
    providerMessageId: 'mobile_flow/fixture-user/key-0001',
    text: 'Pode me perguntar o que falta?',
    timestamp,
  })
}

function whatsapp(reply: string, recorded: Recorded = { inserts: [] }) {
  return processMessage(makeDeps([reply], recorded), {
    from: '5511999999999',
    providerMessageId: 'wamid.fixture',
    text: 'Pode me perguntar o que falta?',
    contentType: 'text',
    provider: 'whatsapp',
    timestamp,
  })
}

const buttonReply = 'Pra ajustar sua meta: qual é o seu sexo?\n[BTN:sex:Homem=masculino|Mulher=feminino]'
const listReply =
  'Qual é o seu nível de atividade?\n[LIST:activity_level:Sedentário=sedentario|Leve=leve|Moderado=moderado|Alto=alto|Atleta=atleta]'

afterEach(() => {
  vi.restoreAllMocks()
})

describe('3.2 legacy [BTN:]/[LIST:] tags on the mobile Flow', () => {
  it('a button tag keeps the question and turns the options into plain text, with no interactive payload', async () => {
    const recorded: Recorded = { inserts: [] }
    const output = await mobile(buttonReply, recorded)

    expect(output.text).toBe('Pra ajustar sua meta: qual é o seu sexo?\n\n• Homem\n• Mulher')
    expect(output.text).not.toMatch(/\[(BTN|LIST):|masculino|feminino/)
    expect(output.interactive).toBeUndefined()
    const events = recorded.inserts
      .filter((entry) => entry.table === 'product_events')
      .map((entry) => (entry.row as { event: string }).event)
    expect(events).not.toContain('pipeline.onboarding_button_sent')
  })

  it('a list tag is flattened the same way', async () => {
    const output = await mobile(listReply)

    expect(output.text).toBe('Qual é o seu nível de atividade?\n\n• Sedentário\n• Leve\n• Moderado\n• Alto\n• Atleta')
    expect(output.interactive).toBeUndefined()
  })

  it('a malformed or unterminated tag is removed and the useful text around it is kept', async () => {
    expect((await mobile('Me conta mais sobre sua rotina. [BTN:nao_existe:Sim=sim] Combinado?')).text).toBe(
      'Me conta mais sobre sua rotina. Combinado?',
    )
    expect((await mobile('Qual o seu objetivo? [LIST:goal:Perder')).text).toBe('Qual o seu objetivo?')
  })

  it('a reply that is only a tag leaves no visible text (the service then fails the turn with 502)', async () => {
    const output = await mobile('[BTN:sex:Homem=masculino|Mulher=feminino]')

    expect(output.text).toBe('')
    expect(output.interactive).toBeUndefined()
  })

  it('WhatsApp keeps sending the tag as interactive buttons, unchanged', async () => {
    const recorded: Recorded = { inserts: [] }
    const output = await whatsapp(buttonReply, recorded)

    expect(output.text).toBe('')
    expect(output.interactive).toMatchObject({
      body: 'Pra ajustar sua meta: qual é o seu sexo?',
      buttons: [
        { id: 'btn_sex_masculino', title: 'Homem' },
        { id: 'btn_sex_feminino', title: 'Mulher' },
      ],
    })
  })

  it('the flattening helper never invents content', () => {
    expect(flattenLegacyTagsForApp('Tudo certo por aqui.')).toBe('Tudo certo por aqui.')
    expect(flattenLegacyTagsForApp('   ')).toBe('')
    expect(flattenLegacyTagsForApp('[LIST:activity_level:Leve=leve|Alto=alto]')).toBe('')
  })
})

describe('3.4 S3 — plan generator identity', () => {
  it('the default (every legacy consumer) keeps the current prompt byte for byte', () => {
    expect(trainingSystemPrompt()).toBe(trainingSystemPrompt('legacy'))
    expect(trainingSystemPrompt().split('\n')[0]).toBe(
      'Você é Dr. Roberto Menescal, conduzindo o Método MPP via WhatsApp.',
    )
    expect(dietSystemPrompt()).toBe(dietSystemPrompt('legacy'))
    expect(dietSystemPrompt().split('\n')[0]).toBe(
      'Você é Dr. Roberto Menescal, nutricionista que conduz o Método MPP via WhatsApp.',
    )
  })

  it('the Flow identity names neither a person nor WhatsApp nor the internal method name', () => {
    for (const prompt of [trainingSystemPrompt('flow'), dietSystemPrompt('flow')]) {
      expect(prompt.split('\n')[0]).toMatch(/^Você é o Flow, o assistente do Performe AI/)
      expect(prompt).not.toMatch(/Roberto|Menescal|WhatsApp|\bMPP\b/)
    }
    // The technical rules are the same; only the identity lines change.
    expect(trainingSystemPrompt('flow')).toContain('Compostos primeiro, isoladores depois')
    expect(dietSystemPrompt('flow')).toContain('Use TACO brasileira como referência calórica')
  })

  function captureGeneratorIdentity(tool: typeof geraTreino | typeof geraDieta) {
    const identities: string[] = []
    const llm = {
      complete: vi.fn(async (input: { systemPrompt: string }) => {
        identities.push(String(input.systemPrompt).split('\n')[0] ?? '')
        return { content: '{}', toolCalls: [], model: 'openai/test-model', promptTokens: 1, completionTokens: 1, costUsd: 0 }
      }),
    }
    return { identities, llm, tool }
  }

  it.each([
    ['gera_treino', geraTreino, { available_equipment: ['halteres'], location: 'casa', days_per_week: 3, training_level: 'iniciante' }],
    ['gera_dieta', geraDieta, {}],
  ] as const)('%s speaks as Flow only when the server-set mobile context says so', async (_name, tool, args) => {
    const recorded: Recorded = { inserts: [] }
    const supabase = makeDeps([''], recorded).supabase
    for (const identity of [undefined, 'flow'] as const) {
      const { identities, llm } = captureGeneratorIdentity(tool)
      await tool
        .execute(tool.parameters.parse(args) as never, {
          supabase,
          userId: 'fixture-user',
          userWpp: '',
          llm,
          ...(identity ? { assistantIdentity: identity } : {}),
        })
        .catch(() => undefined)
      // The generator must actually have been reached (no vacuous pass).
      expect(identities).toHaveLength(1)
      expect(identities[0]).toMatch(identity === 'flow' ? /^Você é o Flow/ : /^Você é Dr\. Roberto Menescal/)
    }
  })
})

describe('adversarial review follow-ups', () => {
  it('an unterminated tag only removes its own line; bracketed prose is kept; spaces are tidy', () => {
    expect(flattenLegacyTagsForApp('Qual seu sexo? [BTN:sex:Homem=masc\n\nDepois me conta sua rotina.')).toBe(
      'Qual seu sexo?\n\nDepois me conta sua rotina.',
    )
    expect(flattenLegacyTagsForApp('Compre [List: arroz, feijão] hoje.')).toBe('Compre [List: arroz, feijão] hoje.')
    expect(flattenLegacyTagsForApp('Me conta. [BTN:nao_existe:Sim=sim] Combinado?')).toBe('Me conta. Combinado?')
    // A tag split across lines or written with spaces is still a tag.
    expect(flattenLegacyTagsForApp('Qual seu sexo? [BTN:sex:\nHomem=masculino|\nMulher=feminino]')).toBe(
      'Qual seu sexo?\n\n• Homem\n• Mulher',
    )
    expect(flattenLegacyTagsForApp('Oi [BTN: sex: Homem=masculino|Mulher=feminino] tudo bem?')).toBe('Oi tudo bem?')
    // Prose without options is not a tag, and a reply without tags is untouched.
    expect(flattenLegacyTagsForApp('[LIST:compras: arroz, feijão]')).toBe('[LIST:compras: arroz, feijão]')
    expect(flattenLegacyTagsForApp('Lista:\n  - ovos  2 un\n\n\n  - pão')).toBe('Lista:\n  - ovos  2 un\n\n\n  - pão')
  })

  it('the legacy generator prompts are byte-identical to the released ones', async () => {
    const { createHash } = await import('node:crypto')
    const sha = (text: string) => createHash('sha256').update(text).digest('hex')
    expect(sha(trainingSystemPrompt('legacy'))).toBe(LEGACY_TRAINING_PROMPT_SHA256)
    expect(sha(dietSystemPrompt('legacy'))).toBe(LEGACY_DIET_PROMPT_SHA256)
  })

  it('the pipeline hands the Flow identity to tools only on the mobile channel', async () => {
    const seen: Array<string | undefined> = []
    vi.spyOn(consultaProgresso, 'execute').mockImplementation(async (_args, ctx) => {
      seen.push(ctx.assistantIdentity)
      return { success: true }
    })
    const script = (recorded: Recorded) =>
      makeScriptedDeps(
        [
          { toolCalls: [{ id: 'call-1', name: 'consulta_progresso', arguments: '{}' }] },
          { toolCalls: [], content: 'Seu progresso está ótimo.' },
        ],
        recorded,
      )
    await processAuthenticatedMessage(script({ inserts: [] }), {
      userId: 'fixture-user',
      providerMessageId: 'mobile_flow/fixture-user/key-0002',
      text: 'Como está meu progresso?',
      timestamp,
    })
    await processMessage(script({ inserts: [] }), {
      from: '5511999999999',
      providerMessageId: 'wamid.fixture-2',
      text: 'Como está meu progresso?',
      contentType: 'text',
      provider: 'whatsapp',
      timestamp,
    })
    expect(seen).toEqual(['flow', undefined])
  })
})

// Audit 2026-09-28 (golden: __golden__/audit-09-28-flow-history-date.test.ts):
// the date label is wired to the Flow channel only, through the real pipeline.
describe('history rows from a previous local day', () => {
  const now = new Date('2026-09-29T00:08:34.286Z') // 28/09 21:08 in São Paulo
  const yesterdayAnswer = 'Hoje você tá em 676 kcal de 3.355 — ainda bem abaixo da meta.'
  const rows = [
    { direction: 'out', content: yesterdayAnswer, content_type: 'text', created_at: '2026-09-28T02:43:53.130Z', provider_message_id: 'out-1' },
    { direction: 'in', content: 'Quanto eu ja comi hoje?', content_type: 'text', created_at: '2026-09-28T02:43:41.662Z', provider_message_id: 'in-1' },
  ]
  const historyOf = (input: { messages: unknown[] }) =>
    (input.messages as Array<{ role: string; content: unknown }>)
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map((m) => String(m.content))

  it('the mobile Flow sends yesterday\'s rows dated to the model', async () => {
    const seen: string[][] = []
    const deps = makeScriptedDeps([{ toolCalls: [], content: 'Ok.' }], { inserts: [] }, {
      messages: rows,
      onComplete: (input) => seen.push(historyOf(input)),
    })
    await processAuthenticatedMessage(deps, {
      userId: 'fixture-user',
      providerMessageId: 'mobile_flow/fixture-user/key-0002',
      text: 'Qual é a minha meta de hoje e quanto falta?',
      timestamp: now,
    })
    const first = seen[0] ?? []
    expect(first.filter((c) => c.startsWith('[Mensagem de 27/09/2026, dia anterior'))).toHaveLength(2)
    expect(first.some((c) => c.endsWith(yesterdayAnswer))).toBe(true)
  })

  it('WhatsApp sends the same rows byte for byte, without any date label', async () => {
    const seen: string[][] = []
    const deps = makeScriptedDeps([{ toolCalls: [], content: 'Ok.' }], { inserts: [] }, {
      messages: rows,
      onComplete: (input) => seen.push(historyOf(input)),
    })
    await processMessage(deps, {
      from: '5511999999999',
      providerMessageId: 'wamid.fixture-2',
      text: 'Qual é a minha meta de hoje e quanto falta?',
      contentType: 'text',
      provider: 'whatsapp',
      timestamp: now,
    })
    const first = seen[0] ?? []
    expect(first.some((c) => c.includes('[Mensagem de'))).toBe(false)
    expect(first).toContain('Quanto eu ja comi hoje?')
    expect(first).toContain(yesterdayAnswer)
  })
})

// Staging device E2E 2026-09-30 (iPhone, QA A, BFF p2six2e3s, Flow config
// f5013b3f with max_tool_iterations 2): "Mostre meu progresso recente." ran
// consulta_progresso, the next answer tripped the premature-block guard
// (llm.premature_block_completion), the guard's retry had no iteration left,
// and the turn ended with no text (POST /flow/chat 502 empty_reply). A guard
// retry must not consume the patient's answer.
describe('a guard retry on the last allowed iteration', () => {
  it('still produces the corrected answer (mobile Flow, 2 tool iterations)', async () => {
    vi.spyOn(consultaProgresso, 'execute').mockResolvedValue({ success: true })
    const corrected = 'Seu bloco atual está em andamento; ele só é creditado no fechamento do dia.'
    const output = await processAuthenticatedMessage(
      makeScriptedDeps(
        [
          { toolCalls: [{ id: 'call-1', name: 'consulta_progresso', arguments: '{}' }] },
          { toolCalls: [], content: 'Com o treino de hoje você fechou o segundo bloco completo!' },
          { toolCalls: [], content: corrected },
        ],
        { inserts: [] },
        { maxToolIterations: 2 },
      ),
      {
        userId: 'fixture-user',
        providerMessageId: 'mobile_flow/fixture-user/key-0930',
        text: 'Mostre meu progresso recente.',
        timestamp,
      },
    )
    expect(output.text).toBe(corrected)
  })

  it('a guard retries at most once, so the turn stays bounded', async () => {
    vi.spyOn(consultaProgresso, 'execute').mockResolvedValue({ success: true })
    let calls = 0
    const premature = 'Com o treino de hoje você fechou o segundo bloco completo!'
    const output = await processAuthenticatedMessage(
      makeScriptedDeps(
        [
          { toolCalls: [{ id: 'call-1', name: 'consulta_progresso', arguments: '{}' }] },
          { toolCalls: [], content: premature },
          { toolCalls: [], content: premature },
          { toolCalls: [], content: 'nunca chamado' },
        ],
        { inserts: [] },
        { maxToolIterations: 2, onComplete: () => { calls += 1 } },
      ),
      {
        userId: 'fixture-user',
        providerMessageId: 'mobile_flow/fixture-user/key-0931',
        text: 'Mostre meu progresso recente.',
        timestamp,
      },
    )
    expect(calls).toBe(3)
    expect(output.text).toBe(premature)
  })
})
