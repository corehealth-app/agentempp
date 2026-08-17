import { describe, expect, it } from 'vitest'
import { validateRegistraRefeicao } from './registra_refeicao-guard.js'

// biome-ignore lint/suspicious/noExplicitAny: mock supabase pra testes
function mockSupabase(
  recentMeals: Array<{ food_name: string; meal_type: string }> = [],
  errorMessage?: string,
): any {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            gte: () => ({
              limit: async () => ({
                data: errorMessage ? null : recentMeals,
                error: errorMessage ? { message: errorMessage } : null,
              }),
            }),
          }),
        }),
      }),
    }),
  }
}

describe('validateRegistraRefeicao — guard pós-LLM', () => {
  const baseCtx = { supabase: mockSupabase(), userId: 'u1' }

  it('R1: items=[] → reject empty_items', async () => {
    const r = await validateRegistraRefeicao({ meal_type: 'almoco', items: [] }, baseCtx)
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toBe('empty_items')
  })

  it('R1: items undefined → reject empty_items', async () => {
    const r = await validateRegistraRefeicao({ meal_type: 'almoco' }, baseCtx)
    expect(r.ok).toBe(false)
  })

  it('R2: total kcal > 5000 → reject implausible_total_kcal', async () => {
    const r = await validateRegistraRefeicao(
      {
        meal_type: 'almoco',
        items: [{ food_name: 'arroz', quantity_g: 100, kcal: 6000 }],
      },
      baseCtx,
    )
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toBe('implausible_total_kcal')
  })

  it('R2: total kcal ≤ 5000 passa', async () => {
    const r = await validateRegistraRefeicao(
      {
        meal_type: 'almoco',
        items: [{ food_name: 'arroz', quantity_g: 100, kcal: 130 }],
      },
      baseCtx,
    )
    expect(r.ok).toBe(true)
  })

  it('R3: duplicação >=50% → reject duplicate_recent', async () => {
    const ctx = {
      supabase: mockSupabase([
        { food_name: 'arroz', meal_type: 'almoco' },
        { food_name: 'feijão', meal_type: 'almoco' },
      ]),
      userId: 'u1',
    }
    const r = await validateRegistraRefeicao(
      {
        meal_type: 'almoco',
        items: [
          { food_name: 'arroz', quantity_g: 100 },
          { food_name: 'feijão', quantity_g: 80 },
        ],
      },
      ctx,
    )
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toBe('duplicate_recent')
  })

  it('R3: overlap <50% passa', async () => {
    const ctx = {
      supabase: mockSupabase([{ food_name: 'arroz', meal_type: 'almoco' }]),
      userId: 'u1',
    }
    const r = await validateRegistraRefeicao(
      {
        meal_type: 'almoco',
        items: [
          { food_name: 'arroz', quantity_g: 100 },
          { food_name: 'feijão', quantity_g: 80 },
          { food_name: 'frango', quantity_g: 150 },
        ],
      },
      ctx,
    )
    expect(r.ok).toBe(true)
  })

  it('R3: trustedTap=true bypassa duplicação (paciente clicou ciente)', async () => {
    const ctx = {
      supabase: mockSupabase([
        { food_name: 'arroz', meal_type: 'almoco' },
        { food_name: 'feijão', meal_type: 'almoco' },
      ]),
      userId: 'u1',
      trustedTap: true,
    }
    const r = await validateRegistraRefeicao(
      {
        meal_type: 'almoco',
        items: [
          { food_name: 'arroz', quantity_g: 100 },
          { food_name: 'feijão', quantity_g: 80 },
        ],
      },
      ctx,
    )
    expect(r.ok).toBe(true)
  })

  it('R3: falha fechada quando a consulta de duplicidade está indisponível', async () => {
    const ctx = {
      supabase: mockSupabase([], 'recent meal guard unavailable'),
      userId: 'u1',
    }

    await expect(
      validateRegistraRefeicao(
        {
          meal_type: 'almoco',
          items: [{ food_name: 'arroz', quantity_g: 100 }],
        },
        ctx,
      ),
    ).rejects.toThrow('recent meal guard unavailable')
  })
})
