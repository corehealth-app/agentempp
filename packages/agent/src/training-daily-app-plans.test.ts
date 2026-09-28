import { describe, expect, it } from 'vitest'
import { getTodayTraining, isAppConfirmedTrainingPlan } from './training-plan-generator.js'

function supabase(row: Record<string, unknown> | null) {
  const selected: string[] = []
  const query = {
    select(columns: string) {
      selected.push(columns)
      return query
    },
    eq: () => query,
    order: () => query,
    limit: () => query,
    maybeSingle: async () => ({ data: row, error: null }),
  }
  return { client: { from: () => query } as never, selected }
}

const schedule = [{ day: 'seg', focus: 'inferiores', duration_min: 60, exercises: [] }]

describe('entrega diária de treino pelo WhatsApp', () => {
  it('envia o plano gerado no WhatsApp', async () => {
    const { client, selected } = supabase({
      id: 'plan-1',
      weekly_schedule: schedule,
      generated_by: 'agent',
    })
    await expect(getTodayTraining(client, 'user-1', 'seg')).resolves.toEqual({
      plan_id: 'plan-1',
      day: schedule[0],
    })
    expect(selected[0]).toContain('generated_by')
  })

  it('não envia um plano confirmado no app, mesmo com a entrega ligada', async () => {
    for (const generatedBy of [
      'flow_draft',
      'flow_draft_edited',
      'patient_import',
      'patient_import_edited',
    ]) {
      const { client } = supabase({ id: 'plan-2', weekly_schedule: schedule, generated_by: generatedBy })
      await expect(getTodayTraining(client, 'user-1', 'seg'), generatedBy).resolves.toBeNull()
    }
  })

  it('reconhece só as origens do app', () => {
    expect(isAppConfirmedTrainingPlan('agent')).toBe(false)
    expect(isAppConfirmedTrainingPlan(null)).toBe(false)
    expect(isAppConfirmedTrainingPlan('professional')).toBe(false)
    expect(isAppConfirmedTrainingPlan('flow_draft_edited_x')).toBe(false)
  })
})
