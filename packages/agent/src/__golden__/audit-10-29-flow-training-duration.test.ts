/**
 * R353 connected QA recorded a request for 45 minutes and generated durations
 * [60, 60, 60, 50]. The generated exercise bodies were not retained here:
 * these controlled provider replies reproduce that duration vector, not a
 * recovered full model response. Never fix adherence by relabelling minutes.
 */
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
import { describe, expect, it } from 'vitest'
import { generateTrainingPlan, type TrainingGeneratorInput } from '../training-plan-generator.js'

const input: TrainingGeneratorInput & { duration_min: number } = {
  identity: 'flow',
  userId: 'synthetic-duration-qa',
  profile: {
    name: 'QA',
    sex: null,
    age: 30,
    weight_kg: 80,
    height_cm: 180,
    protocol: 'recomposicao',
    bf_percent: null,
    training_level: 'iniciante',
  },
  days_per_week: 4,
  training_days: ['seg', 'ter', 'qui', 'sex'],
  available_equipment: ['halteres', 'banco'],
  location: 'casa',
  duration_min: 45,
}

function fixture(minutes: number[]) {
  const schedule = minutes.map((duration_min, index) => ({
    day: ['seg', 'ter', 'qui', 'sex'][index],
    focus: 'Corpo inteiro',
    duration_min,
    exercises: [
      {
        name: 'Agachamento',
        muscle_group: 'pernas',
        sets: 3,
        reps_range: '10-12',
        rest_seconds: 90,
      },
    ],
  }))
  const requests: Array<{ messages: Array<{ content: unknown }>; maxRetries?: number }> = []
  const events: unknown[] = []
  const llm = {
    complete: async (request: (typeof requests)[number]) => {
      requests.push(request)
      return { content: JSON.stringify({ plan_type: 'full_body', weekly_schedule: schedule }) }
    },
  } as unknown as OpenRouterLLM
  const supabase = {
    from: (table: string) => {
      if (table !== 'product_events') throw new Error('Generator must not write a plan')
      return {
        insert: async (event: unknown) => {
          events.push(event)
          return { error: null }
        },
      }
    },
  } as unknown as ServiceClient
  return { llm, supabase, requests, events, schedule }
}

describe('audit 2026-10-29 — requested Flow training duration', () => {
  it('includes the requested 45 minutes in the provider input and preserves a matching plan', async () => {
    const f = fixture([45, 45, 45, 45])
    const plan = await generateTrainingPlan(f.llm, f.supabase, input)
    expect(String(f.requests[0]?.messages[0]?.content)).toContain('45 minutos')
    expect(plan?.weekly_schedule).toEqual(f.schedule)
    expect(f.events).toEqual([])
  })

  it('rejects the observed 60/60/60/50 response to a 45-minute request without relabelling or retry', async () => {
    const f = fixture([60, 60, 60, 50])
    expect(await generateTrainingPlan(f.llm, f.supabase, input)).toBeNull()
    expect(f.schedule.map((day) => day.duration_min)).toEqual([60, 60, 60, 50])
    expect(f.requests).toHaveLength(1)
    expect(f.requests[0]?.maxRetries).toBe(0)
    expect(f.events).toMatchObject([
      {
        event: 'training.generation_failed',
        properties: { reason: 'requested_duration_exceeded' },
      },
    ])
  })

  it('checks every session, including a last session that alone exceeds the limit', async () => {
    const f = fixture([45, 40, 35, 46])
    expect(await generateTrainingPlan(f.llm, f.supabase, input)).toBeNull()
  })

  it.each([
    [45, 45.4],
    [180, 180.4],
  ])('rejects a fractional excess before rounding can hide it: limit %s, generated %s', async (limit, generated) => {
    const f = fixture([limit, limit, limit, generated])
    expect(
      await generateTrainingPlan(f.llm, f.supabase, { ...input, duration_min: limit }),
    ).toBeNull()
    expect(f.schedule[3]?.duration_min).toBe(generated)
  })

  it('keeps shorter sessions as generated within the available time', async () => {
    const f = fixture([40, 45, 35, 45])
    expect((await generateTrainingPlan(f.llm, f.supabase, input))?.weekly_schedule).toEqual(
      f.schedule,
    )
  })

  it.each([
    0,
    9,
    181,
    45.5,
    Number.NaN,
  ])('refuses invalid requested minutes %s before a paid call', async (duration_min) => {
    const f = fixture([45, 45, 45, 45])
    expect(await generateTrainingPlan(f.llm, f.supabase, { ...input, duration_min })).toBeNull()
    expect(f.requests).toEqual([])
  })

  it.each([10, 180])('accepts the existing duration boundary %s', async (duration_min) => {
    const f = fixture([duration_min, duration_min, duration_min, duration_min])
    expect(
      (await generateTrainingPlan(f.llm, f.supabase, { ...input, duration_min }))?.weekly_schedule,
    ).toEqual(f.schedule)
  })

  it('preserves generated durations when the person did not specify a limit', async () => {
    const f = fixture([60, 60, 60, 50])
    const { duration_min: _, ...withoutDuration } = input
    expect(
      (await generateTrainingPlan(f.llm, f.supabase, withoutDuration))?.weekly_schedule,
    ).toEqual(f.schedule)
  })

  it('does not change the legacy request or interpretation for an app-only field', async () => {
    const f = fixture([60, 60, 60, 50])
    const plan = await generateTrainingPlan(f.llm, f.supabase, { ...input, identity: 'legacy' })
    expect(plan?.weekly_schedule).toEqual(f.schedule)
    expect(String(f.requests[0]?.messages[0]?.content)).not.toContain('45 minutos')
  })
})
