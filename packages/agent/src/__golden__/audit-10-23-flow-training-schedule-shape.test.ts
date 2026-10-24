/**
 * Public Flow QA C, 2026-10-23: an explicit four-day request returned no draft.
 * The staging receipt recorded zod_validation_failed at weekly_schedule.4/5
 * (duration_min and exercises). The generated raw values were not retained:
 * the invalid trailing entries below are synthetic, not a recovered model reply.
 * Keep strict rejection and make the generator's active-day contract explicit.
 */
import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
import { describe, expect, it } from 'vitest'
import {
  generateTrainingPlan,
  type TrainingGeneratorInput,
  trainingSystemPrompt,
} from '../training-plan-generator.js'

const trainingDays = ['seg', 'ter', 'qui', 'sex']
const input: TrainingGeneratorInput = {
  userId: 'synthetic-qa-c',
  identity: 'flow',
  profile: {
    name: 'QA',
    sex: 'masculino',
    age: 30,
    weight_kg: 80,
    height_cm: 180,
    protocol: 'recomposicao',
    bf_percent: null,
    training_level: 'iniciante',
  },
  days_per_week: 4,
  training_days: trainingDays,
  available_equipment: ['halteres', 'barras', 'banco', 'máquinas', 'polias'],
  location: 'academia_completa',
  goes_to_failure: false,
}
const schedule = trainingDays.map((day) => ({
  day,
  focus: 'Corpo inteiro',
  duration_min: 45,
  exercises: [
    { name: 'Agachamento', muscle_group: 'pernas', sets: 3, reps_range: '10-12', rest_seconds: 90 },
  ],
}))
function capture(weekly_schedule: unknown) {
  const calls: Array<{
    systemPrompt: string
    messages: Array<{ content: unknown }>
    maxRetries?: number
  }> = []
  const events: unknown[] = []
  const llm = {
    complete: async (params: (typeof calls)[number]) => {
      calls.push(params)
      return {
        content: JSON.stringify({ plan_type: 'full_body', weekly_schedule }),
        finishReason: 'stop',
      }
    },
  } as unknown as OpenRouterLLM
  const supabase = {
    from: () => ({
      insert: async (event: unknown) => {
        events.push(event)
        return { error: null }
      },
    }),
  } as unknown as ServiceClient
  return { llm, supabase, calls, events }
}

describe('audit 2026-10-23 — Flow active training schedule contract', () => {
  it('asks for exactly the requested active days, with rest outside the schedule', async () => {
    const c = capture(schedule)
    await generateTrainingPlan(c.llm, c.supabase, input)
    expect(c.calls).toHaveLength(1)
    expect(c.calls[0]?.systemPrompt).toContain('weekly_schedule contém somente dias de treino')
    expect(c.calls[0]?.systemPrompt).toContain('exatamente days_per_week entradas')
    expect(c.calls[0]?.systemPrompt).toContain('Descanso semanal fica somente em notes')
    expect(String(c.calls[0]?.messages[0]?.content)).toContain('4 (seg/ter/qui/sex)')
    expect(c.calls[0]?.maxRetries).toBe(0)
  })
  it('preserves all four valid days and their exercises without changing quantities', async () => {
    const c = capture(schedule)
    const plan = await generateTrainingPlan(c.llm, c.supabase, input)
    expect(plan?.weekly_schedule).toEqual(schedule)
    expect(plan?.days_per_week).toBe(4)
    expect(c.events).toEqual([])
  })
  it('continues rejecting invalid trailing entries rather than trimming a generated plan', async () => {
    const c = capture([
      ...schedule,
      { day: 'sab', focus: 'Descanso', duration_min: 0, exercises: [] },
      { day: 'dom', focus: 'Descanso', duration_min: 0, exercises: [] },
    ])
    expect(await generateTrainingPlan(c.llm, c.supabase, input)).toBeNull()
    expect(c.calls).toHaveLength(1)
    expect(c.events).toMatchObject([
      { event: 'training.generation_failed', properties: { reason: 'zod_validation_failed' } },
    ])
  })
  it('keeps the legacy prompt byte for byte', () => {
    expect(createHash('sha256').update(trainingSystemPrompt('legacy')).digest('hex')).toBe(
      '19bb8a14a93e85d499497c8cb7a0e9c25ce12bab11b7d03dcd36ba4d45f84f5c',
    )
    expect(trainingSystemPrompt()).toBe(trainingSystemPrompt('legacy'))
  })
})
