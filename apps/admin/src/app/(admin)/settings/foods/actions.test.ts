import { beforeEach, describe, expect, it, vi } from 'vitest'

// As ações de Banco de alimentos ficam atrás da tela /settings/foods: só passa
// quem pode abri-la. Até 2026-10-05 elas não conferiam sessão nem papel e
// gravavam em food_db com a chave de serviço para qualquer chamada.

const state = vi.hoisted(() => ({
  user: null as { id: string; email: string } | null,
  adminRow: null as { id: string; email: string; name: string | null; role: string } | null,
  /** Cada operação feita com a chave de serviço: "tabela.operação". */
  serviceOps: [] as string[],
  revalidated: [] as string[],
}))

vi.mock('next/navigation', () => ({
  redirect: (url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  },
}))
vi.mock('next/cache', () => ({
  revalidatePath: (path: string) => {
    state.revalidated.push(path)
  },
}))

vi.mock('@/lib/supabase/server', () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: state.user } }) },
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: state.adminRow, error: null }) }),
      }),
    }),
  }),
  // food_db falso: uma referência NÃO verificada, que aceita gravar e apagar.
  createServiceClient: () => ({
    from: (table: string) => {
      const row = { id: 7, is_verified: false }
      const step = (op: string) => {
        state.serviceOps.push(`${table}.${op}`)
        const chain = {
          eq: () => chain,
          select: () => chain,
          maybeSingle: async () => ({ data: row, error: null }),
        }
        return chain
      }
      return {
        select: () => step('select'),
        update: () => step('update'),
        delete: () => step('delete'),
        insert: async () => {
          state.serviceOps.push(`${table}.insert`)
          return { error: null }
        },
      }
    },
  }),
}))

import { deleteFood, type FoodInput, upsertFood } from './actions'

const FOOD: FoodInput = {
  name_pt: 'Ovo cozido',
  category: 'ovos',
  kcal_per_100g: 155,
  protein_g: 13,
  carbs_g: 1.1,
  fat_g: 11,
  fiber_g: 0,
  country_code: 'BR',
  source: null,
}

function signIn(role: string | null) {
  state.user = { id: 'admin-1', email: 'pessoa@exemplo.com' }
  state.adminRow = role
    ? { id: 'admin-1', email: 'pessoa@exemplo.com', name: 'Pessoa', role }
    : null
}

beforeEach(() => {
  state.user = null
  state.adminRow = null
  state.serviceOps = []
  state.revalidated = []
})

describe('Banco de alimentos — quem pode gravar e apagar', () => {
  it('sem sessão: recusa as duas ações e não toca no banco', async () => {
    await expect(upsertFood(FOOD)).resolves.toEqual({ ok: false, error: 'Não autenticado' })
    await expect(upsertFood({ ...FOOD, id: 7 })).resolves.toEqual({
      ok: false,
      error: 'Não autenticado',
    })
    await expect(deleteFood(7)).resolves.toEqual({ ok: false, error: 'Não autenticado' })
    expect(state.serviceOps).toEqual([])
    expect(state.revalidated).toEqual([])
  })

  it('content_editor (não abre a tela): recusa as duas ações e não toca no banco', async () => {
    signIn('content_editor')
    await expect(upsertFood(FOOD)).resolves.toEqual({ ok: false, error: 'Acesso negado' })
    await expect(upsertFood({ ...FOOD, id: 7 })).resolves.toEqual({
      ok: false,
      error: 'Acesso negado',
    })
    await expect(deleteFood(7)).resolves.toEqual({ ok: false, error: 'Acesso negado' })
    expect(state.serviceOps).toEqual([])
    expect(state.revalidated).toEqual([])
  })

  it('conta logada que não é administradora (ex.: uma conta do app): recusa', async () => {
    signIn(null)
    await expect(upsertFood(FOOD)).resolves.toEqual({ ok: false, error: 'Acesso negado' })
    await expect(deleteFood(7)).resolves.toEqual({ ok: false, error: 'Acesso negado' })
    signIn('viewer')
    await expect(upsertFood(FOOD)).resolves.toEqual({ ok: false, error: 'Acesso negado' })
    expect(state.serviceOps).toEqual([])
  })

  it.each([
    'support',
    'nutrition_admin',
    'operations_admin',
    'master_admin',
  ])('%s (abre a tela): cria, edita e apaga como antes', async (role) => {
    signIn(role)

    await expect(upsertFood(FOOD)).resolves.toEqual({ ok: true })
    expect(state.serviceOps).toEqual(['food_db.insert'])

    state.serviceOps = []
    await expect(upsertFood({ ...FOOD, id: 7 })).resolves.toEqual({ ok: true })
    expect(state.serviceOps).toEqual(['food_db.select', 'food_db.update'])

    state.serviceOps = []
    await expect(deleteFood(7)).resolves.toEqual({ ok: true })
    expect(state.serviceOps).toEqual(['food_db.select', 'food_db.delete'])

    expect(state.revalidated).toEqual(['/settings/foods', '/settings/foods', '/settings/foods'])
  })
})
