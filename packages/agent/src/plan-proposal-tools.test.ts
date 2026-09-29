import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  authorizeToolCall,
  draftRetryMessage,
  fakeWriteRetryAllowed,
  MOBILE_FLOW_DRAFT_TOOLS,
  MOBILE_FLOW_READ_ONLY_TOOLS,
  MOBILE_FLOW_TOOLS,
  mobileFlowSystemPolicy,
  selectPipelineTools,
} from './pipeline.js'
import { ALL_TOOLS, propoePlanoDieta, propoePlanoTreino } from './tools.js'
import type { ToolContext } from './tools.js'

const generateTrainingPlan = vi.hoisted(() => vi.fn())
const saveTrainingPlan = vi.hoisted(() => vi.fn())
const generateDietPlan = vi.hoisted(() => vi.fn())
const saveDietPlan = vi.hoisted(() => vi.fn())

vi.mock('./training-plan-generator.js', async (original) => ({
  ...(await original<typeof import('./training-plan-generator.js')>()),
  generateTrainingPlan,
  saveTrainingPlan,
}))
vi.mock('./diet-generator.js', async (original) => ({
  ...(await original<typeof import('./diet-generator.js')>()),
  generateDietPlan,
  saveDietPlan,
}))
vi.mock('./calc-config-loader.js', () => ({ loadCalcConfig: async () => ({}) }))
vi.mock('./calc-targets.js', async (original) => ({
  ...(await original<typeof import('./calc-targets.js')>()),
  loadDailyTargets: async () => ({ calories_target: 2000, protein_target: 140 }),
}))

const USER = '00000000-0000-4000-8000-00000000000a'
const TURN = `mobile_flow/${USER}/key-0001`
const DRAFT = '11111111-1111-4111-8111-111111111111'
const MESSAGE = '22222222-2222-4222-8222-222222222222'

const exercise = {
  name: 'Agachamento',
  muscle_group: 'pernas',
  sets: 4,
  reps_range: '8-12',
  rest_seconds: 90,
}
const trainingPlan = {
  user_id: USER,
  generated_at: '2026-09-28T12:00:00.000Z',
  plan_type: 'split' as const,
  days_per_week: 2,
  equipment_summary: 'halteres',
  weekly_schedule: [
    { day: 'seg', focus: 'inferiores', duration_min: 60, exercises: [exercise] },
    { day: 'qua', focus: 'superiores', duration_min: 50, exercises: [exercise] },
  ],
  progression_rule: 'subir carga a cada 2 semanas',
}
const dietPlan = {
  user_id: USER,
  generated_at: '2026-09-28T12:00:00.000Z',
  mode: 'referencia' as const,
  horizon: 'daily' as const,
  meta_kcal: 2000,
  meta_protein_g: 140,
  daily_meals: [
    {
      meal_type: 'almoco',
      items: [
        { food_name: 'arroz', quantity_g: 120, kcal: 150, protein_g: 3, carbs_g: 33, fat_g: 0.3 },
      ],
      total_kcal: 150,
      total_protein_g: 3,
    },
  ],
  shopping_list: [{ category: 'carboidratos', food_name: 'arroz', quantity_g: 840 }],
}

const trainingArguments = {
  available_equipment: ['halteres'],
  location: 'casa',
  days_per_week: 2,
  training_level: 'iniciante',
}

interface Recorded {
  inserts: Array<{ table: string; row: Record<string, unknown> }>
  rpcs: Array<{ name: string; params: Record<string, unknown> }>
  reads: string[]
}

function makeContext(options: {
  existingDraft?: { id: string; status: string } | null
  recentEvents?: number
  /** Events counted per name; overrides `recentEvents` for the names given. */
  eventsByName?: Record<string, number>
  openDrafts?: number
  insertError?: boolean
  providerMessageId?: string | undefined
  llm?: unknown
  rpcError?: boolean
} = {}): { ctx: ToolContext; recorded: Recorded } {
  const recorded: Recorded = { inserts: [], rpcs: [], reads: [] }
  const rows: Record<string, unknown> = {
    plan_drafts: options.existingDraft ?? null,
    messages: { id: MESSAGE },
    product_events: Array.from({ length: options.recentEvents ?? 0 }, (_, id) => ({ id })),
    users: { name: 'Pessoa sintética' },
    user_profiles: { sex: null, birth_date: null, weight_kg: 80, height_cm: 175 },
    user_progress: { current_bf_percent: null },
    meal_logs: [{ food_name: 'Arroz' }, { food_name: 'arroz ' }],
  }
  const from = (table: string) => {
    recorded.reads.push(table)
    const result: { data: unknown; error: null } = { data: rows[table] ?? null, error: null }
    const query = Promise.resolve(result) as Promise<typeof result> & Record<string, unknown>
    for (const method of ['select', 'eq', 'gte', 'order']) query[method] = () => query
    query.in = (column: string, values: string[]) => {
      if (table === 'product_events' && column === 'event' && options.eventsByName) {
        const count = values.reduce(
          (total, name) => total + (options.eventsByName?.[name] ?? 0),
          0,
        )
        result.data = Array.from({ length: count }, (_, id) => ({ id }))
      }
      return query
    }
    // `limit` is how the open drafts are counted; a single-row lookup
    // (maybeSingle) is the draft of this turn.
    query.limit = () => {
      if (table === 'plan_drafts') {
        result.data = Array.from({ length: options.openDrafts ?? 0 }, (_, id) => ({ id }))
      }
      return query
    }
    query.maybeSingle = async () => ({ data: rows[table] ?? null, error: null })
    query.insert = (row: Record<string, unknown>) => {
      recorded.inserts.push({ table, row })
      return Promise.resolve({
        data: null,
        error: options.insertError ? { message: 'insert failed' } : null,
      })
    }
    return query
  }
  const rpc = async (name: string, params: Record<string, unknown>) => {
    recorded.rpcs.push({ name, params })
    return options.rpcError
      ? { data: null, error: { code: 'PD429', message: 'limit' } }
      : { data: { id: DRAFT, status: params.p_status, inserted: true }, error: null }
  }
  const ctx = {
    supabase: { from, rpc },
    userId: USER,
    userWpp: '',
    llm: 'llm' in options ? options.llm : { complete: vi.fn() },
    providerMessageId: 'providerMessageId' in options ? options.providerMessageId : TURN,
    referenceTimestamp: new Date('2026-09-28T12:00:00.000Z'),
    assistantIdentity: 'flow',
  } as unknown as ToolContext
  return { ctx, recorded }
}

function expectNoPlanWrite(recorded: Recorded) {
  const tables = recorded.inserts.map((entry) => entry.table)
  expect(tables).not.toContain('training_plans')
  expect(tables).not.toContain('prescriptions')
  expect(tables).not.toContain('routine_items')
  const rpcs = recorded.rpcs.map((entry) => entry.name)
  expect(rpcs).not.toContain('save_training_plan_atomic')
  expect(rpcs.filter((name) => /confirm/i.test(name))).toEqual([])
  expect(saveTrainingPlan).not.toHaveBeenCalled()
  expect(saveDietPlan).not.toHaveBeenCalled()
}

afterEach(() => {
  vi.resetAllMocks()
})

describe('canal do app: o que o Flow pode chamar', () => {
  it('são as 4 consultas e as 2 propostas, e nada mais', () => {
    expect([...MOBILE_FLOW_TOOLS]).toEqual([
      'consulta_progresso',
      'consulta_metricas',
      'consulta_resumo_periodo',
      'consulta_reavaliacao_protocolo',
      'propoe_plano_treino',
      'propoe_plano_dieta',
    ])
    const names = selectPipelineTools(null, MOBILE_FLOW_TOOLS).map((tool) => tool.name)
    expect(names.sort()).toEqual([...MOBILE_FLOW_TOOLS].sort())
  })

  it('gera_* e qualquer gravação continuam recusadas pelo nome', () => {
    const mobile = selectPipelineTools(null, MOBILE_FLOW_TOOLS)
    for (const name of [
      'gera_treino',
      'gera_dieta',
      'registra_refeicao',
      'registra_treino',
      'cadastra_dados_iniciais',
      'define_protocolo',
      'define_meta_peso',
      'delete_user',
    ]) {
      expect(authorizeToolCall(name, mobile).status, name).toBe('not_authorized')
    }
  })

  it('não existe ferramenta de confirmação de plano em canal nenhum', () => {
    const confirming = ALL_TOOLS.map((tool) => tool.name).filter((name) =>
      /confirma.*(plano|rascunho|proposta|dieta|treino)|confirm.*(plan|draft)|ativa.*plano/i.test(
        name,
      ),
    )
    expect(confirming).toEqual([])
    // As propostas dizem, na própria descrição, que não são o plano.
    for (const tool of [propoePlanoTreino, propoePlanoDieta]) {
      expect(tool.description).toMatch(/rascunho: só vira plano quando o paciente\s+confirma no app/)
    }
    for (const name of [
      'confirma_plano',
      'confirma_rascunho',
      'confirm_plan_draft',
      'confirm_plan_draft_atomic',
      'confirma_plano_treino',
      'confirma_plano_dieta',
    ]) {
      expect(authorizeToolCall(name, selectPipelineTools(null, MOBILE_FLOW_TOOLS)).status).toBe(
        'unknown',
      )
    }
  })

  it('o WhatsApp não recebe as propostas, nem com "todas as ferramentas"', () => {
    const whatsapp = selectPipelineTools(null).map((tool) => tool.name)
    expect(whatsapp).toContain('gera_treino')
    expect(whatsapp).toContain('gera_dieta')
    for (const name of MOBILE_FLOW_DRAFT_TOOLS) expect(whatsapp).not.toContain(name)
    expect(selectPipelineTools(['propoe_plano_treino', 'gera_treino']).map((t) => t.name)).toEqual([
      'gera_treino',
    ])
    // A configuração só restringe: sem a ferramenta na lista, nem o app a recebe.
    expect(
      selectPipelineTools(['consulta_progresso'], MOBILE_FLOW_TOOLS).map((tool) => tool.name),
    ).toEqual(['consulta_progresso'])
  })

  it('plano inventado no texto é corrigido apontando para a proposta, nunca para gera_*', () => {
    const mobile = selectPipelineTools(null, MOBILE_FLOW_TOOLS)
    const readOnly = selectPipelineTools(null, MOBILE_FLOW_READ_ONLY_TOOLS)
    const whatsapp = selectPipelineTools(null)

    const training = draftRetryMessage('training_fake', mobile)
    const diet = draftRetryMessage('diet_fake', mobile)
    expect(training).toContain('propoe_plano_treino')
    expect(diet).toContain('propoe_plano_dieta')
    for (const message of [training, diet]) {
      expect(message).not.toMatch(/gera_(treino|dieta)/)
      expect(message).toContain('PROPOSTA')
    }
    expect(fakeWriteRetryAllowed('training_fake', mobile)).toBe(true)
    expect(fakeWriteRetryAllowed('registration', mobile)).toBe(false)

    expect(draftRetryMessage('training_fake', whatsapp)).toBeNull()
    expect(draftRetryMessage('diet_fake', readOnly)).toBeNull()
    expect(draftRetryMessage('registration', mobile)).toBeNull()
    expect(fakeWriteRetryAllowed('diet_fake', readOnly)).toBe(false)
  })

  it('a política do canal diz que proposta não é plano e que confirmar não é revisão', () => {
    expect(mobileFlowSystemPolicy).toContain('PROPOSTAS')
    expect(mobileFlowSystemPolicy).toMatch(/só\s+passa a valer depois que ele revisa e confirma no app/)
    expect(mobileFlowSystemPolicy).toMatch(/não é\s+revisão de um profissional/)
    expect(mobileFlowSystemPolicy).toMatch(/medicamentos, suplementos ou doses/)
  })
})

describe('propoe_plano_treino', () => {
  it('cria só o rascunho, com a origem e a chave do turno', async () => {
    generateTrainingPlan.mockResolvedValue(trainingPlan)
    const { ctx, recorded } = makeContext()

    const result = await propoePlanoTreino.execute(trainingArguments, ctx)

    expect(recorded.rpcs).toHaveLength(1)
    expect(recorded.rpcs[0]?.name).toBe('create_plan_draft_atomic')
    expect(recorded.rpcs[0]?.params).toMatchObject({
      p_user_id: USER,
      p_domain: 'training',
      p_origin: 'flow_generated',
      p_status: 'ready_for_review',
      p_source_media_asset_id: null,
      p_source_message_id: MESSAGE,
      p_request_key: `${TURN}:propoe_plano_treino`,
      p_uncertain_fields: [],
    })
    const payload = recorded.rpcs[0]?.params.p_payload as Record<string, unknown>
    expect(payload.weekly_schedule).toEqual(trainingPlan.weekly_schedule)
    expect(payload).not.toHaveProperty('user_id')
    expectNoPlanWrite(recorded)
    expect(generateTrainingPlan).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      expect.objectContaining({ identity: 'flow', userId: USER }),
    )
    expect(result).toMatchObject({ success: true, draft_id: DRAFT, domain: 'training' })
    expect(String(result.message)).toContain('RASCUNHO')
    expect(String(result.message)).toContain('Revisar proposta')
    expect(recorded.inserts.map((entry) => entry.row.event)).toEqual(['training.plan_proposed'])
  })

  it('plano do gerador fora da faixa vira rascunho incompleto, nunca ajustado', async () => {
    generateTrainingPlan.mockResolvedValue({
      ...trainingPlan,
      weekly_schedule: [
        { day: 'seg', focus: 'a', duration_min: 60, exercises: [{ ...exercise, sets: 40 }] },
      ],
    })
    const { ctx, recorded } = makeContext()

    const result = await propoePlanoTreino.execute(trainingArguments, ctx)

    expect(recorded.rpcs[0]?.params).toMatchObject({
      p_status: 'needs_completion',
      p_uncertain_fields: [
        { pointer: '/weekly_schedule/0/exercises/0/sets', reason: 'out_of_range' },
      ],
    })
    expect(result).toMatchObject({ success: true, status: 'needs_completion' })
    expectNoPlanWrite(recorded)
  })

  it('o mesmo turno de novo devolve o mesmo rascunho sem gerar nem gravar', async () => {
    const { ctx, recorded } = makeContext({
      existingDraft: { id: DRAFT, status: 'ready_for_review' },
    })

    const result = await propoePlanoTreino.execute(trainingArguments, ctx)

    expect(result).toMatchObject({ success: true, draft_id: DRAFT, replayed: true })
    expect(generateTrainingPlan).not.toHaveBeenCalled()
    expect(recorded.rpcs).toEqual([])
    expect(recorded.inserts).toEqual([])
  })

  it('respeita o limite de 1 por 24h somando gerações e propostas', async () => {
    const { ctx, recorded } = makeContext({ recentEvents: 1 })

    const result = await propoePlanoTreino.execute(trainingArguments, ctx)

    expect(result).toMatchObject({ success: false, retry_tool: false })
    expect(generateTrainingPlan).not.toHaveBeenCalled()
    expect(recorded.rpcs).toEqual([])
  })

  it('sem a chave do turno ou sem modelo, nada é gerado nem gravado', async () => {
    for (const options of [
      { providerMessageId: undefined },
      { providerMessageId: 'chave com espaço e acento é' },
      { llm: undefined },
    ]) {
      const { ctx, recorded } = makeContext(options)
      const result = await propoePlanoTreino.execute(trainingArguments, ctx)
      expect(result).toMatchObject({ success: false })
      expect(generateTrainingPlan).not.toHaveBeenCalled()
      expect(recorded.rpcs).toEqual([])
      expect(recorded.inserts).toEqual([])
    }
  })

  it('sem lugar para guardar a proposta, nada é gerado (nem pago)', async () => {
    generateTrainingPlan.mockResolvedValue(trainingPlan)
    for (const options of [
      { openDrafts: 20 },
      { eventsByName: { 'training.proposal_failed': 3 } },
    ]) {
      const { ctx, recorded } = makeContext(options)
      const result = await propoePlanoTreino.execute(trainingArguments, ctx)
      expect(result).toMatchObject({ success: false, retry_tool: false })
      expect(generateTrainingPlan).not.toHaveBeenCalled()
      expect(recorded.rpcs).toEqual([])
      expect(recorded.inserts).toEqual([])
    }

    const allowed = makeContext({
      openDrafts: 19,
      eventsByName: { 'training.proposal_failed': 2 },
    })
    expect(await propoePlanoTreino.execute(trainingArguments, allowed.ctx)).toMatchObject({
      success: true,
    })
  })

  // Staging 2026-09-28: after failed proposals the Flow told the patient to
  // "gerar pelo app diretamente", a path that does not exist.
  it('a falha diz ao modelo que não há outro caminho para gerar o plano', async () => {
    generateTrainingPlan.mockResolvedValueOnce(null)
    const failed = makeContext()
    const blocked = makeContext({ eventsByName: { 'training.proposal_failed': 3 } })
    for (const result of [
      await propoePlanoTreino.execute(trainingArguments, failed.ctx),
      await propoePlanoTreino.execute(trainingArguments, blocked.ctx),
    ]) {
      expect(result).toMatchObject({ success: false })
      expect(String((result as { error?: unknown }).error)).toContain(
        'Não sugira outro caminho, tela ou recurso para gerar o plano',
      )
    }
  })

  it('o evento que sustenta o limite precisa ser gravado', async () => {
    generateTrainingPlan.mockResolvedValue(trainingPlan)
    const { ctx } = makeContext({ insertError: true })
    await expect(propoePlanoTreino.execute(trainingArguments, ctx)).rejects.toThrow(
      'plan proposal event was not stored',
    )
  })

  it('rascunho do turno que já foi descartado não é anunciado como pronto', async () => {
    for (const status of ['discarded', 'expired', 'failed', 'confirmed']) {
      const { ctx, recorded } = makeContext({ existingDraft: { id: DRAFT, status } })
      const result = await propoePlanoTreino.execute(trainingArguments, ctx)
      expect(result, status).toMatchObject({ success: false, retry_tool: false })
      expect(result).not.toHaveProperty('draft_id')
      expect(generateTrainingPlan).not.toHaveBeenCalled()
      expect(recorded.rpcs).toEqual([])
    }
  })

  it('falha do gerador ou do banco não vira proposta; a falha de gravação é contada', async () => {
    generateTrainingPlan.mockResolvedValueOnce(null)
    const first = makeContext()
    expect(await propoePlanoTreino.execute(trainingArguments, first.ctx)).toMatchObject({
      success: false,
    })
    expect(first.recorded.rpcs).toEqual([])
    expect(first.recorded.inserts).toEqual([])

    generateTrainingPlan.mockResolvedValueOnce(trainingPlan)
    const second = makeContext({ rpcError: true })
    const result = await propoePlanoTreino.execute(trainingArguments, second.ctx)
    expect(result).toMatchObject({ success: false })
    expect(result).not.toHaveProperty('draft_id')
    expect(second.recorded.inserts.map((entry) => entry.row.event)).toEqual([
      'training.proposal_failed',
    ])
    expectNoPlanWrite(second.recorded)
  })
})

describe('propoe_plano_dieta', () => {
  it('cria só o rascunho de cardápio, com as metas oficiais lidas e nada recalculado', async () => {
    generateDietPlan.mockResolvedValue(dietPlan)
    const { ctx, recorded } = makeContext()

    const result = await propoePlanoDieta.execute({ horizon: 'daily' }, ctx)

    expect(recorded.rpcs).toHaveLength(1)
    expect(recorded.rpcs[0]?.params).toMatchObject({
      p_domain: 'nutrition',
      p_origin: 'flow_generated',
      p_status: 'ready_for_review',
      p_request_key: `${TURN}:propoe_plano_dieta`,
    })
    const payload = recorded.rpcs[0]?.params.p_payload as Record<string, unknown>
    expect(payload.daily_meals).toEqual(dietPlan.daily_meals)
    expect(payload.meta_kcal).toBe(2000)
    expect(generateDietPlan).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      expect.objectContaining({
        identity: 'flow',
        mode: 'referencia',
        historical_foods: [{ food_name: 'arroz', frequency: 2 }],
        profile: expect.objectContaining({ meta_kcal: 2000, meta_protein_g: 140 }),
      }),
    )
    expectNoPlanWrite(recorded)
    expect(result).toMatchObject({ success: true, draft_id: DRAFT, domain: 'nutrition' })
    expect(recorded.inserts.map((entry) => entry.row.event)).toEqual(['diet.proposed'])
  })

  it('respeita o limite de 2 em 2h somando gerações e propostas', async () => {
    const { ctx, recorded } = makeContext({ recentEvents: 2 })
    expect(await propoePlanoDieta.execute({}, ctx)).toMatchObject({ success: false })
    expect(generateDietPlan).not.toHaveBeenCalled()
    expect(recorded.rpcs).toEqual([])

    generateDietPlan.mockResolvedValue(dietPlan)
    const allowed = makeContext({ recentEvents: 1 })
    expect(await propoePlanoDieta.execute({}, allowed.ctx)).toMatchObject({ success: true })
  })
})
