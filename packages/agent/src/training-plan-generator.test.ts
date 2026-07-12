import { describe, expect, it } from 'vitest'
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
import {
  getTodayTraining,
  generateTrainingPlan,
  saveTrainingPlan,
  type TrainingDay,
  type TrainingGeneratorInput,
} from './training-plan-generator.js'

function mockLLM(returnText: string): OpenRouterLLM {
  return {
    complete: async () => ({ content: returnText, model: 'mock', stop_reason: 'end_turn' }),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  } as any
}

const VALID_TRAIN_INPUT: TrainingGeneratorInput = {
  userId: 'u-1',
  profile: {
    name: 'Paciente',
    sex: 'masculino',
    age: 30,
    weight_kg: 80,
    height_cm: 175,
    protocol: 'recomposicao',
    bf_percent: 22,
    training_level: 'intermediario',
  },
  days_per_week: 3,
  available_equipment: ['halteres 5-30kg', 'barra fixa'],
  location: 'casa',
}

const VALID_TRAIN_LLM_OUTPUT = JSON.stringify({
  plan_type: 'split',
  weekly_schedule: [
    {
      day: 'seg',
      focus: 'Inferiores',
      duration_min: 60,
      exercises: [
        {
          name: 'Agachamento',
          muscle_group: 'glúteos',
          sets: 4,
          reps_range: '8-12',
          rest_seconds: 90,
        },
      ],
    },
  ],
  progression_rule: 'Adicione 1 rep por treino.',
})

function makeMockSupabase(returns: {
  data: { id: string; weekly_schedule: unknown } | null
  error?: { message: string } | null
}): ServiceClient {
  const chain = {
    select: () => chain,
    eq: () => chain,
    order: () => chain,
    limit: () => chain,
    maybeSingle: async () => returns,
  }
  return {
    from: () => chain,
  } as unknown as ServiceClient
}

const SAMPLE_DAY: TrainingDay = {
  day: 'seg',
  focus: 'Inferiores',
  duration_min: 60,
  exercises: [
    {
      name: 'Agachamento livre',
      muscle_group: 'glúteos+quadríceps',
      sets: 4,
      reps_range: '8-12',
      rest_seconds: 90,
    },
  ],
}

const SAMPLE_WED: TrainingDay = {
  day: 'qua',
  focus: 'Empurrar',
  duration_min: 60,
  exercises: [
    {
      name: 'Supino reto',
      muscle_group: 'peitoral',
      sets: 4,
      reps_range: '6-10',
      rest_seconds: 90,
    },
  ],
}

describe('getTodayTraining', () => {
  it('retorna treino do dia quando label bate', async () => {
    const supa = makeMockSupabase({
      data: {
        id: 'plan-1',
        weekly_schedule: [SAMPLE_DAY, SAMPLE_WED],
      },
    })
    const result = await getTodayTraining(supa, 'user-1', 'seg')
    expect(result).not.toBeNull()
    expect(result?.plan_id).toBe('plan-1')
    expect(result?.day.focus).toBe('Inferiores')
    expect(result?.day.exercises.length).toBe(1)
  })

  it('retorna null quando hoje não é dia de treino', async () => {
    const supa = makeMockSupabase({
      data: {
        id: 'plan-1',
        weekly_schedule: [SAMPLE_DAY, SAMPLE_WED],
      },
    })
    const result = await getTodayTraining(supa, 'user-1', 'dom')
    expect(result).toBeNull()
  })

  it('retorna null quando paciente não tem plano ativo', async () => {
    const supa = makeMockSupabase({ data: null })
    const result = await getTodayTraining(supa, 'user-1', 'seg')
    expect(result).toBeNull()
  })

  it('propaga erro ao consultar o plano ativo', async () => {
    const supa = makeMockSupabase({
      data: null,
      error: { message: 'training plan query failed' },
    })

    await expect(getTodayTraining(supa, 'user-1', 'seg')).rejects.toThrow(
      'training plan query failed',
    )
  })

  it('retorna null quando weekly_schedule não é array (corrupto)', async () => {
    const supa = makeMockSupabase({
      data: { id: 'plan-1', weekly_schedule: { not: 'an array' } },
    })
    const result = await getTodayTraining(supa, 'user-1', 'seg')
    expect(result).toBeNull()
  })

  it('retorna null quando weekly_schedule é null', async () => {
    const supa = makeMockSupabase({
      data: { id: 'plan-1', weekly_schedule: null },
    })
    const result = await getTodayTraining(supa, 'user-1', 'seg')
    expect(result).toBeNull()
  })

  it('matches por day_label exato (case-sensitive)', async () => {
    const supa = makeMockSupabase({
      data: {
        id: 'plan-1',
        weekly_schedule: [SAMPLE_DAY],
      },
    })
    expect(await getTodayTraining(supa, 'user-1', 'SEG')).toBeNull()
    expect((await getTodayTraining(supa, 'user-1', 'seg'))?.plan_id).toBe('plan-1')
  })
})

describe('generateTrainingPlan — pipeline com mock LLM', () => {
  const mockSupa = {} as ServiceClient

  it('aceita output bem formado e retorna TrainingPlan', async () => {
    const llm = mockLLM(VALID_TRAIN_LLM_OUTPUT)
    const result = await generateTrainingPlan(llm, mockSupa, VALID_TRAIN_INPUT)
    expect(result).not.toBeNull()
    expect(result?.plan_type).toBe('split')
    expect(result?.weekly_schedule.length).toBe(1)
    expect(result?.weekly_schedule[0]?.focus).toBe('Inferiores')
  })

  it('rejeita JSON inválido', async () => {
    const llm = mockLLM('isso não é JSON')
    const result = await generateTrainingPlan(llm, mockSupa, VALID_TRAIN_INPUT)
    expect(result).toBeNull()
  })

  it('rejeita weekly_schedule vazio', async () => {
    const llm = mockLLM(JSON.stringify({ plan_type: 'split', weekly_schedule: [] }))
    const result = await generateTrainingPlan(llm, mockSupa, VALID_TRAIN_INPUT)
    expect(result).toBeNull()
  })

  it('rejeita exercise sem nome', async () => {
    const llm = mockLLM(
      JSON.stringify({
        weekly_schedule: [
          {
            day: 'seg',
            focus: 'X',
            duration_min: 60,
            exercises: [{ name: '', muscle_group: 'g', sets: 3, reps_range: '8-12', rest_seconds: 60 }],
          },
        ],
      }),
    )
    const result = await generateTrainingPlan(llm, mockSupa, VALID_TRAIN_INPUT)
    expect(result).toBeNull()
  })

  it('rejeita sets fora da faixa (sets=20)', async () => {
    const llm = mockLLM(
      JSON.stringify({
        weekly_schedule: [
          {
            day: 'seg',
            focus: 'X',
            duration_min: 60,
            exercises: [
              { name: 'agachamento', muscle_group: 'g', sets: 20, reps_range: '8-12', rest_seconds: 60 },
            ],
          },
        ],
      }),
    )
    const result = await generateTrainingPlan(llm, mockSupa, VALID_TRAIN_INPUT)
    expect(result).toBeNull()
  })

  it('rejeita duration_min fora da faixa (180+)', async () => {
    const llm = mockLLM(
      JSON.stringify({
        weekly_schedule: [
          {
            day: 'seg',
            focus: 'X',
            duration_min: 999,
            exercises: [
              { name: 'agachamento', muscle_group: 'g', sets: 3, reps_range: '8-12', rest_seconds: 60 },
            ],
          },
        ],
      }),
    )
    const result = await generateTrainingPlan(llm, mockSupa, VALID_TRAIN_INPUT)
    expect(result).toBeNull()
  })

  it('usa progression_rule default quando ausente', async () => {
    const llm = mockLLM(
      JSON.stringify({
        weekly_schedule: [
          {
            day: 'seg',
            focus: 'X',
            duration_min: 60,
            exercises: [
              { name: 'agachamento', muscle_group: 'g', sets: 3, reps_range: '8-12', rest_seconds: 60 },
            ],
          },
        ],
      }),
    )
    const result = await generateTrainingPlan(llm, mockSupa, VALID_TRAIN_INPUT)
    expect(result?.progression_rule).toMatch(/Adicione 1 rep/)
  })
})

describe('saveTrainingPlan — persistência atômica', () => {
  it('usa uma única RPC e envia a chave idempotente da mensagem', async () => {
    const calls: Array<{ name: string; params: Record<string, unknown> }> = []
    const supabase = {
      rpc: async (name: string, params: Record<string, unknown>) => {
        calls.push({ name, params })
        return { data: { plan_id: 'plan-1', inserted: true }, error: null }
      },
      from: () => {
        throw new Error('saveTrainingPlan must not issue separate table writes')
      },
    }

    const saved = await saveTrainingPlan(
      supabase as never,
      {
        user_id: 'user-1',
        generated_at: '2026-07-12T12:00:00.000Z',
        plan_type: 'split',
        days_per_week: 3,
        equipment_summary: 'halteres, barra fixa',
        weekly_schedule: [SAMPLE_DAY],
        progression_rule: 'Adicione uma repetição por treino.',
      },
      'provider-message-1',
    )

    expect(saved).toEqual({ id: 'plan-1' })
    expect(calls).toEqual([
      {
        name: 'save_training_plan_atomic',
        params: expect.objectContaining({
          p_user_id: 'user-1',
          p_request_key: 'provider-message-1',
          p_days_per_week: 3,
        }),
      },
    ])
  })

  it('não chama o banco quando generated_at é inválido', async () => {
    let rpcCalled = false
    const supabase = {
      rpc: async () => {
        rpcCalled = true
        return { data: null, error: null }
      },
    }

    const saved = await saveTrainingPlan(
      supabase as never,
      {
        user_id: 'user-1',
        generated_at: 'invalid-date',
        plan_type: 'split',
        days_per_week: 3,
        equipment_summary: 'halteres',
        weekly_schedule: [SAMPLE_DAY],
        progression_rule: 'Adicione uma repetição por treino.',
      },
      'provider-message-2',
    )

    expect(saved).toEqual({ id: null })
    expect(rpcCalled).toBe(false)
  })
})
