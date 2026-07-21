import { Ban, CircleX, GitBranch, MousePointerClick } from 'lucide-react'
import type { CoachUsageSummary as CoachUsageSummaryData } from '@/lib/coach-messages/admin-service'

const METRICS = [
  { key: 'selected', label: 'Selecionadas', icon: MousePointerClick },
  { key: 'suppressed', label: 'Suprimidas', icon: Ban },
  { key: 'balancedFallback', label: 'Fallbacks', icon: GitBranch },
  { key: 'failed', label: 'Falhas', icon: CircleX },
] as const

export function UsageSummary({ summary }: { summary: CoachUsageSummaryData }) {
  return (
    <section className="content-card" aria-label="Resumo de uso do catálogo">
      <div className="grid grid-cols-2 divide-x divide-y divide-border/60 sm:grid-cols-4 sm:divide-y-0">
        {METRICS.map(({ key, label, icon: Icon }) => (
          <div key={key} className="min-w-0 px-4 py-3 sm:px-5">
            <div className="flex items-center gap-2 text-muted-foreground">
              <Icon className="h-3.5 w-3.5" />
              <span className="truncate text-[10px] font-mono uppercase tracking-widest">
                {label}
              </span>
            </div>
            <p className="mt-2 font-mono text-xl font-semibold tabular-nums text-foreground">
              {summary[key].toLocaleString('pt-BR')}
            </p>
          </div>
        ))}
      </div>
    </section>
  )
}
