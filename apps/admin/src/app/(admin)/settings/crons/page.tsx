import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { CheckCircle2, Clock, XCircle, Circle } from 'lucide-react'

export default async function CronsPage() {
  const supabase = createServiceClient()
  const { data: jobs, error } = await supabase.from('v_cron_jobs').select('*')

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Crons' }]}
        title="Cron Jobs"
        description="Agendamentos rodando via pg_cron. Cada job dispara um evento Inngest ou executa SQL direto."
      />

      {error && (
        <div className="glass-card border-l-4 border-l-destructive p-4 text-sm">
          <strong>Erro:</strong> {error.message}
        </div>
      )}

      <ContentCard
        title="Jobs ativos"
        description="Configurados no Supabase. Edição via SQL: cron.schedule(...)"
      >
        {!jobs || jobs.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Nenhum cron job configurado ainda.
          </p>
        ) : (
          <ul className="space-y-3">
            {jobs.map((j) => {
              const lastRun =
                (j.last_run as { status?: string; start_time?: string; return_message?: string } | null) ??
                null
              return (
                <li
                  key={j.jobid as number}
                  className="glass-subtle p-4 flex items-start justify-between gap-4"
                >
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 mb-1.5">
                      <Clock className="h-4 w-4 text-muted-foreground shrink-0" />
                      <span className="font-medium text-foreground truncate">{j.jobname}</span>
                      <span
                        className={`inline-flex items-center gap-1 text-[10px] uppercase tracking-widest font-mono px-2 py-0.5 rounded-full shrink-0 ${
                          j.active
                            ? 'bg-moss-100 text-moss-700'
                            : 'bg-muted text-muted-foreground'
                        }`}
                      >
                        <Circle
                          className={`h-2 w-2 ${j.active ? 'fill-moss-500 text-moss-500' : 'fill-muted-foreground text-muted-foreground'}`}
                        />
                        {j.active ? 'ativo' : 'inativo'}
                      </span>
                    </div>
                    <code className="text-xs bg-muted text-foreground px-2 py-0.5 rounded inline-block mb-1.5 font-mono">
                      {j.schedule}
                    </code>
                    <pre className="text-xs text-muted-foreground whitespace-pre-wrap break-all max-w-2xl font-mono">
                      {String(j.command).slice(0, 200)}
                      {String(j.command).length > 200 ? '…' : ''}
                    </pre>
                  </div>
                  <div className="text-right shrink-0 text-xs">
                    <div className="flex items-center gap-1.5 justify-end mb-1">
                      {lastRun?.status === 'succeeded' ? (
                        <CheckCircle2 className="h-3.5 w-3.5 text-moss-500" />
                      ) : lastRun?.status === 'failed' ? (
                        <XCircle className="h-3.5 w-3.5 text-destructive" />
                      ) : null}
                      <span className="font-mono uppercase tracking-widest text-[10px] text-muted-foreground">
                        {lastRun?.status ?? 'nunca'}
                      </span>
                    </div>
                    <div className="text-xs font-mono text-muted-foreground">
                      {lastRun?.start_time ? formatDateTime(lastRun.start_time) : '—'}
                    </div>
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
