/**
 * KpiCard: número grande + delta vs período anterior + sparkline.
 * Padrão visual editorial (Fraunces tabular-nums).
 */
import { ArrowDownRight, ArrowRight, ArrowUpRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Sparkline } from './sparkline'

export interface KpiCardProps {
  label: string
  value: string
  /** série pra sparkline (mais antigo → mais recente) */
  series?: number[]
  /** valor anterior pra calcular delta. Se ausente, usa series[0] */
  previousValue?: number
  /** valor atual (numérico) pra calcular delta. Se ausente, usa series[last] */
  currentValue?: number
  /** mais alto = melhor (default true). Inverte cor do delta quando false (ex: latência, custo) */
  higherIsBetter?: boolean
  /** sub-label opcional (ex: 'últimos 7d') */
  subtitle?: string
  /** ícone à direita */
  icon?: React.ComponentType<{ className?: string }>
  /** href clicável (drill-down) */
  href?: string
  className?: string
}

export function KpiCard({
  label,
  value,
  series,
  previousValue,
  currentValue,
  higherIsBetter = true,
  subtitle,
  icon: Icon,
  className,
}: KpiCardProps) {
  let delta: number | null = null
  let deltaPct: number | null = null
  if (series && series.length >= 2) {
    const cur = currentValue ?? series[series.length - 1] ?? 0
    const prev = previousValue ?? series[0] ?? 0
    delta = cur - prev
    deltaPct = prev !== 0 ? (delta / prev) * 100 : null
  } else if (previousValue !== undefined && currentValue !== undefined) {
    delta = currentValue - previousValue
    deltaPct = previousValue !== 0 ? (delta / previousValue) * 100 : null
  }

  const isUp = delta !== null && delta > 0
  const isDown = delta !== null && delta < 0
  const isFlat = delta === 0
  const trendIsGood = (isUp && higherIsBetter) || (isDown && !higherIsBetter)
  const trendIsBad = (isDown && higherIsBetter) || (isUp && !higherIsBetter)

  const TrendIcon = isFlat ? ArrowRight : isUp ? ArrowUpRight : ArrowDownRight

  return (
    <div className={cn('glass-card p-5', className)}>
      <div className="flex items-center justify-between mb-3">
        <span className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
          {label}
        </span>
        {Icon && <Icon className="h-4 w-4 text-muted-foreground" />}
      </div>
      <div className="flex items-end justify-between gap-3">
        <div>
          <div className="font-display text-3xl tracking-tight tabular-nums leading-none">
            {value}
          </div>
          {delta !== null && (
            <div
              className={cn(
                'mt-2 inline-flex items-center gap-1 text-[11px] font-mono',
                trendIsGood && 'text-moss-700',
                trendIsBad && 'text-rose-600',
                isFlat && 'text-muted-foreground',
              )}
            >
              <TrendIcon className="h-3 w-3" />
              {deltaPct !== null
                ? `${deltaPct > 0 ? '+' : ''}${deltaPct.toFixed(0)}%`
                : `${delta > 0 ? '+' : ''}${delta}`}
              {subtitle && (
                <span className="ml-1.5 text-muted-foreground/80">{subtitle}</span>
              )}
            </div>
          )}
          {delta === null && subtitle && (
            <div className="mt-2 text-[11px] font-mono text-muted-foreground">{subtitle}</div>
          )}
        </div>
        {series && series.length >= 2 && (
          <Sparkline
            data={series}
            width={80}
            height={28}
            trend={
              trendIsBad ? 'negative' : trendIsGood ? 'positive' : 'neutral'
            }
          />
        )}
      </div>
    </div>
  )
}
