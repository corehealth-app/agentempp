import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'

function scoreColor(score: number): string {
  if (score >= 8) return 'bg-moss-100 text-moss-700'
  if (score >= 6) return 'bg-cream-300 text-foreground/80'
  return 'bg-destructive/15 text-destructive'
}

export default async function EvaluationsPage() {
  const svc = createServiceClient()
  const { data: evals } = await svc
    .from('llm_evaluations')
    .select('*')
    .order('evaluated_at', { ascending: false })
    .limit(50)

  const validEvals = evals?.filter((e) => e.score != null) ?? []
  const avgScore =
    validEvals.length > 0
      ? validEvals.reduce((acc, e) => acc + Number(e.score), 0) / validEvals.length
      : null

  const distribution = {
    high: validEvals.filter((e) => Number(e.score) >= 8).length,
    mid: validEvals.filter((e) => Number(e.score) >= 6 && Number(e.score) < 8).length,
    low: validEvals.filter((e) => Number(e.score) < 6).length,
  }

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Visão geral' }, { label: 'Avaliações LLM' }]}
        title="Avaliações LLM"
        description="LLM-as-Judge avalia ~10% das respostas do agente. Permite detectar regressões de qualidade após mudanças em prompts."
      />

      {/* Stats row */}
      <div className="grid gap-4 md:grid-cols-4">
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Score médio
          </div>
          <div className="font-display text-3xl tracking-tight tabular-nums leading-none">
            {avgScore?.toFixed(1) ?? '—'}
            <span className="text-base text-muted-foreground ml-1.5 font-sans">/10</span>
          </div>
          <div className="mt-2 text-xs font-mono text-muted-foreground">
            {validEvals.length} avaliações
          </div>
        </div>
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Score alto (≥8)
          </div>
          <div className="font-display text-3xl tracking-tight tabular-nums leading-none text-moss-700">
            {distribution.high}
          </div>
          <div className="mt-2 text-xs font-mono text-muted-foreground">
            {validEvals.length > 0
              ? `${((distribution.high / validEvals.length) * 100).toFixed(0)}% do total`
              : '—'}
          </div>
        </div>
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Score médio (6-7)
          </div>
          <div className="font-display text-3xl tracking-tight tabular-nums leading-none text-bronze">
            {distribution.mid}
          </div>
          <div className="mt-2 text-xs font-mono text-muted-foreground">
            {validEvals.length > 0
              ? `${((distribution.mid / validEvals.length) * 100).toFixed(0)}% do total`
              : '—'}
          </div>
        </div>
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Score baixo (&lt;6)
          </div>
          <div className="font-display text-3xl tracking-tight tabular-nums leading-none text-destructive">
            {distribution.low}
          </div>
          <div className="mt-2 text-xs font-mono text-muted-foreground">
            {validEvals.length > 0
              ? `${((distribution.low / validEvals.length) * 100).toFixed(0)}% do total`
              : '—'}
          </div>
        </div>
      </div>

      <ContentCard title="Últimas 50 avaliações" description="Score, mensagem do user, resposta do agente e raciocínio do judge">
        {!evals || evals.length === 0 ? (
          <p className="text-sm text-muted-foreground py-2">
            Nenhuma avaliação ainda. Será populada quando o sample-judge rodar.
          </p>
        ) : (
          <ul className="space-y-3">
            {evals.map((e) => (
              <li
                key={e.id}
                className="glass-subtle p-4 hover:bg-muted/40 transition-colors"
              >
                <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
                  <span
                    className={`inline-flex items-center gap-1.5 text-xs font-mono font-medium px-2.5 py-1 rounded-full ${scoreColor(Number(e.score))}`}
                  >
                    <span className="num text-base">{e.score}</span>
                    <span className="text-muted-foreground">/10</span>
                  </span>
                  <span className="text-[10px] font-mono text-muted-foreground">
                    {e.model_used} · {formatDateTime(e.evaluated_at)}
                  </span>
                </div>

                <div className="space-y-2 text-sm">
                  <div>
                    <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-1">
                      Usuário
                    </div>
                    <div className="text-foreground">{e.user_input}</div>
                  </div>
                  <div>
                    <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-1">
                      Resposta
                    </div>
                    <div className="text-foreground">{e.response_obtained}</div>
                  </div>
                  {e.reasoning && (
                    <div className="border-l-2 border-moss-400 pl-3 mt-2">
                      <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-1">
                        Raciocínio do judge
                      </div>
                      <div className="text-foreground/80 italic">{e.reasoning}</div>
                    </div>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </ContentCard>
    </div>
  )
}
