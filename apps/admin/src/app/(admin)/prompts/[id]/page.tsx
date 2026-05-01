import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { notFound } from 'next/navigation'
import { RuleEditor } from './editor'

export default async function RuleEditPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = createServiceClient()
  const { data: rule } = await supabase
    .from('agent_rules')
    .select('*')
    .eq('id', id)
    .maybeSingle()

  if (!rule) notFound()

  const { data: versions } = await supabase
    .from('agent_rules_versions')
    .select('version_num, status, change_reason, changed_at')
    .eq('rule_id', id)
    .order('version_num', { ascending: false })
    .limit(20)

  return (
    <div className="space-y-6 p-6 max-w-5xl">
      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <Badge variant="outline">{rule.tipo}</Badge>
          <h1 className="text-2xl font-bold">{rule.topic}</h1>
          <p className="text-sm text-muted-foreground font-mono">{rule.slug}</p>
        </div>
        <div className="text-right text-xs text-muted-foreground">
          atualizado em {formatDateTime(rule.updated_at)}
          <br />~{rule.token_estimate ?? 0} tokens
        </div>
      </div>

      <RuleEditor
        id={rule.id}
        topic={rule.topic}
        tipo={rule.tipo}
        content={rule.content}
        status={rule.status}
        displayOrder={rule.display_order}
      />

      {/* Histórico */}
      <Card>
        <CardHeader>
          <CardTitle>Histórico de versões</CardTitle>
          <CardDescription>Últimas 20 alterações registradas pelo trigger</CardDescription>
        </CardHeader>
        <CardContent>
          {!versions || versions.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem histórico ainda.</p>
          ) : (
            <ul className="space-y-1 text-sm">
              {versions.map((v) => (
                <li
                  key={v.version_num}
                  className="flex items-center justify-between border-b py-1 last:border-0"
                >
                  <span>
                    <code className="text-xs bg-muted px-1.5 py-0.5 rounded">
                      v{v.version_num}
                    </code>{' '}
                    <Badge variant="outline" className="text-xs">
                      {v.status}
                    </Badge>{' '}
                    {v.change_reason ?? '(sem motivo)'}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {formatDateTime(v.changed_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
