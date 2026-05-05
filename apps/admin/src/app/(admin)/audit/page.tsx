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

  // Alucinações numéricas detectadas pelo validador de saída — últimas 24h
  const since24h = new Date(Date.now() - 24 * 3600 * 1000).toISOString()
  const { data: mismatches, count: mismatchCount } = await (svc as unknown as {
    from: (t: string) => {
      select: (
        s: string,
        opts?: { count?: 'exact' },
      ) => {
        eq: (col: string, val: string) => {
          gte: (col: string, val: string) => {
            order: (col: string, opt: { ascending: boolean }) => {
              limit: (n: number) => Promise<{
                data: Array<{
                  id: string
                  user_id: string | null
                  created_at: string
                  properties: Record<string, unknown>
                }> | null
                count: number | null
              }>
            }
          }
        }
      }
    }
  })
    .from('product_events')
    .select('id, user_id, created_at, properties', { count: 'exact' })
    .eq('event', 'llm.numeric_mismatch')
    .gte('created_at', since24h)
    .order('created_at', { ascending: false })
    .limit(20)

  return (
    <div className="flex flex-col h-full">
      <div className="shrink-0 mb-3">
        <PageHeader
          compact
          breadcrumbs={[{ label: 'Operação' }, { label: 'Auditoria' }]}
          title="Auditoria"
          description={`${logs?.length ?? 0} ações sensíveis (credentials, regras, configs, admins).`}
        />
      </div>

      {(mismatchCount ?? 0) > 0 && (
        <div className="shrink-0 mb-3 content-card p-4 border-l-4 border-destructive">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-semibold">
              ⚠️ Alucinações numéricas detectadas (24h): {mismatchCount}
            </h3>
            <span className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground">
              event: llm.numeric_mismatch
            </span>
          </div>
          <p className="text-xs text-muted-foreground mb-3">
            Validador parseou números na resposta do agente e achou divergência &gt;10% vs valor
            real. Não bloqueou a msg — apenas auditou. Investigue se padrão.
          </p>
          <ul className="space-y-2 text-xs font-mono max-h-60 overflow-auto">
            {(mismatches ?? []).map((m) => {
              const findings = (m.properties as { findings?: Array<Record<string, unknown>> })
                .findings
              return (
                <li key={m.id} className="border-l-2 border-border pl-2">
                  <div className="text-muted-foreground">
                    {formatDateTime(m.created_at)} · user {m.user_id?.slice(0, 8)} ·{' '}
                    <span className="font-bold">{findings?.length ?? 0}</span> finding(s)
                  </div>
                  {(findings ?? []).slice(0, 3).map((f, i) => (
                    <div key={i} className="text-foreground/80">
                      <span className="text-bronze">{String(f.field)}</span>: disse{' '}
                      <span className="text-destructive">{String(f.claimed)}</span> vs real{' '}
                      <span className="text-moss-700">{String(f.real)}</span> (
                      {(Number(f.diff_pct) * 100).toFixed(0)}% off)
                    </div>
                  ))}
                </li>
              )
            })}
          </ul>
        </div>
      )}

      <ContentCard className="flex-1 min-h-0 flex flex-col overflow-hidden">
        {!logs || logs.length === 0 ? (
          <p className="text-sm text-muted-foreground py-4 px-5">Sem registros ainda.</p>
        ) : (
          <div className="flex-1 overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-[10px] uppercase tracking-widest text-muted-foreground bg-muted/40 border-b border-border sticky top-0 z-10">
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
