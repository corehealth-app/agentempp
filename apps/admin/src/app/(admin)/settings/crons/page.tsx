import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { CheckCircle2, Clock, XCircle } from 'lucide-react'

export default async function CronsPage() {
  const supabase = createServiceClient()
  const { data: jobs, error } = await supabase.from('v_cron_jobs').select('*')

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Cron Jobs</h1>
        <p className="text-muted-foreground">
          Agendamentos rodando via <code>pg_cron</code>. Cada job dispara um evento Inngest ou
          executa SQL direto.
        </p>
      </div>

      {error && (
        <Card>
          <CardContent className="pt-6 text-sm text-muted-foreground">
            Não foi possível ler <code>v_cron_jobs</code>: {error.message}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Jobs ativos</CardTitle>
          <CardDescription>
            Configurados no Supabase. Edição via SQL: <code>cron.schedule(...)</code>.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {!jobs || jobs.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Nenhum cron job configurado ainda. Eles serão criados pela Fase 4 (daily-closer +
              engagement).
            </p>
          ) : (
            <div className="space-y-3">
              {jobs.map((j) => {
                const lastRun = (j.last_run as { status?: string; start_time?: string } | null) ?? null
                return (
                  <div
                    key={j.jobid as number}
                    className="border rounded-lg p-4 flex items-start justify-between gap-4"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <Clock className="h-4 w-4 text-muted-foreground" />
                        <span className="font-medium">{j.jobname}</span>
                        {j.active ? (
                          <Badge variant="default" className="text-xs">
                            ativo
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="text-xs">
                            inativo
                          </Badge>
                        )}
                      </div>
                      <code className="text-xs bg-muted px-2 py-0.5 rounded inline-block mb-1">
                        {j.schedule}
                      </code>
                      <pre className="text-xs text-muted-foreground whitespace-pre-wrap break-all max-w-2xl mt-1">
                        {String(j.command).slice(0, 200)}
                        {String(j.command).length > 200 ? '…' : ''}
                      </pre>
                    </div>
                    <div className="text-right text-xs text-muted-foreground shrink-0">
                      {lastRun?.status === 'succeeded' ? (
                        <CheckCircle2 className="h-4 w-4 text-green-500 inline mr-1" />
                      ) : lastRun?.status === 'failed' ? (
                        <XCircle className="h-4 w-4 text-red-500 inline mr-1" />
                      ) : null}
                      {lastRun?.start_time ? formatDateTime(lastRun.start_time) : 'nunca rodou'}
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
