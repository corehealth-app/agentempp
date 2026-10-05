import { readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const state = vi.hoisted(() => ({
  user: null as { id: string; email: string } | null,
  adminRow: null as { id: string; email: string; name: string | null; role: string } | null,
  sessionTables: [] as string[],
  serviceTables: [] as string[],
}))

vi.mock('next/navigation', () => ({
  redirect: (url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  },
  notFound: () => {
    throw new Error('NEXT_NOT_FOUND')
  },
}))
vi.mock('next/link', () => ({ default: 'a' }))

// Cliente de serviço falso: qualquer cadeia resolve vazio. O que interessa é
// SE ele foi usado (a página só pode ler depois que o guarda liberou).
function emptyChain(): unknown {
  const result = { data: [], error: null, count: 0 }
  const chain: unknown = new Proxy(() => {}, {
    get(_target, property) {
      if (property === 'then') {
        return (resolvePromise: (value: unknown) => void) => resolvePromise(result)
      }
      if (property === 'maybeSingle' || property === 'single') {
        return async () => ({ data: null, error: null })
      }
      return () => chain
    },
    apply: () => chain,
  })
  return chain
}

vi.mock('@/lib/supabase/server', () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: state.user } }) },
    from: (table: string) => {
      state.sessionTables.push(table)
      return {
        select: () => ({
          eq: () => ({ maybeSingle: async () => ({ data: state.adminRow, error: null }) }),
        }),
      }
    },
  }),
  createServiceClient: () => ({
    from: (table: string) => {
      state.serviceTables.push(table)
      return emptyChain()
    },
    rpc: () => emptyChain(),
  }),
}))

// A tela de Conversas é a página guardada do teste: os filhos (thread, lateral
// e extras em tempo real) não importam aqui.
vi.mock('@/app/(admin)/messages/conversation-thread', () => ({ ConversationThread: 'section' }))
vi.mock('@/app/(admin)/messages/conversation-sidebar', () => ({ ConversationSidebar: 'aside' }))
vi.mock('@/app/(admin)/messages/lazy-extras', () => ({
  LazyRealtimeListener: 'span',
  LazySearchTrigger: 'span',
}))
// O formulário do Playground puxa as ações (e o motor): não interessa aqui.
vi.mock('@/app/(admin)/prompts/playground/form', () => ({ PlaygroundForm: 'form' }))

import ConversasPage from '@/app/(admin)/messages/page'
import RegrasPage from '@/app/(admin)/prompts/page'
import PlaygroundPage from '@/app/(admin)/prompts/playground/page'
import { AdminAccessDenied } from '@/components/admin-access-denied'
import { canOpenAdminPath } from './admin-access'
import { checkAdminPageAccess, guardAdminPage } from './admin-page-guard'
import { ADMIN_ROLES, AI_PLAYGROUND_ROLES } from './admin-rbac'

function signIn(role: string | null) {
  state.user = { id: 'admin-1', email: 'pessoa@exemplo.com' }
  state.adminRow = role
    ? { id: 'admin-1', email: 'pessoa@exemplo.com', name: 'Pessoa', role }
    : null
}

beforeEach(() => {
  state.user = null
  state.adminRow = null
  state.sessionTables = []
  state.serviceTables = []
})

describe('guardAdminPage', () => {
  it('manda para o login quem não tem sessão', async () => {
    await expect(guardAdminPage('/messages')).rejects.toThrow('NEXT_REDIRECT:/login')
  })

  it('recusa a conta logada que não é administradora (ex.: uma conta do app)', async () => {
    signIn(null)
    await expect(guardAdminPage('/messages')).resolves.toEqual({
      ok: false,
      reason: 'not_admin',
      userEmail: 'pessoa@exemplo.com',
    })
  })

  it('recusa um papel que não existe na lista de papéis', async () => {
    signIn('viewer')
    await expect(guardAdminPage('/content')).resolves.toMatchObject({
      ok: false,
      reason: 'not_admin',
    })
  })

  it('recusa o content_editor fora de Publicações, Regras e Mensagens do coach', async () => {
    signIn('content_editor')
    for (const path of [
      '/messages',
      '/users',
      '/audit',
      '/dashboard',
      '/settings/api-keys',
      '/settings/foods',
      '/prompts/playground',
    ]) {
      await expect(guardAdminPage(path), path).resolves.toMatchObject({
        ok: false,
        reason: 'role',
      })
    }
    await expect(guardAdminPage('/content')).resolves.toMatchObject({ ok: true })
    await expect(guardAdminPage('/settings/coach-messages')).resolves.toMatchObject({ ok: true })
    await expect(guardAdminPage('/prompts')).resolves.toMatchObject({ ok: true })
  })

  it('libera os outros papéis como antes', async () => {
    for (const role of ['support', 'nutrition_admin', 'operations_admin', 'master_admin']) {
      signIn(role)
      await expect(guardAdminPage('/messages'), role).resolves.toMatchObject({
        ok: true,
        admin: { role },
      })
    }
  })

  it('lê só admin_users, e com o cliente da sessão', async () => {
    signIn('master_admin')
    await guardAdminPage('/messages')
    expect(state.sessionTables).toEqual(['admin_users'])
    expect(state.serviceTables).toEqual([])
  })
})

// O que fica atrás de uma tela (ação de servidor, rota) faz a mesma pergunta,
// sem redirecionar: quem chama mantém o próprio formato de erro.
describe('checkAdminPageAccess', () => {
  it('sem sessão: recusa com "anonymous" e NÃO redireciona', async () => {
    await expect(checkAdminPageAccess('/settings/foods')).resolves.toEqual({
      ok: false,
      reason: 'anonymous',
    })
  })

  it('conta logada que não é administradora, ou com papel desconhecido: "not_admin"', async () => {
    signIn(null)
    await expect(checkAdminPageAccess('/settings/foods')).resolves.toEqual({
      ok: false,
      reason: 'not_admin',
    })
    signIn('viewer')
    await expect(checkAdminPageAccess('/settings/foods')).resolves.toEqual({
      ok: false,
      reason: 'not_admin',
    })
  })

  it('dá, para todo papel e toda tela, a mesma resposta do guarda da página', async () => {
    for (const role of ADMIN_ROLES) {
      signIn(role)
      for (const path of ['/messages', '/settings/foods', '/prompts', '/prompts/playground']) {
        const page = await guardAdminPage(path)
        const action = await checkAdminPageAccess(path)
        expect(action.ok, `${role} ${path}`).toBe(page.ok)
        expect(action.ok, `${role} ${path}`).toBe(canOpenAdminPath(role, path))
      }
    }
  })

  it('a lista própria da ação nunca alarga: vale a interseção com a tela', async () => {
    const allowed: string[] = []
    for (const role of ADMIN_ROLES) {
      signIn(role)
      const access = await checkAdminPageAccess('/prompts/playground', AI_PLAYGROUND_ROLES)
      if (access.ok) allowed.push(role)
    }
    // content_editor está na lista da ação, mas não abre a tela; support e
    // operations_admin abrem a tela, mas não estão na lista da ação.
    expect(allowed).toEqual(['nutrition_admin', 'master_admin'])
  })

  it('lê só admin_users, e com o cliente da sessão', async () => {
    signIn('master_admin')
    await checkAdminPageAccess('/settings/foods')
    expect(state.sessionTables).toEqual(['admin_users'])
    expect(state.serviceTables).toEqual([])
  })
})

describe('página guardada: Conversas', () => {
  const open = () => ConversasPage({ searchParams: Promise.resolve({}) })

  it('content_editor recebe "Não autorizado" e NENHUMA leitura é feita', async () => {
    signIn('content_editor')
    const element = (await open()) as { type: unknown; props: { access: unknown } }
    expect(element.type).toBe(AdminAccessDenied)
    expect(element.props.access).toMatchObject({ ok: false, reason: 'role' })
    expect(state.serviceTables).toEqual([])
  })

  it('conta logada que não é administradora também não lê nada', async () => {
    signIn(null)
    const element = (await open()) as { type: unknown }
    expect(element.type).toBe(AdminAccessDenied)
    expect(state.serviceTables).toEqual([])
  })

  it('sem sessão, vai para o login antes de ler', async () => {
    await expect(open()).rejects.toThrow('NEXT_REDIRECT:/login')
    expect(state.serviceTables).toEqual([])
  })

  it('support continua abrindo as conversas', async () => {
    signIn('support')
    const element = (await open()) as { type: unknown }
    expect(element.type).not.toBe(AdminAccessDenied)
    expect(state.serviceTables).toContain('messages')
  })
})

describe('páginas guardadas: Regras e Playground', () => {
  const openRules = () => RegrasPage({ searchParams: Promise.resolve({}) })

  it('content_editor abre Regras (como em HEAD) e a página lê as regras', async () => {
    signIn('content_editor')
    const element = (await openRules()) as { type: unknown }
    expect(element.type).not.toBe(AdminAccessDenied)
    expect(state.serviceTables).toContain('agent_rules')
  })

  it('content_editor recebe "Não autorizado" no Playground', async () => {
    signIn('content_editor')
    const element = (await PlaygroundPage()) as { type: unknown; props: { access: unknown } }
    expect(element.type).toBe(AdminAccessDenied)
    expect(element.props.access).toMatchObject({ ok: false, reason: 'role' })
    expect(state.serviceTables).toEqual([])
  })

  it('nutrition_admin continua abrindo o Playground', async () => {
    signIn('nutrition_admin')
    const element = (await PlaygroundPage()) as { type: unknown }
    expect(element.type).not.toBe(AdminAccessDenied)
  })
})

describe('toda página de app/(admin) passa pelo guarda antes de qualquer coisa', () => {
  const adminRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../app/(admin)')

  function pages(root: string): string[] {
    return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
      const path = resolve(root, entry.name)
      if (entry.isDirectory()) return pages(path)
      return entry.name === 'page.tsx' ? [path] : []
    })
  }

  // A primeira instrução da função da página é o guarda (comentários à parte),
  // seguida da saída quando ele recusa.
  const guardFirst =
    /export default async function \w+\([\s\S]*?\) \{\n(?:\s*\/\/[^\n]*\n)*\s*const access = await guardAdminPage\('([^']+)'\)\n\s*if \(!access\.ok\) (?:return <AdminAccessDenied access=\{access\} \/>|\{)/

  const files = pages(adminRoot)

  it('encontra as páginas do painel', () => {
    expect(files.length).toBeGreaterThanOrEqual(25)
  })

  it.each(
    files.map((file) => [relative(adminRoot, file).split(sep).join('/'), file] as const),
  )('%s', (name, file) => {
    const match = readFileSync(file, 'utf8').match(guardFirst)
    expect(match, `${name} não começa pelo guarda`).not.toBeNull()

    // A rota declarada ao guarda é a da própria pasta (ou um pai dela): uma
    // rota copiada de outra tela aplicaria a matriz errada.
    const route = `/${name.replace(/\/?page\.tsx$/, '')}`
    const declared = match?.[1] ?? ''
    expect(route === declared || route.startsWith(`${declared}/`), `${name} → ${declared}`).toBe(
      true,
    )

    // E a rota declarada dá, para todo papel, a MESMA resposta que a rota da
    // própria tela. Declarar o pai só vale quando a matriz não distingue os
    // dois: o Playground, fechado para o content_editor dentro de /prompts
    // (que ele abre), tem de declarar a própria rota.
    const ownRoute = route.replace(/\[[^\]]+\]/g, '00000000-0000-0000-0000-000000000001')
    for (const role of ADMIN_ROLES) {
      expect(canOpenAdminPath(role, declared), `${name} → ${declared} (${role})`).toBe(
        canOpenAdminPath(role, ownRoute),
      )
    }
  })

  it('o Playground declara a própria rota, não a de Regras', () => {
    const playground = files.find((file) => file.endsWith(`prompts${sep}playground${sep}page.tsx`))
    expect(playground).toBeDefined()
    expect(readFileSync(playground ?? '', 'utf8')).toContain(
      "guardAdminPage('/prompts/playground')",
    )
  })
})
