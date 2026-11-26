import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { bindConversationIntake } from './conversation-intake-contracts'
import { createSupabaseConversationTurnReplies } from './conversation-turn-replies'
import type { CurrentClinicalStateSource } from './current-clinical-state'
import type { FlowChatStore } from './flow-chat-service'

const ports = vi.hoisted(() => ({
  complete: vi.fn(),
  today: vi.fn(),
  store: vi.fn(),
}))
vi.mock('@mpp/providers', () => ({
  OpenRouterLLM: class {
    complete = ports.complete
  },
}))
vi.mock('./current-clinical-read-model', () => ({
  createCurrentClinicalReadModel: () => ({ todayWithEnergy: ports.today }),
}))
vi.mock('./flow-chat-service', async (original) => ({
  ...(await original<typeof import('./flow-chat-service')>()),
  createSupabaseFlowChatStore: ports.store,
}))

const owner = '00000000-0000-4000-8000-000000000014'
const epoch = '00000000-0000-4000-8000-000000000015'
const intakeID = '00000000-0000-4000-8000-000000000016'
const admitted = '2026-11-26T03:09:00.000Z'
const timezone = 'America/Sao_Paulo'
const audioAssetID = '00000000-0000-4000-8000-000000000018'
const clinical = { capture: vi.fn() } as unknown as CurrentClinicalStateSource
const auth = { userId: owner, patient: { timezone } } as MobileAuthContext
const walk = {
  id: '00000000-0000-4000-8000-000000000017',
  workout_type: 'caminhada',
  duration_min: 11,
  intensity: 'leve',
  estimated_kcal: 43,
  performed_at: '2026-11-26T02:40:00.000Z',
}

function providerInput(
  text: string,
  restricted = false,
  earlierQuestion?: string,
  channel: 'text' | 'audio' = 'text',
  assessment: 'complete' | 'incomplete' = 'complete',
  additionalMeals: { food_name: string; meal_type: string; kcal: number }[] = [],
) {
  const policy = {
    assessment,
    pause_weight_loss_guidance: restricted,
    hide: { calories: restricted },
  }
  ports.today.mockImplementation(async (_auth, _url, decorate) => {
    const day = {
      local_date: '2026-11-26',
      clinical_policy: policy,
      consumed: { calories_kcal: 0, protein_g: 0 },
      targets: { calories_kcal: null, protein_g: null },
      remaining_food_kcal: null,
      block_7700: { enabled: false },
      workouts: [],
      meals: [
        { food_name: 'feijão preto cozido', meal_type: 'cafe_manha', kcal: 115.5 },
        { food_name: 'farofa de mandioca temperada', meal_type: 'cafe_manha', kcal: 324.6 },
        ...additionalMeals,
      ],
    }
    return decorate ? decorate(owner, day) : day
  })
  const row = {
    id: intakeID,
    role: 'user',
    state: 'processing',
    content: text,
    createdAt: admitted,
    requestId: intakeID,
  } as const
  const store: FlowChatStore = {
    findInbound: async () => null,
    findAssistant: async () => null,
    loadHistory: async () => [],
    countRecentExecutions: async () => 0,
    insertInbound: async () => row,
    transitionInbound: async () => true,
    insertAssistant: async (value) => ({
      ...row,
      role: 'assistant',
      content: value.content,
      state: 'completed',
    }),
    completeInbound: async () => {},
    failInbound: async () => {},
  }
  ports.store.mockReturnValue(store)
  const query = (data: unknown[]) => ({
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    lt: vi.fn().mockReturnThis(),
    like: vi.fn().mockReturnThis(),
    neq: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockResolvedValue({ data, error: null }),
  })
  const workoutQuery = query([walk])
  const messageQuery = query(
    earlierQuestion
      ? [{ direction: 'in', content: earlierQuestion, created_at: '2026-11-26T02:45:00.000Z' }]
      : [],
  )
  const from = vi.fn((table: string) => (table === 'workout_logs' ? workoutQuery : messageQuery))
  const db = { from } as unknown as ServiceClient
  const intake = bindConversationIntake(owner, `cintake1:${intakeID}`, {
    intake_protocol: 'conversation.intake.v1',
    intake_id: intakeID,
    source:
      channel === 'audio'
        ? { channel: 'media', media_asset_id: audioAssetID, user_action: 'report_actual_record' }
        : { channel: 'text', text },
  })
  const binding = {
    owner_id: owner,
    intake_id: intakeID,
    input_hash: intake.inputHash,
    epoch,
    admitted_at: admitted,
  }
  const run = () =>
    createSupabaseConversationTurnReplies(db, auth, clinical).answer(
      {
        intake,
        binding,
        sourceHash: 'a'.repeat(64),
        context: {
          schema: 'conversation.intake-source.v1',
          ...binding,
          source_input: intake.input,
          captured_at: admitted,
          time_zone: timezone,
          local_date: '2026-11-26',
          media:
            channel === 'audio'
              ? {
                  asset_id: audioAssetID,
                  owner_id: owner,
                  kind: 'audio_note',
                  status: 'processed',
                  processed_at: admitted,
                  updated_at: admitted,
                  context_text: null,
                  processing_result: { text },
                }
              : null,
        },
      },
      'question',
      async () => {},
    )
  return { run, from, workoutQuery }
}

beforeEach(() => {
  vi.clearAllMocks()
  vi.stubEnv('OPENROUTER_API_KEY', 'qa-provider-key')
  ports.complete.mockResolvedValue({
    finishReason: 'stop',
    toolCalls: [],
    content: 'Resposta de QA.',
  })
})
afterEach(() => vi.unstubAllEnvs())

it.each([
  ['Como foi minha caminhada de 11 minutos?', undefined],
  ['E qual foi a intensidade?', 'Como foi minha caminhada de 11 minutos?'],
])('grounds an activity question in the owner’s recent official workouts: %s', async (text, prior) => {
  const { run, workoutQuery } = providerInput(text, false, prior)
  await run()
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(payload.context.recent_workouts).toEqual([
    {
      local_date: '2026-11-25',
      workout_type: 'caminhada',
      duration_min: 11,
      intensity: 'leve',
      estimated_kcal: 43,
    },
  ])
  expect(workoutQuery.eq).toHaveBeenCalledWith('user_id', owner)
  expect(workoutQuery.lt).toHaveBeenCalledWith('performed_at', admitted)
  if (prior) expect(payload.context.history[0].local_date).toBe('2026-11-25')
})

it.each([
  'text',
  'audio',
] as const)('grounds a %s current-day summary without old denials or unrelated workouts', async (channel) => {
  const { run, from } = providerInput(
    'Como esta meu dia ate agora?',
    false,
    'Hoje não comi 100 g de arroz.',
    channel,
  )
  await run()
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(payload.context.day.date).toBe('2026-11-26')
  expect(payload.context.history).toEqual([])
  expect(from).not.toHaveBeenCalledWith('messages')
  expect(from).not.toHaveBeenCalledWith('workout_logs')
  expect(payload.context.day).not.toHaveProperty('logged_foods')
})

it.each([
  ['O que comi hoje?', 'text', 'incomplete'],
  ['Quais alimentos eu registrei hoje?', 'audio', 'complete'],
] as const)('includes only official food names and meal types for a current-day food inquiry: %s', async (text, channel, assessment) => {
  const { run, from } = providerInput(
    text,
    false,
    'Hoje não comi 100 g de arroz.',
    channel,
    assessment,
  )
  await run()
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(payload.context.day.logged_foods).toEqual({
    items: [
      { food_name: 'feijão preto cozido', meal_type: 'cafe_manha' },
      { food_name: 'farofa de mandioca temperada', meal_type: 'cafe_manha' },
    ],
    truncated: false,
  })
  expect(payload.context.day.guidance_restricted).toBe(assessment === 'incomplete')
  expect(payload.context.history).toEqual([])
  expect(from).not.toHaveBeenCalled()
})

it('withholds food details when clinical protection is active', async () => {
  const { run } = providerInput('O que comi hoje?', true)
  await run()
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(payload.context.day.guidance_restricted).toBe(true)
  expect(payload.context.day).not.toHaveProperty('logged_foods')
})

it.each([
  ['Meu lanche?', 'text'],
  ['E o meu lanche de hoje', 'audio'],
] as const)('answers a short inquiry using only food already logged for that meal: %s', async (text, channel) => {
  const { run, from } = providerInput(text, false, undefined, channel, 'incomplete', [
    { food_name: 'banana', meal_type: 'lanche', kcal: 89 },
  ])
  const response = await run()
  expect(response.text).toBe('No lanche de hoje, você registrou banana.')
  expect(ports.complete).not.toHaveBeenCalled()
  expect(from).not.toHaveBeenCalled()
})

it('does not disclose an already logged snack when clinical protection is active', async () => {
  const { run } = providerInput('Meu lanche?', true, undefined, 'text', 'complete', [
    { food_name: 'banana', meal_type: 'lanche', kcal: 89 },
  ])
  const response = await run()
  expect(response.text).not.toContain('banana')
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(payload.context.day).not.toHaveProperty('logged_foods')
})

it('does not use breakfast food to fill a missing snack', async () => {
  const { run } = providerInput('Meu lanche?')
  expect((await run()).text).toBe('No lanche de hoje, ainda não encontrei itens no seu diário.')
  expect(ports.complete).not.toHaveBeenCalled()
})

it('does not substitute a current entry for an inquiry about a prior day', async () => {
  const { run } = providerInput('Meu lanche de ontem?', false, undefined, 'text', 'complete', [
    { food_name: 'banana', meal_type: 'lanche', kcal: 89 },
  ])
  await run()
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(payload.context.day).not.toHaveProperty('logged_foods')
})

it('preserves prior conversational context in a follow-up without a date', async () => {
  const previous = 'Quais foram as minhas refeições de ontem?'
  const { run } = providerInput('E o meu lanche?', false, previous, 'text', 'complete', [
    { food_name: 'banana', meal_type: 'lanche', kcal: 89 },
  ])
  await run()
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(payload.context.history[0].content).toBe(previous)
  expect(payload.context.day).not.toHaveProperty('logged_foods')
})

it.each([
  ['Como foi minha caminhada de 11 minutos?', true, undefined],
  [
    'Qual é a diferença entre proteína e carboidrato?',
    false,
    'Como foi minha caminhada de 11 minutos?',
  ],
])('does not read or share workout history when outside the reply scope: %s (%s)', async (text, restricted, earlierQuestion) => {
  const { run, from } = providerInput(text, restricted, earlierQuestion)
  await run()
  const payload = JSON.parse(ports.complete.mock.calls[0]?.[0].messages[0].content)
  expect(from).not.toHaveBeenCalledWith('workout_logs')
  expect(payload.context).not.toHaveProperty('recent_workouts')
})
