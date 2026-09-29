/**
 * Golden test — training plan proposal cut by the output limit, staging
 * device gate of 2026-09-28 (QA account A, mobile Flow, backend 286c910).
 *
 * Exact scenario: "Monte um plano de treino pra mim: 4 dias por semana,
 * academia, foco em hipertrofia." → "Intermediário, treino há 2 anos. Sem
 * lesões." → "Academia completa. Pode montar a proposta." The generator
 * (anthropic/claude-sonnet-4.5, maxTokens 4500) returned indented JSON that
 * stopped mid-array; the log was
 *   [training-plan-generator] json_parse_error "Expected ',' or ']' after
 *   array element in JSON at position 13834 (line 391 column 10)"
 * and Flow answered "Deu um problema técnico aqui ao gerar a proposta".
 * No plan draft was created. The finish reason was not logged.
 *
 * On the mobile channel the generator now asks for compact JSON and allows a
 * longer answer; a cut answer is logged with its finish reason. The WhatsApp
 * (legacy) call is unchanged.
 */
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
import { describe, expect, it } from 'vitest'
import { generateTrainingPlan, type TrainingGeneratorInput } from '../training-plan-generator.js'

const INPUT: TrainingGeneratorInput = {
  userId: 'qa-a',
  profile: {
    name: 'QA',
    sex: 'masculino',
    age: 30,
    weight_kg: 103.4,
    height_cm: 180,
    protocol: 'ganho_massa',
    bf_percent: null,
    training_level: 'intermediario',
    limitations: [],
  },
  days_per_week: 4,
  available_equipment: [],
  location: 'academia_completa',
}

type Call = { maxTokens?: number; requestTimeoutMs?: number; maxRetries?: number; messages: Array<{ content: unknown }> }

function capture(content: string, finishReason = 'stop') {
  const calls: Call[] = []
  const events: Array<Record<string, unknown>> = []
  const llm = {
    complete: async (params: Call) => {
      calls.push(params)
      return { content, model: 'anthropic/claude-sonnet-4.5', finishReason }
    },
  } as unknown as OpenRouterLLM
  const supabase = {
    from: () => ({
      insert: async (row: Record<string, unknown>) => {
        events.push(row)
        return { error: null }
      },
    }),
  } as unknown as ServiceClient
  return { llm, supabase, calls, events }
}

// The cut answer: indented JSON that stops inside the exercises array.
const CUT = '{\n  "plan_type": "split",\n  "weekly_schedule": [\n    {\n      "day": "seg",\n      "exercises": [\n        { "name": "Supino reto" }'

describe('audit 2026-09-28 — Flow training plan cut by the output limit', () => {
  it('the mobile Flow asks for compact JSON with room for a 4-day plan', async () => {
    const { llm, supabase, calls } = capture(CUT, 'length')
    await generateTrainingPlan(llm, supabase, { ...INPUT, identity: 'flow' })
    expect(calls).toHaveLength(1)
    expect(calls[0]!.maxTokens).toBeGreaterThanOrEqual(8000)
    expect(String(calls[0]!.messages[0]!.content)).toMatch(/JSON compacto/)
    // Adversarial review: 8000 tokens do not fit the client's 90 s with a
    // silent retry; the call gets its own limit and is not repeated.
    expect(calls[0]!.requestTimeoutMs).toBe(120_000)
    expect(calls[0]!.maxRetries).toBe(0)
  })

  it('a cut answer is logged with finish_reason "length"', async () => {
    const { llm, supabase, events } = capture(CUT, 'length')
    const result = await generateTrainingPlan(llm, supabase, { ...INPUT, identity: 'flow' })
    expect(result).toBeNull()
    expect(events).toHaveLength(1)
    expect(events[0]).toMatchObject({
      event: 'training.generation_failed',
      properties: { finish_reason: 'length' },
    })
  })

  it('the WhatsApp (legacy) call keeps its limit and payload', async () => {
    const { llm, supabase, calls } = capture(CUT, 'length')
    await generateTrainingPlan(llm, supabase, INPUT)
    expect(calls[0]!.maxTokens).toBe(4500)
    expect(calls[0]!.requestTimeoutMs).toBeUndefined()
    expect(calls[0]!.maxRetries).toBeUndefined()
    expect(String(calls[0]!.messages[0]!.content)).not.toMatch(/JSON compacto/)
    expect(String(calls[0]!.messages[0]!.content).endsWith('Gere o plano em JSON.')).toBe(true)
  })
})

// Second attempt on the device (22:30 local, backend 57e0c20): the compact JSON
// arrived whole, then failed validation with
//   zod_validation_failed weekly_schedule.0.exercises.{0..3}.rpe_target
//   "Expected string, received number"
// The model wrote the RPE as a number (8). It is kept as text, as stored.
describe('audit 2026-09-28 — numeric RPE from the generator', () => {
  const exercise = (name: string, rpe: unknown) => ({
    name,
    muscle_group: 'peito',
    sets: 4,
    reps_range: '8-12',
    rest_seconds: 90,
    rpe_target: rpe,
  })
  const plan = (rpe: unknown) =>
    JSON.stringify({
      plan_type: 'split',
      weekly_schedule: [
        {
          day: 'seg',
          focus: 'Peito e tríceps',
          duration_min: 60,
          exercises: [
            exercise('Supino reto', rpe),
            exercise('Supino inclinado', rpe),
            exercise('Crucifixo', rpe),
            exercise('Tríceps corda', rpe),
          ],
        },
      ],
    })

  it('a numeric rpe_target is accepted and kept as text', async () => {
    const { llm, supabase, events } = capture(plan(8))
    const result = await generateTrainingPlan(llm, supabase, { ...INPUT, identity: 'flow' })
    expect(events).toHaveLength(0)
    expect(result?.weekly_schedule[0]?.exercises.map((e) => e.rpe_target)).toEqual(['8', '8', '8', '8'])
  })

  it('a decimal RPE keeps its value and a text RPE is unchanged', async () => {
    const decimal = await generateTrainingPlan(capture(plan(7.5)).llm, capture('').supabase, INPUT)
    expect(decimal?.weekly_schedule[0]?.exercises[0]?.rpe_target).toBe('7.5')
    const text = await generateTrainingPlan(capture(plan('RPE 8')).llm, capture('').supabase, INPUT)
    expect(text?.weekly_schedule[0]?.exercises[0]?.rpe_target).toBe('RPE 8')
  })

  // Adversarial review: same failure class on neighbouring fields.
  it('numeric reps, fractional seconds/minutes and null optionals no longer refuse the plan', async () => {
    const body = JSON.parse(plan(8))
    const ex = body.weekly_schedule[0].exercises[0]
    ex.reps_range = 12
    ex.rest_seconds = 90.5
    ex.notes = null
    ex.execution_steps = null
    body.weekly_schedule[0].duration_min = 45.5
    body.progression_rule = null
    const { llm, supabase, events } = capture(JSON.stringify(body))
    const result = await generateTrainingPlan(llm, supabase, INPUT)
    expect(events).toHaveLength(0)
    const day = result!.weekly_schedule[0]!
    expect(day.duration_min).toBe(46)
    expect(day.exercises[0]).toMatchObject({ reps_range: '12', rest_seconds: 91, rpe_target: '8' })
    expect(day.exercises[0]).not.toHaveProperty('notes')
  })

  it('the shared schema is unchanged: a numeric RPE is still invalid for document import', async () => {
    const { TrainingDaySchema } = await import('../training-plan-generator.js')
    const day = JSON.parse(plan(9)).weekly_schedule[0]
    expect(TrainingDaySchema.safeParse(day).success).toBe(false)
  })

  it('a non-finite or non-scalar RPE is still refused', async () => {
    for (const bad of [{ value: 8 }, [8], true]) {
      const { llm, supabase } = capture(plan(bad))
      expect(await generateTrainingPlan(llm, supabase, INPUT)).toBeNull()
    }
  })
})
