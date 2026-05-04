import { ContentCard } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatNumber } from '@/lib/utils'

interface FunnelRow {
  cohort_week: string
  cohort_size: number
  s1_messaged: number
  s2_onboarded: number
  s3_logged_meal: number
  s4_closed_block: number
  s5_paying: number
}

function buildSteps(kcalBlock: number): Array<{
  key: keyof FunnelRow
  label: string
  description: string
}> {
  return [
    { key: 'cohort_size', label: 'Cadastrou', description: 'criou conta' },
    { key: 's1_messaged', label: 'Mandou msg', description: 'pelo menos 1 IN' },
    { key: 's2_onboarded', label: 'Onboarding ✓', description: 'completou questionário' },
    { key: 's3_logged_meal', label: '1ª refeição', description: 'logou meal' },
    { key: 's4_closed_block', label: '1º bloco', description: `${kcalBlock} kcal de déficit` },
    { key: 's5_paying', label: 'Pagou', description: 'subscription active|trial' },
  ]
}

export async function FunilView() {
  const svc = createServiceClient()
  const [{ data: rawFunnel }, { data: kcalBlockRow }] = await Promise.all([
    (svc as unknown as {
      from: (t: string) => {
        select: (s: string) => {
          order: (col: string, opt: { ascending: boolean }) => Promise<{ data: FunnelRow[] | null }>
        }
      }
    })
      .from('v_funnel_activation')
      .select('*')
      .order('cohort_week', { ascending: false }),
    (svc as unknown as {
      from: (t: string) => {
        select: (s: string) => {
          eq: (col: string, val: string) => {
            maybeSingle: () => Promise<{ data: { value: unknown } | null }>
          }
        }
      }
    })
      .from('global_config')
      .select('value')
      .eq('key', 'calc.kcal_block')
      .maybeSingle(),
  ])

  const funnel = rawFunnel ?? []
  const STEPS = buildSteps(Number(kcalBlockRow?.value ?? 7700))

  const allTimeTotals = funnel.reduce(
    (acc, f) => {
      for (const s of STEPS) {
        acc[s.key] = (acc[s.key] ?? 0) + Number(f[s.key] ?? 0)
      }
      return acc
    },
    {} as Record<keyof FunnelRow, number>,
  )

  return (
    <div className="space-y-4">

      <ContentCard
        title="Funil agregado (8 semanas)"
        description="Conversão acumulada de todos os cohorts juntos"
      >
        <FunnelDisplay
          steps={STEPS.map((s) => ({
            label: s.label,
            description: s.description,
            n: Number(allTimeTotals[s.key] ?? 0),
          }))}
        />
      </ContentCard>

      <ContentCard
        title="Cohorts semanais"
        description="Cada linha é uma semana de cadastros"
      >
        {funnel.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sem cohorts ainda.</p>
        ) : (
          <div className="overflow-x-auto -mx-5">
            <table className="w-full text-xs">
              <thead className="text-muted-foreground/80 border-b border-border">
                <tr>
                  <th className="text-left font-mono uppercase tracking-widest px-5 py-2 text-[10px]">
                    Semana
                  </th>
                  <th className="text-right font-mono uppercase tracking-widest px-3 py-2 text-[10px]">
                    Cohort
                  </th>
                  {STEPS.slice(1).map((s) => (
                    <th
                      key={s.key}
                      className="text-right font-mono uppercase tracking-widest px-3 py-2 text-[10px]"
                    >
                      {s.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {funnel.map((f) => {
                  const cohort = f.cohort_size || 1
                  const week = new Date(f.cohort_week).toLocaleDateString('pt-BR', {
                    day: '2-digit',
                    month: 'short',
                  })
                  return (
                    <tr key={f.cohort_week} className="border-b border-border/40 hover:bg-muted/20">
                      <td className="px-5 py-2.5 font-mono text-foreground">{week}</td>
                      <td className="px-3 py-2.5 text-right font-mono tabular-nums">
                        {f.cohort_size}
                      </td>
                      {STEPS.slice(1).map((s) => {
                        const n = Number(f[s.key] ?? 0)
                        const pct = (n / cohort) * 100
                        return (
                          <td
                            key={s.key}
                            className="px-3 py-2.5 text-right font-mono tabular-nums"
                          >
                            <span className="text-foreground">{n}</span>
                            <span className="text-muted-foreground/70 ml-1.5 text-[10px]">
                              {pct.toFixed(0)}%
                            </span>
                          </td>
                        )
                      })}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </ContentCard>
    </div>
  )
}

function FunnelDisplay({
  steps,
}: {
  steps: Array<{ label: string; description: string; n: number }>
}) {
  if (steps.length === 0 || steps[0]?.n === 0) {
    return <p className="text-sm text-muted-foreground">Sem dados ainda.</p>
  }
  const max = steps[0]!.n
  return (
    <div className="space-y-2">
      {steps.map((s, i) => {
        const pct = (s.n / max) * 100
        const dropoff =
          i > 0 && steps[i - 1] ? ((s.n - steps[i - 1]!.n) / steps[i - 1]!.n) * 100 : 0
        return (
          <div key={s.label} className="flex items-center gap-3 text-sm">
            <div className="w-32 shrink-0">
              <div className="font-medium text-foreground">{s.label}</div>
              <div className="text-[10px] font-mono text-muted-foreground">{s.description}</div>
            </div>
            <div className="flex-1 h-7 bg-muted/30 rounded relative overflow-hidden">
              <div
                className="absolute inset-y-0 left-0 bg-gradient-to-r from-moss-400 to-moss-600 rounded transition-all flex items-center px-3"
                style={{ width: `${pct}%` }}
              >
                <span className="text-cream-100 font-mono text-xs tabular-nums">
                  {formatNumber(s.n)}
                </span>
              </div>
            </div>
            <div className="w-20 text-right">
              <div className="font-mono tabular-nums text-foreground">{pct.toFixed(0)}%</div>
              {i > 0 && (
                <div className="text-[10px] font-mono text-rose-500">
                  {dropoff.toFixed(0)}%
                </div>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}
