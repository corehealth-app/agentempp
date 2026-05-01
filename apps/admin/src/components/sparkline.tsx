/**
 * Sparkline minimalista em SVG, sem dependência externa.
 * Renderiza até ~30 pontos em <120 bytes de DOM.
 */
import { cn } from '@/lib/utils'

export interface SparklineProps {
  data: number[]
  width?: number
  height?: number
  className?: string
  /** 'positive' verde, 'negative' vermelho, 'neutral' cinza, 'auto' = comparando 1º com último */
  trend?: 'auto' | 'positive' | 'negative' | 'neutral'
  filled?: boolean
}

export function Sparkline({
  data,
  width = 120,
  height = 28,
  className,
  trend = 'auto',
  filled = true,
}: SparklineProps) {
  if (!data || data.length < 2) {
    return <div className={cn('h-7 opacity-40', className)} style={{ width }} />
  }

  const min = Math.min(...data)
  const max = Math.max(...data)
  const range = max - min || 1
  const stepX = width / (data.length - 1)

  const points = data.map((v, i) => {
    const x = i * stepX
    const y = height - ((v - min) / range) * height
    return [x, y] as const
  })

  const linePath = points.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`).join(' ')
  const areaPath = `${linePath} L${width.toFixed(1)},${height} L0,${height} Z`

  const computedTrend =
    trend === 'auto'
      ? data[data.length - 1]! > data[0]!
        ? 'positive'
        : data[data.length - 1]! < data[0]!
          ? 'negative'
          : 'neutral'
      : trend

  const colors = {
    positive: 'text-moss-600',
    negative: 'text-rose-500',
    neutral: 'text-muted-foreground',
  }

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className={cn(colors[computedTrend], className)}
      preserveAspectRatio="none"
    >
      {filled && <path d={areaPath} fill="currentColor" opacity={0.12} />}
      <path d={linePath} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinejoin="round" />
    </svg>
  )
}
