import type { NextRequest } from 'next/server'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// GET /api/media/[id] fica atrás da tela Conversas (a prévia de mídia de uma
// mensagem): só passa quem pode abrir a tela. Até 2026-10-05 bastava ter uma
// linha em admin_users, com qualquer papel — o content_editor, que não abre
// Conversas, baixava a mídia.

const state = vi.hoisted(() => ({
  user: null as { id: string; email: string } | null,
  adminRow: null as { id: string; email: string; name: string | null; role: string } | null,
  /** Tabelas lidas com a chave de serviço. */
  serviceTables: [] as string[],
  fetched: [] as string[],
}))

vi.mock('next/navigation', () => ({
  redirect: (url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
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
  createServiceClient: () => ({
    from: (table: string) => {
      state.serviceTables.push(table)
      const chain = {
        select: () => chain,
        eq: () => chain,
        in: async () => ({
          data: [{ key_name: 'access_token', value: 'token-de-teste' }],
          error: null,
        }),
      }
      return chain
    },
  }),
}))

import { GET } from './route'

const MEDIA_ID = 'midia-123'
const open = () =>
  GET({} as NextRequest, { params: Promise.resolve({ id: MEDIA_ID }) }) as Promise<Response>

function signIn(role: string | null) {
  state.user = { id: 'admin-1', email: 'pessoa@exemplo.com' }
  state.adminRow = role
    ? { id: 'admin-1', email: 'pessoa@exemplo.com', name: 'Pessoa', role }
    : null
}

beforeEach(() => {
  state.user = null
  state.adminRow = null
  state.serviceTables = []
  state.fetched = []
  // Nenhuma chamada de rede de verdade: o provedor de mídia é falso.
  vi.stubGlobal('fetch', async (url: string) => {
    state.fetched.push(url)
    if (url.includes('graph.facebook.com')) {
      return new Response(
        JSON.stringify({ url: 'https://midia.invalid/arquivo', mime_type: 'image/jpeg' }),
        { status: 200 },
      )
    }
    return new Response(new Uint8Array([1, 2, 3]), { status: 200 })
  })
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('GET /api/media/[id] — quem pode baixar a mídia de uma conversa', () => {
  it('sem sessão: 401, sem ler a credencial e sem chamar o provedor', async () => {
    const response = await open()
    expect(response.status).toBe(401)
    expect(await response.text()).toBe('unauthenticated')
    expect(state.serviceTables).toEqual([])
    expect(state.fetched).toEqual([])
  })

  it('content_editor (não abre Conversas): 403, sem ler a credencial e sem chamar o provedor', async () => {
    signIn('content_editor')
    const response = await open()
    expect(response.status).toBe(403)
    expect(await response.text()).toBe('forbidden')
    expect(state.serviceTables).toEqual([])
    expect(state.fetched).toEqual([])
  })

  it('conta logada que não é administradora, ou com papel desconhecido: 403', async () => {
    signIn(null)
    expect((await open()).status).toBe(403)
    signIn('viewer')
    expect((await open()).status).toBe(403)
    expect(state.serviceTables).toEqual([])
    expect(state.fetched).toEqual([])
  })

  it.each([
    'support',
    'nutrition_admin',
    'operations_admin',
    'master_admin',
  ])('%s (abre Conversas): recebe a mídia como antes', async (role) => {
    signIn(role)
    const response = await open()

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toBe('image/jpeg')
    expect(response.headers.get('Cache-Control')).toBe('private, max-age=3600')
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([1, 2, 3]))
    expect(state.serviceTables).toEqual(['service_credentials'])
    expect(state.fetched).toEqual([
      `https://graph.facebook.com/v21.0/${MEDIA_ID}`,
      'https://midia.invalid/arquivo',
    ])
  })
})
