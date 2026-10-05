import { beforeEach, describe, expect, it, vi } from 'vitest'

// As ações do Playground ficam atrás da tela /prompts/playground: só passa
// quem pode abri-la, E quem já estava na lista da ação (AI_PLAYGROUND_ROLES).
// Até 2026-10-05 o content_editor passava aqui sem poder abrir a tela:
// runPlayground roda o motor legado como a conta daquele número e
// resetPlaygroundUser APAGA a conta daquele número.

const state = vi.hoisted(() => ({
  user: null as { id: string; email: string } | null,
  adminRow: null as { id: string; email: string; name: string | null; role: string } | null,
  /** Cada operação feita com a chave de serviço: "tabela.operação". */
  serviceOps: [] as string[],
  engineCalls: [] as Array<{ from: string; text: string; provider: string }>,
}))

vi.mock('next/navigation', () => ({
  redirect: (url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  },
}))

// O motor e o provedor não rodam: interessa SE foram chamados.
vi.mock('@mpp/agent', () => ({
  processMessage: async (
    _deps: unknown,
    input: { from: string; text: string; provider: string },
  ) => {
    state.engineCalls.push({ from: input.from, text: input.text, provider: input.provider })
    return {
      text: 'resposta do motor',
      stage: 'manutencao',
      modelUsed: 'modelo-de-teste',
      promptTokens: 10,
      completionTokens: 5,
      costUsd: 0.001,
      latencyMs: 12,
      toolCalls: [{ name: 'consulta_progresso' }, { name: 'registra_refeicao', error: 'x' }],
    }
  },
}))
vi.mock('@mpp/providers', () => ({ OpenRouterLLM: class {} }))

vi.mock('@/lib/supabase/server', () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: state.user } }) },
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: state.adminRow, error: null }) }),
      }),
    }),
  }),
  createServiceClient: () => ({
    from: (table: string) => ({
      select: () => {
        state.serviceOps.push(`${table}.select`)
        const data = table === 'users' ? { id: 'conta-1' } : { value: 'chave-de-teste' }
        const chain = {
          eq: () => chain,
          maybeSingle: async () => ({ data, error: null }),
        }
        return chain
      },
      delete: () => ({
        eq: async () => {
          state.serviceOps.push(`${table}.delete`)
          return { error: null }
        },
      }),
    }),
  }),
}))

import { resetPlaygroundUser, runPlayground } from './actions'

const WPP = '5511999999999'

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
  state.engineCalls = []
})

describe('Playground — quem pode rodar o motor e apagar a conta de teste', () => {
  it('sem sessão: recusa as duas ações, não roda o motor e não apaga nada', async () => {
    await expect(runPlayground({ from: WPP, text: 'oi' })).resolves.toEqual({
      error: 'Não autenticado',
    })
    await expect(resetPlaygroundUser(WPP)).resolves.toEqual({ error: 'Não autenticado' })
    expect(state.engineCalls).toEqual([])
    expect(state.serviceOps).toEqual([])
  })

  it('content_editor (não abre a tela): recusa as duas ações, não roda o motor e não apaga nada', async () => {
    signIn('content_editor')
    await expect(runPlayground({ from: WPP, text: 'oi' })).resolves.toEqual({
      error: 'Acesso negado',
    })
    await expect(resetPlaygroundUser(WPP)).resolves.toEqual({ error: 'Acesso negado' })
    expect(state.engineCalls).toEqual([])
    expect(state.serviceOps).toEqual([])
  })

  it('conta logada que não é administradora: recusa', async () => {
    signIn(null)
    await expect(runPlayground({ from: WPP, text: 'oi' })).resolves.toEqual({
      error: 'Acesso negado',
    })
    await expect(resetPlaygroundUser(WPP)).resolves.toEqual({ error: 'Acesso negado' })
    expect(state.engineCalls).toEqual([])
    expect(state.serviceOps).toEqual([])
  })

  it.each([
    'support',
    'operations_admin',
  ])('%s abre a tela, mas a ação já não o aceitava: continua recusado (nunca alarga)', async (role) => {
    signIn(role)
    await expect(runPlayground({ from: WPP, text: 'oi' })).resolves.toEqual({
      error: 'Acesso negado',
    })
    await expect(resetPlaygroundUser(WPP)).resolves.toEqual({ error: 'Acesso negado' })
    expect(state.engineCalls).toEqual([])
    expect(state.serviceOps).toEqual([])
  })

  it.each([
    'nutrition_admin',
    'master_admin',
  ])('%s (abre a tela e está na lista da ação): roda e apaga como antes', async (role) => {
    signIn(role)

    await expect(runPlayground({ from: WPP, text: 'oi' })).resolves.toEqual({
      text: 'resposta do motor',
      stage: 'manutencao',
      model: 'modelo-de-teste',
      prompt_tokens: 10,
      completion_tokens: 5,
      cost_usd: 0.001,
      latency_ms: 12,
      tools: [
        { name: 'consulta_progresso', success: true },
        { name: 'registra_refeicao', success: false },
      ],
    })
    expect(state.engineCalls).toEqual([{ from: WPP, text: 'oi', provider: 'admin_playground' }])
    expect(state.serviceOps).toEqual(['service_credentials.select'])

    state.serviceOps = []
    await expect(resetPlaygroundUser(WPP)).resolves.toEqual({ ok: true })
    expect(state.serviceOps).toEqual(['users.select', 'users.delete'])
  })
})
