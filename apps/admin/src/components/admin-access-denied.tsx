import Link from 'next/link'
import { adminLandingLinks } from '@/lib/admin-access'
import type { AdminIdentity, AdminPageAccess } from '@/lib/admin-page-guard'

type DeniedAccess = Extract<AdminPageAccess, { ok: false }>

/**
 * O estado "Não autorizado" do painel. Dois casos, o mesmo cartão:
 *
 * - `not_admin`: a conta logada não é administradora (texto que já existia no
 *   layout);
 * - `role`: é administradora, mas o papel não inclui a tela pedida.
 *
 * Nenhum dos dois mostra dado: a página devolve este componente ANTES de ler.
 */
export function AdminAccessDenied({
  access,
  fullScreen = false,
}: {
  access: DeniedAccess
  fullScreen?: boolean
}) {
  return (
    <div
      className={
        fullScreen
          ? 'min-h-screen flex items-center justify-center p-6'
          : 'flex items-center justify-center py-12'
      }
    >
      <div className="glass-card p-8 max-w-md w-full space-y-6">
        <div className="section-eyebrow">Acesso restrito</div>
        <h1 className="font-display text-3xl text-foreground tracking-tight">Não autorizado</h1>
        {access.reason === 'not_admin' ? (
          <>
            <p className="text-muted-foreground text-pretty">
              O e-mail <strong className="font-medium text-foreground">{access.userEmail}</strong>{' '}
              não está cadastrado como administrador do painel. Peça a um administrador atual para
              te incluir.
            </p>
            <SignOutForm />
          </>
        ) : (
          <>
            <p className="text-muted-foreground text-pretty">
              O seu perfil de acesso não inclui esta área do painel. Se você precisa dela, peça a um
              administrador para ajustar o seu papel.
            </p>
            <AllowedLinks admin={access.admin} />
          </>
        )}
      </div>
    </div>
  )
}

function AllowedLinks({ admin }: { admin: AdminIdentity }) {
  const links = adminLandingLinks(admin.role)
  if (links.length === 0) return null
  return (
    <ul className="space-y-1 pt-2 border-t border-border">
      {links.map((link) => (
        <li key={link.href}>
          <Link
            href={link.href}
            className="text-sm text-primary underline underline-offset-4 focus-ring rounded px-1 -mx-1"
          >
            Ir para {link.label}
          </Link>
        </li>
      ))}
    </ul>
  )
}

function SignOutForm() {
  return (
    <form action="/auth/signout" method="post" className="pt-4">
      <button
        type="submit"
        className="text-sm text-muted-foreground hover:text-foreground underline underline-offset-4 focus-ring rounded px-1 -mx-1"
      >
        Sair desta conta
      </button>
    </form>
  )
}

/**
 * Tela inicial neutra: o que aparece em /dashboard para o papel que não abre
 * o dashboard (hoje, `content_editor`). Sem números, sem dado de usuário.
 */
export function AdminLanding({ admin }: { admin: AdminIdentity }) {
  const links = adminLandingLinks(admin.role)
  return (
    <div className="space-y-4">
      <div className="glass-card p-6">
        <div className="section-eyebrow">Performe AI · Painel</div>
        <h1 className="font-display text-2xl md:text-3xl text-foreground tracking-tight mt-2">
          Olá{admin.name ? `, ${admin.name}` : ''}
        </h1>
        <p className="mt-1.5 text-sm text-muted-foreground text-pretty max-w-2xl">
          Estas são as áreas do painel disponíveis para o seu perfil.
        </p>
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        {links.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className="glass-card p-5 block hover:border-primary/40 transition-colors focus-ring"
          >
            <div className="font-display text-lg text-foreground tracking-tight">{link.label}</div>
            <p className="mt-1 text-sm text-muted-foreground">{link.description}</p>
          </Link>
        ))}
      </div>
    </div>
  )
}
