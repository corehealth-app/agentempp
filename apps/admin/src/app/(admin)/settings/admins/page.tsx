import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { Shield, ShieldCheck, Eye } from 'lucide-react'
import { AdminInviteForm } from './form'

const ROLE_BADGE: Record<string, { label: string; class: string; icon: React.ComponentType<{ className?: string }> }> = {
  admin: { label: 'admin', class: 'bg-moss-100 text-moss-700', icon: ShieldCheck },
  editor: { label: 'editor', class: 'bg-cream-300 text-foreground/80', icon: Shield },
  viewer: { label: 'viewer', class: 'bg-muted text-muted-foreground', icon: Eye },
}

export default async function AdminsPage() {
  const svc = createServiceClient()
  const { data: admins } = await svc
    .from('admin_users')
    .select('*')
    .order('created_at', { ascending: false })

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Admins' }]}
        title="Usuários do admin"
        description="Quem pode acessar este painel. Apenas role admin pode adicionar outros usuários."
      />

      <ContentCard
        title="Adicionar admin"
        description="O usuário precisa ter feito login pelo menos uma vez via /login para que o ID seja conhecido. O email aqui deve ser o mesmo do magic link."
      >
        <AdminInviteForm />
      </ContentCard>

      <ContentCard title="Lista atual" description={`${admins?.length ?? 0} usuários cadastrados`}>
        {!admins || admins.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum admin cadastrado ainda.</p>
        ) : (
          <ul className="divide-y divide-border -mx-5 -my-5">
            {admins.map((a) => {
              const role = ROLE_BADGE[a.role] ?? ROLE_BADGE.viewer
              if (!role) return null
              const Icon = role.icon
              return (
                <li
                  key={a.id}
                  className="flex items-center justify-between gap-3 px-5 py-3.5 hover:bg-muted/30 transition-colors"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="h-9 w-9 shrink-0 rounded-full bg-moss-700 text-cream-100 flex items-center justify-center text-xs font-medium font-display">
                      {(a.name ?? a.email ?? 'A').slice(0, 2).toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <div className="font-medium text-foreground truncate">
                        {a.name ?? a.email}
                      </div>
                      <div className="text-xs text-muted-foreground truncate font-mono">
                        {a.email}
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 shrink-0">
                    <span
                      className={`inline-flex items-center gap-1.5 text-[10px] uppercase tracking-widest font-mono px-2 py-1 rounded-full ${role.class}`}
                    >
                      <Icon className="h-3 w-3" />
                      {role.label}
                    </span>
                    <span className="text-xs text-muted-foreground hidden sm:inline">
                      {formatDateTime(a.created_at)}
                    </span>
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </ContentCard>
    </div>
  )
}
