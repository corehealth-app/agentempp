import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'

export default async function EvaluationsPage() {
  const svc = createServiceClient()
  const { data: evals } = await svc
    .from('llm_evaluations')
    .select('*')
    .order('evaluated_at', { ascending: false })
    .limit(50)

  const avgScore =
    evals && evals.length > 0
      ? evals.reduce((acc, e) => acc + (Number(e.score) ?? 0), 0) / evals.length
      : null

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Avaliações LLM</h1>
        <p className="text-muted-foreground">
          LLM-as-Judge — sample 10% das respostas. Score médio:{' '}
          <strong>{avgScore?.toFixed(1) ?? '—'}/10</strong>
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Últimas 50 avaliações</CardTitle>
        </CardHeader>
        <CardContent>
          {!evals || evals.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Nenhuma avaliação ainda. Será populada quando o sample-judge rodar.
            </p>
          ) : (
            <ul className="space-y-3">
              {evals.map((e) => (
                <li key={e.id} className="border rounded p-3 text-sm">
                  <div className="flex items-center justify-between mb-1">
                    <Badge
                      variant={
                        Number(e.score) >= 8
                          ? 'default'
                          : Number(e.score) >= 6
                            ? 'secondary'
                            : 'destructive'
                      }
                    >
                      {e.score}/10
                    </Badge>
                    <span className="text-xs text-muted-foreground">
                      {e.model_used} · {formatDateTime(e.evaluated_at)}
                    </span>
                  </div>
                  <div className="text-xs text-muted-foreground">User: {e.user_input}</div>
                  <div className="text-xs mt-1">Resposta: {e.response_obtained}</div>
                  {e.reasoning && (
                    <div className="text-xs italic text-muted-foreground mt-1 border-l-2 pl-2">
                      Reasoning: {e.reasoning}
                    </div>
                  )}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
