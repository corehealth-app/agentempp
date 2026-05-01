import { cn } from '@/lib/utils'

export function PageHeader({
  chapter,
  eyebrow,
  title,
  description,
  actions,
  className,
}: {
  chapter?: string
  eyebrow?: string
  title: string
  description?: string
  actions?: React.ReactNode
  className?: string
}) {
  return (
    <header className={cn('mb-10 flex items-start justify-between gap-6', className)}>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-3 mb-3">
          {chapter && (
            <span className="font-mono text-xs text-ink-500 tabular-nums tracking-widest">
              CAPÍTULO {chapter}
            </span>
          )}
          {chapter && eyebrow && <span className="text-ink-400">·</span>}
          {eyebrow && <span className="section-eyebrow">{eyebrow}</span>}
        </div>
        <h1 className="font-display text-4xl md:text-5xl text-ink-900 tracking-tight text-balance leading-[1.05]">
          {title}
        </h1>
        {description && (
          <p className="mt-3 text-ink-600 text-pretty max-w-2xl">{description}</p>
        )}
      </div>
      {actions && <div className="shrink-0 flex items-center gap-2">{actions}</div>}
    </header>
  )
}

export function StatCard({
  label,
  value,
  subtitle,
  trend,
  variant = 'default',
}: {
  label: string
  value: string
  subtitle?: string
  trend?: 'up' | 'down' | 'flat'
  variant?: 'default' | 'feature' | 'inverted'
}) {
  return (
    <div
      className={cn(
        'border border-border p-5 rounded-sm transition-colors',
        variant === 'default' && 'bg-cream-50 hover:border-ink-300',
        variant === 'feature' && 'bg-moss-700 text-cream-100 border-moss-700',
        variant === 'inverted' && 'bg-ink-900 text-cream-100 border-ink-900',
      )}
    >
      <div
        className={cn(
          'section-eyebrow mb-3 truncate',
          variant !== 'default' && '!text-cream-100/50',
        )}
      >
        {label}
      </div>
      <div className="font-display text-3xl tracking-tight tabular-nums">{value}</div>
      {subtitle && (
        <div
          className={cn(
            'mt-1.5 text-xs font-mono',
            variant === 'default' ? 'text-ink-500' : 'text-cream-100/60',
          )}
        >
          {subtitle}
        </div>
      )}
    </div>
  )
}
