import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime, formatUSD } from '@/lib/utils'
import Link from 'next/link'

export default async function MessagesPage() {
  const svc = createServiceClient()
  const { data: messages } = await svc
    .from('messages')
    .select(
      'id, user_id, direction, content, content_type, agent_stage, model_used, prompt_tokens, completion_tokens, cost_usd, latency_ms, created_at',
    )
    .order('created_at', { ascending: false })
    .limit(100)

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Mensagens</h1>
        <p className="text-muted-foreground">Últimas 100 mensagens (in + out)</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Log</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {!messages || messages.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem mensagens ainda.</p>
          ) : (
            messages.map((m) => (
              <div
                key={m.id}
                className="border rounded-lg p-3 text-sm space-y-1 hover:bg-muted/30"
              >
                <div className="flex items-center justify-between gap-2 flex-wrap text-xs">
                  <div className="flex items-center gap-2">
                    <Badge variant={m.direction === 'in' ? 'secondary' : 'default'}>
                      {m.direction}
                    </Badge>
                    {m.agent_stage && <Badge variant="outline">{m.agent_stage}</Badge>}
                    <Badge variant="outline">{m.content_type}</Badge>
                    <Link
                      href={`/users/${m.user_id}`}
                      className="text-muted-foreground underline hover:text-foreground"
                    >
                      user
                    </Link>
                  </div>
                  <div className="text-muted-foreground">
                    {m.prompt_tokens != null &&
                      `${m.prompt_tokens}+${m.completion_tokens} tok · `}
                    {m.cost_usd != null && `${formatUSD(Number(m.cost_usd), 5)} · `}
                    {m.latency_ms != null && `${m.latency_ms}ms · `}
                    {formatDateTime(m.created_at)}
                  </div>
                </div>
                <div className="whitespace-pre-wrap">{m.content ?? '(mídia)'}</div>
                {m.model_used && (
                  <code className="text-xs text-muted-foreground">{m.model_used}</code>
                )}
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </div>
  )
}
