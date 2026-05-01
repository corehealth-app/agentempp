import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'

export default async function AuditPage() {
  const svc = createServiceClient()
  const { data: logs } = await svc
    .from('audit_log')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(200)

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Auditoria</h1>
        <p className="text-muted-foreground">Últimas 200 ações sensíveis</p>
      </div>

      <Card>
        <CardContent className="pt-6">
          {!logs || logs.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem registros.</p>
          ) : (
            <table className="w-full text-sm">
              <thead className="text-xs text-muted-foreground">
                <tr className="border-b">
                  <th className="text-left py-2">Quando</th>
                  <th className="text-left py-2">Quem</th>
                  <th className="text-left py-2">Ação</th>
                  <th className="text-left py-2">Entidade</th>
                  <th className="text-left py-2">ID</th>
                </tr>
              </thead>
              <tbody>
                {logs.map((l) => (
                  <tr key={l.id} className="border-b last:border-0">
                    <td className="py-2 text-xs">{formatDateTime(l.created_at)}</td>
                    <td className="py-2 text-xs">{l.actor_email ?? '—'}</td>
                    <td className="py-2">
                      <Badge variant="outline" className="text-xs">
                        {l.action}
                      </Badge>
                    </td>
                    <td className="py-2 text-xs">{l.entity}</td>
                    <td className="py-2 text-xs font-mono truncate max-w-[200px]">
                      {l.entity_id ?? '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
