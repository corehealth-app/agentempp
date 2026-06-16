import { describe, expect, it } from 'vitest'
import { validateMarcaRefeicaoPulada } from './marca_refeicao_pulada-guard.js'

// biome-ignore lint/suspicious/noExplicitAny: mock supabase pra testes
function mockSupabase(existingMealLogsCount: number = 0): any {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            gte: async () => ({ count: existingMealLogsCount }),
          }),
        }),
      }),
    }),
  }
}

describe('validateMarcaRefeicaoPulada — guard pós-LLM', () => {
  it('passa quando sem vision pendente e sem meal_logs', async () => {
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      { supabase: mockSupabase(0), userId: 'u1' },
    )
    expect(r.ok).toBe(true)
  })

  it('S1: vision pendente recente do MESMO meal_type → reject', async () => {
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      {
        supabase: mockSupabase(0),
        userId: 'u1',
        visionPending: {
          mealContext: 'jantar com pão e queijo',
          ageMinutes: 30,
          items: [{ name: 'pão' }],
        },
      },
    )
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toBe('skip_blocked_vision_pending')
  })

  it('S1: vision contexto diferente do skip → permite', async () => {
    // foto de café, paciente pula jantar — refeições diferentes, OK skip
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      {
        supabase: mockSupabase(0),
        userId: 'u1',
        visionPending: {
          mealContext: 'café da manhã com pão',
          ageMinutes: 30,
          items: [{ name: 'pão' }],
        },
      },
    )
    expect(r.ok).toBe(true)
  })

  it('S1: vision > 4h → considera abandonada, permite skip', async () => {
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      {
        supabase: mockSupabase(0),
        userId: 'u1',
        visionPending: {
          mealContext: 'jantar com pão',
          ageMinutes: 300, // 5h
          items: [{ name: 'pão' }],
        },
      },
    )
    expect(r.ok).toBe(true)
  })

  it('S3: já há meal_logs do mesmo meal_type hoje → reject skip_after_registration', async () => {
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'almoco' },
      { supabase: mockSupabase(3), userId: 'u1' },
    )
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toBe('skip_after_registration')
  })
})
