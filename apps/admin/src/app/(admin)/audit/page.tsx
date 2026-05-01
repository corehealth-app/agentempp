import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'

const ACTION_COLORS: Record<string, string> = {
  create: 'bg-moss-100 text-moss-700',
  update: 'bg-cream-300 text-foreground/80',
  delete: 'bg-destructive/15 text-destructive',
  publish: 'bg-bronze/15 text-bronze',
}

function actionVariant(action: string): string {
  if (action.includes('create') || action.includes('insert')) return ACTION_COLORS.create!
  if (action.includes('delete') || action.includes('archive')) return ACTION_COLORS.delete!
  if (action.includes('publish')) return ACTION_COLORS.publish!
  return ACTION_COLORS.update!
}

export default async function AuditPage() {
  const svc = createServiceClient()
  const { data: logs } = await svc
    .from('audit_log')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(200)

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Operação' }, { label: 'Auditoria' }]}
        title="Auditoria"
        description="Últimas 200 ações sensíveis registradas. Mudanças em credentials, regras, configs e admins ficam aqui."
      />

      <ContentCard>
        {!logs || logs.length === 0 ? (
          <p className="text-sm text-muted-foreground py-4">Sem registros ainda.</p>
        ) : (
          <div className="overflow-x-auto -mx-5 -my-5">
            <table className="w-full text-sm">
              <thead className="text-[10px] uppercase tracking-widest text-muted-foreground bg-muted/40 border-b border-border">
                <tr>
                  <th className="text-left px-5 py-2.5 font-mono">Quando</th>
                  <th className="text-left px-3 py-2.5 font-mono">Quem</th>
                  <th className="text-left px-3 py-2.5 font-mono">Ação</th>
                  <th className="text-left px-3 py-2.5 font-mono">Entidade</th>
                  <th className="text-left px-5 py-2.5 font-mono">ID</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {logs.map((l) => (
                  <tr key={l.id} className="hover:bg-muted/30 transition-colors">
                    <td className="px-5 py-2.5 text-xs font-mono text-muted-foreground whitespace-nowrap">
                      {formatDateTime(l.created_at)}
                    </td>
                    <td className="px-3 py-2.5 text-xs">
                      {l.actor_email ?? <span className="text-muted-foreground">—</span>}
                    </td>
                    <td className="px-3 py-2.5">
                      <span
                        className={`inline-flex text-[10px] uppercase tracking-widest font-mono px-2 py-0.5 rounded-full ${actionVariant(
                          l.action,
                        )}`}
                      >
                        {l.action}
                      </span>
                    </td>
                    <td className="px-3 py-2.5 text-xs font-mono">{l.entity}</td>
                    <td className="px-5 py-2.5 text-xs font-mono text-muted-foreground truncate max-w-[200px]">
                      {l.entity_id ?? '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </ContentCard>
    </div>
  )
}
