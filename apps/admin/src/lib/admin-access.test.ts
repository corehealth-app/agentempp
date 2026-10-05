import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import {
  adminLandingLinks,
  canOpenAdminPath,
  canSeeAdminNavItem,
  normalizeAdminPath,
} from './admin-access'
import {
  ADMIN_ROLES,
  type AdminRole,
  CONTENT_ADMIN_ROLES,
  CONTENT_MODULE_ROLES,
} from './admin-rbac'

// Toda tela do painel (uma por pasta com page.tsx em app/(admin)).
const PANEL_PATHS = [
  '/dashboard',
  '/messages',
  '/users',
  '/users/00000000-0000-0000-0000-000000000001',
  '/content',
  '/content/new',
  '/content/00000000-0000-0000-0000-000000000002',
  '/crescimento',
  '/crescimento?tab=funil',
  '/prompts',
  '/prompts/00000000-0000-0000-0000-000000000003',
  '/prompts/playground',
  '/settings/agents',
  '/settings/tools',
  '/evaluations',
  '/audit',
  '/settings/global',
  '/settings/calc',
  '/formulas',
  '/settings/foods',
  '/settings/coach-messages',
  '/settings/api-keys',
  '/settings/stripe',
  '/settings/crons',
  '/settings/admins',
  '/tutorial',
] as const

const CONTENT_EDITOR_ALLOWED = [
  '/content',
  '/content/new',
  '/content/00000000-0000-0000-0000-000000000002',
  '/prompts',
  '/prompts/00000000-0000-0000-0000-000000000003',
  '/settings/coach-messages',
]

describe('matriz de acesso do painel', () => {
  it('content_editor abre só Publicações, Regras e Mensagens do coach', () => {
    const opened = PANEL_PATHS.filter((path) => canOpenAdminPath('content_editor', path))
    expect(opened).toEqual(CONTENT_EDITOR_ALLOWED)
  })

  it('content_editor abre Regras e a edição de uma regra (como em HEAD), mas não o Playground', () => {
    // Este papel salva rascunho de regra: a ação saveRule aceita CONTENT_ADMIN_ROLES.
    expect(CONTENT_ADMIN_ROLES).toContain('content_editor')
    for (const path of [
      '/prompts',
      '/prompts/',
      '/prompts?tipo=regras_gerais',
      '/prompts/00000000-0000-0000-0000-000000000003',
      '/prompts/00000000-0000-0000-0000-000000000003?v=2',
    ]) {
      expect(canOpenAdminPath('content_editor', path), path).toBe(true)
    }
    for (const path of [
      '/prompts/playground',
      '/prompts/playground/',
      '/prompts/playground?from=5511999999999',
      '/prompts/playground#x',
      '/prompts/playground/qualquer-coisa',
    ]) {
      expect(canOpenAdminPath('content_editor', path), path).toBe(false)
    }
    // Um nome parecido com a área liberada continua fechado.
    expect(canOpenAdminPath('content_editor', '/prompts-antigos')).toBe(false)
    expect(canOpenAdminPath('content_editor', '/promptsx')).toBe(false)
  })

  it('content_editor não abre Conversas, Usuários nem Auditoria (a exposição de 2026-10-05)', () => {
    for (const path of ['/messages', '/messages?user=abc', '/users', '/users/abc', '/audit']) {
      expect(canOpenAdminPath('content_editor', path), path).toBe(false)
    }
  })

  it('os outros papéis continuam abrindo tudo, como antes', () => {
    const others = ADMIN_ROLES.filter((role) => role !== 'content_editor')
    expect(others).toEqual(['support', 'nutrition_admin', 'operations_admin', 'master_admin'])
    for (const role of others) {
      for (const path of PANEL_PATHS) {
        expect(canOpenAdminPath(role, path), `${role} ${path}`).toBe(true)
      }
    }
  })

  it('não libera por prefixo parecido nem por query', () => {
    expect(canOpenAdminPath('content_editor', '/contents')).toBe(false)
    expect(canOpenAdminPath('content_editor', '/content-admin')).toBe(false)
    expect(canOpenAdminPath('content_editor', '/settings/coach-messages-old')).toBe(false)
    expect(canOpenAdminPath('content_editor', '/settings')).toBe(false)
    expect(canOpenAdminPath('content_editor', '/messages?next=/content')).toBe(false)
    expect(canOpenAdminPath('content_editor', '/messages?next=/prompts')).toBe(false)
    expect(canOpenAdminPath('content_editor', '/content?status=draft')).toBe(true)
    expect(canOpenAdminPath('content_editor', '/content/')).toBe(true)
  })

  it('normaliza query, âncora e barra final', () => {
    expect(normalizeAdminPath('/crescimento?tab=funil')).toBe('/crescimento')
    expect(normalizeAdminPath('/audit#x')).toBe('/audit')
    expect(normalizeAdminPath('/content/')).toBe('/content')
    expect(normalizeAdminPath('/')).toBe('/')
    expect(normalizeAdminPath('')).toBe('/')
  })
})

describe('itens de navegação por papel', () => {
  const publications = { href: '/content', roles: CONTENT_MODULE_ROLES }
  const conversations = { href: '/messages' }
  const coachMessages = { href: '/settings/coach-messages' }
  const rules = { href: '/prompts' }
  const playground = { href: '/prompts/playground' }

  it('content_editor vê Publicações, Regras e Mensagens do coach, e não vê Conversas nem Playground', () => {
    expect(canSeeAdminNavItem('content_editor', publications)).toBe(true)
    expect(canSeeAdminNavItem('content_editor', coachMessages)).toBe(true)
    expect(canSeeAdminNavItem('content_editor', rules)).toBe(true)
    expect(canSeeAdminNavItem('content_editor', conversations)).toBe(false)
    expect(canSeeAdminNavItem('content_editor', playground)).toBe(false)
  })

  it('mantém a restrição própria do item para os outros papéis', () => {
    const seesPublications = (role: AdminRole) => canSeeAdminNavItem(role, publications)
    expect(ADMIN_ROLES.map(seesPublications)).toEqual([false, true, true, false, true])
    for (const role of ADMIN_ROLES.filter((r) => r !== 'content_editor')) {
      expect(canSeeAdminNavItem(role, conversations)).toBe(true)
    }
  })
})

describe('tela inicial neutra', () => {
  it('leva o content_editor só às três áreas dele', () => {
    expect(adminLandingLinks('content_editor').map((link) => link.href)).toEqual([
      '/content',
      '/prompts',
      '/settings/coach-messages',
    ])
  })
})

// O menu lateral, a busca rápida e os atalhos têm cada um a sua lista de
// telas; o que cada papel vê sai da MESMA matriz. Aqui o teste lê as três
// listas do código e aplica a matriz, como o componente faz.
describe('menu lateral, busca rápida e atalhos seguem a mesma matriz', () => {
  const source = (file: string) =>
    readFileSync(fileURLToPath(new URL(`../components/${file}`, import.meta.url)), 'utf8')

  /** As entradas `{ …, href|path: '/x', … }` de uma lista, com a restrição `roles` quando há. */
  function entries(code: string, key: 'href' | 'path') {
    const pattern = new RegExp(`\\{[^{}]*?\\b${key}: '([^']+)'[^{}]*?\\}`, 'g')
    return Array.from(code.matchAll(pattern), (match) => ({
      href: match[1] ?? '',
      ...(match[0].includes('roles: CONTENT_MODULE_ROLES') ? { roles: CONTENT_MODULE_ROLES } : {}),
    }))
  }
  const visible = (role: AdminRole, items: Array<{ href: string; roles?: readonly AdminRole[] }>) =>
    items.filter((item) => canSeeAdminNavItem(role, item)).map((item) => item.href)

  const sidebar = source('sidebar.tsx')
  const palette = source('command-palette.tsx')
  const shortcuts = source('keyboard-shortcuts.tsx')

  it('os três filtram pela matriz', () => {
    expect(sidebar).toContain('category.items.filter((item) => canSeeAdminNavItem(role, item))')
    expect(palette).toContain('NAV_ITEMS.filter((item) => canSeeAdminNavItem(role, item))')
    expect(shortcuts).toContain(
      'SHORTCUTS.filter((shortcut) => canOpenAdminPath(role, shortcut.path))',
    )
  })

  it('content_editor: menu e busca mostram Publicações, Regras e Mensagens do coach; o atalho é o de Regras', () => {
    const areas = ['/content', '/prompts', '/settings/coach-messages']
    expect(visible('content_editor', entries(sidebar, 'href'))).toEqual(areas)
    expect(visible('content_editor', entries(palette, 'href'))).toEqual(areas)
    expect(visible('content_editor', entries(shortcuts, 'path'))).toEqual(['/prompts'])
  })

  it('os outros papéis continuam com a lista inteira (menos Publicações, para quem já não a via)', () => {
    for (const role of ['support', 'operations_admin'] as const) {
      const all = entries(sidebar, 'href').map((item) => item.href)
      expect(all.length).toBeGreaterThanOrEqual(19)
      expect(visible(role, entries(sidebar, 'href'))).toEqual(
        all.filter((href) => href !== '/content'),
      )
      expect(visible(role, entries(shortcuts, 'path'))).toHaveLength(9)
    }
    for (const role of ['nutrition_admin', 'master_admin'] as const) {
      expect(visible(role, entries(sidebar, 'href'))).toEqual(
        entries(sidebar, 'href').map((item) => item.href),
      )
      expect(visible(role, entries(palette, 'href'))).toEqual(
        entries(palette, 'href').map((item) => item.href),
      )
    }
  })

  it('nenhuma das três listas leva ao Playground', () => {
    for (const code of [sidebar, palette, shortcuts]) {
      expect(code).not.toMatch(/(?:href|path): '\/prompts\/playground/)
    }
  })
})
