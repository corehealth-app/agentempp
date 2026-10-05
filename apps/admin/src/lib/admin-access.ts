import type { AdminRole } from './admin-rbac'

/**
 * Quais telas do painel cada papel pode abrir.
 *
 * A matriz é a menor que fecha a exposição encontrada em 2026-10-05: o papel
 * `content_editor` (quem escreve os artigos da Biblioteca) abria Conversas,
 * Usuários e Auditoria, porque só um item do menu era filtrado e quase
 * nenhuma página conferia o papel no servidor.
 *
 * - `content_editor` → Publicações, Mensagens do coach e Regras (`/prompts` e
 *   `/prompts/[id]`: este papel já abria as duas e salva rascunho de regra
 *   pela ação `saveRule`, que aceita `CONTENT_ADMIN_ROLES`; ativar uma regra
 *   continua só de `master_admin`). O Playground (`/prompts/playground`) fica
 *   fechado para ele: roda o motor legado como uma conta e apaga conta.
 * - Todos os outros papéis → como antes (nenhuma tela a menos; as páginas que
 *   já conferiam papel por conta própria continuam conferindo).
 *
 * Este arquivo é puro (sem servidor, sem React): o menu lateral, a busca
 * rápida e os atalhos usam a mesma função que o guarda das páginas
 * (`guardAdminPage` em `admin-page-guard.ts`) e que o guarda das ações de
 * servidor e rotas que ficam atrás de uma tela (`checkAdminPageAccess`).
 */
export const CONTENT_EDITOR_PATHS = ['/content', '/prompts', '/settings/coach-messages'] as const

/** Dentro de uma área liberada, o que continua fechado para o `content_editor`. */
export const CONTENT_EDITOR_CLOSED_PATHS = ['/prompts/playground'] as const

/** Tira query, âncora e barra final: `/crescimento?tab=funil` → `/crescimento`. */
export function normalizeAdminPath(href: string): string {
  const path = href.split(/[?#]/, 1)[0] ?? ''
  if (path.length > 1 && path.endsWith('/')) return path.slice(0, -1)
  return path || '/'
}

function isUnder(path: string, base: string): boolean {
  return path === base || path.startsWith(`${base}/`)
}

export function canOpenAdminPath(role: AdminRole, href: string): boolean {
  if (role !== 'content_editor') return true
  const path = normalizeAdminPath(href)
  if (CONTENT_EDITOR_CLOSED_PATHS.some((base) => isUnder(path, base))) return false
  return CONTENT_EDITOR_PATHS.some((base) => isUnder(path, base))
}

/**
 * Um item de navegação aparece quando o papel pode abrir a tela E passa na
 * restrição própria do item (`roles`), que já existia para Publicações.
 */
export function canSeeAdminNavItem(
  role: AdminRole,
  item: { href: string; roles?: readonly AdminRole[] },
): boolean {
  if (item.roles && !item.roles.includes(role)) return false
  return canOpenAdminPath(role, item.href)
}

export interface AdminLandingLink {
  href: string
  label: string
  description: string
}

const LANDING_LINKS: readonly AdminLandingLink[] = [
  {
    href: '/content',
    label: 'Publicações',
    description: 'Artigos da Biblioteca do app: escrever, revisar e publicar.',
  },
  {
    href: '/prompts',
    label: 'Regras',
    description: 'Regras do Flow: ler e salvar rascunho de regra.',
  },
  {
    href: '/settings/coach-messages',
    label: 'Mensagens do coach',
    description: 'Catálogo das mensagens do coach que o app entrega.',
  },
]

/** Atalhos da tela inicial neutra, para o papel que não abre o dashboard. */
export function adminLandingLinks(role: AdminRole): AdminLandingLink[] {
  return LANDING_LINKS.filter((link) => canOpenAdminPath(role, link.href))
}
