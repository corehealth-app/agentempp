import { redirect } from 'next/navigation'
import { cache } from 'react'
import { canOpenAdminPath } from '@/lib/admin-access'
import { type AdminRole, isAdminRole } from '@/lib/admin-rbac'
import { createClient } from '@/lib/supabase/server'

/**
 * O guarda de servidor do painel. TODA página em `app/(admin)` chama
 * `guardAdminPage(<rota>)` antes de ler qualquer dado, e devolve o estado
 * "Não autorizado" quando ele recusa:
 *
 *   const access = await guardAdminPage('/messages')
 *   if (!access.ok) return <AdminAccessDenied access={access} />
 *
 * Por que na página e não só no layout: o layout não é executado de novo na
 * navegação entre telas (o Next só busca o segmento da página) e não conhece
 * a rota. Conferir só no layout deixava a página — que lê com a chave de
 * serviço — respondendo a quem o layout barraria.
 *
 * O teste `admin-page-guard.test.ts` trava que nenhuma página do painel fica
 * sem o guarda.
 *
 * O que fica ATRÁS de uma tela — ação de servidor e rota que só aquela tela
 * chama — usa `checkAdminPageAccess(<rota da tela>)`: a mesma leitura e a
 * mesma matriz, sem redirecionar.
 */

export interface AdminIdentity {
  id: string
  email: string
  name: string | null
  role: AdminRole
}

export type AdminSession =
  | { kind: 'anonymous' }
  | { kind: 'not_admin'; userEmail: string | null }
  | { kind: 'admin'; admin: AdminIdentity; userEmail: string | null }

export type AdminPageAccess =
  | { ok: true; admin: AdminIdentity }
  /** Sessão válida, mas a conta não é um administrador do painel. */
  | { ok: false; reason: 'not_admin'; userEmail: string | null }
  /** Administrador cujo papel não inclui esta tela. */
  | { ok: false; reason: 'role'; admin: AdminIdentity }

/**
 * Quem está logado e qual o papel. `cache` do React: o layout e a página do
 * mesmo pedido compartilham uma única leitura de `admin_users`.
 */
export const loadAdminSession = cache(async (): Promise<AdminSession> => {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { kind: 'anonymous' }

  const { data: adminRow } = await supabase
    .from('admin_users')
    .select('id, email, name, role')
    .eq('id', user.id)
    .maybeSingle()

  const row = adminRow as {
    id: string
    email: string
    name: string | null
    role: string
  } | null
  const userEmail = user.email ?? null

  if (!row || !isAdminRole(row.role)) return { kind: 'not_admin', userEmail }
  return {
    kind: 'admin',
    admin: { id: row.id, email: row.email, name: row.name, role: row.role },
    userEmail,
  }
})

export async function guardAdminPage(path: string): Promise<AdminPageAccess> {
  const session = await loadAdminSession()
  if (session.kind === 'anonymous') redirect('/login')
  if (session.kind === 'not_admin') {
    return { ok: false, reason: 'not_admin', userEmail: session.userEmail }
  }
  if (!canOpenAdminPath(session.admin.role, path)) {
    return { ok: false, reason: 'role', admin: session.admin }
  }
  return { ok: true, admin: session.admin }
}

export type AdminActionAccess =
  | { ok: true; admin: AdminIdentity }
  /** `anonymous`: sem sessão. `not_admin`: não é administrador. `role`: o papel não inclui a tela. */
  | { ok: false; reason: 'anonymous' | 'not_admin' | 'role' }

/**
 * Para ações de servidor e rotas que ficam atrás de uma tela. Regra única:
 * **só passa quem pode abrir a tela a que a ação pertence** — a mesma sessão
 * (`loadAdminSession`) e a mesma matriz (`canOpenAdminPath`) do guarda da
 * página.
 *
 * Não redireciona nem lança: quem chama devolve a recusa no formato de
 * resposta e de erro que já tinha.
 *
 * `alsoRequire` nunca alarga. Quando a ação já tinha uma lista de papéis mais
 * estreita que a tela, ela continua valendo: passa quem pode abrir a tela E
 * está na lista (a interseção).
 */
export async function checkAdminPageAccess(
  path: string,
  alsoRequire?: readonly AdminRole[],
): Promise<AdminActionAccess> {
  const session = await loadAdminSession()
  if (session.kind === 'anonymous') return { ok: false, reason: 'anonymous' }
  if (session.kind === 'not_admin') return { ok: false, reason: 'not_admin' }
  const { role } = session.admin
  if (!canOpenAdminPath(role, path)) return { ok: false, reason: 'role' }
  if (alsoRequire && !alsoRequire.includes(role)) return { ok: false, reason: 'role' }
  return { ok: true, admin: session.admin }
}
