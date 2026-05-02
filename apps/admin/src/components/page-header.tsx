import { ChevronRight, Home } from 'lucide-react'
import Link from 'next/link'
import { cn } from '@/lib/utils'

interface BreadcrumbItem {
  label: string
  href?: string
}

interface PageHeaderProps {
  title: string
  description?: React.ReactNode
  breadcrumbs?: BreadcrumbItem[]
  actions?: React.ReactNode
  children?: React.ReactNode
  className?: string
  compact?: boolean
}

export function PageHeader({
  title,
  description,
  breadcrumbs,
  actions,
  children,
  className,
  compact = false,
}: PageHeaderProps) {
  return (
    <div className={cn('glass-card', compact ? 'p-4' : 'p-6', className)}>
      {/* Breadcrumbs */}
      {breadcrumbs && breadcrumbs.length > 0 && (
        <nav className="flex items-center gap-1 text-sm text-muted-foreground mb-3">
          <Link href="/dashboard" className="hover:text-foreground transition-colors">
            <Home className="w-4 h-4" />
          </Link>
          {breadcrumbs.map((crumb, index) => (
            <div key={index} className="flex items-center gap-1">
              <ChevronRight className="w-4 h-4" />
              {crumb.href ? (
                <Link href={crumb.href} className="hover:text-foreground transition-colors">
                  {crumb.label}
                </Link>
              ) : (
                <span className="text-foreground">{crumb.label}</span>
              )}
            </div>
          ))}
        </nav>
      )}

      {/* Header row */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div className="min-w-0">
          <h1 className="font-display text-2xl md:text-3xl text-foreground tracking-tight leading-tight text-balance">
            {title}
          </h1>
          {description && (
            <div className="mt-1.5 text-sm text-muted-foreground text-pretty max-w-2xl">
              {description}
            </div>
          )}
        </div>
        {actions && <div className="shrink-0 flex items-center gap-2">{actions}</div>}
      </div>

      {children && <div className="mt-4">{children}</div>}
    </div>
  )
}

export function StatCard({
  label,
  value,
  subtitle,
  icon: Icon,
  variant = 'default',
}: {
  label: string
  value: string
  subtitle?: string
  icon?: React.ComponentType<{ className?: string }>
  variant?: 'default' | 'feature' | 'inverted'
}) {
  return (
    <div
      className={cn(
        'glass-card p-5 transition-colors',
        variant === 'feature' && '!bg-moss-700 !text-cream-100 !border-moss-700',
        variant === 'inverted' && '!bg-ink-900 !text-cream-100 !border-ink-900',
      )}
    >
      <div className="flex items-center justify-between mb-3">
        <span
          className={cn(
            'text-[10px] font-mono uppercase tracking-widest',
            variant === 'default' ? 'text-muted-foreground' : 'text-cream-100/60',
          )}
        >
          {label}
        </span>
        {Icon && (
          <Icon
            className={cn(
              'h-4 w-4',
              variant === 'default' ? 'text-muted-foreground' : 'text-cream-100/60',
            )}
          />
        )}
      </div>
      <div className="font-display text-3xl tracking-tight tabular-nums leading-none">{value}</div>
      {subtitle && (
        <div
          className={cn(
            'mt-2 text-xs font-mono',
            variant === 'default' ? 'text-muted-foreground' : 'text-cream-100/60',
          )}
        >
          {subtitle}
        </div>
      )}
    </div>
  )
}

export function ContentCard({
  children,
  className,
  title,
  description,
  actions,
  bodyClassName,
}: {
  children: React.ReactNode
  className?: string
  title?: string
  description?: string
  actions?: React.ReactNode
  /** Override classes do `<div>` que envolve children. Default 'p-5'. */
  bodyClassName?: string
}) {
  if (!title) {
    return <div className={cn('content-card', className)}>{children}</div>
  }
  return (
    <div className={cn('content-card', className)}>
      <div className="shrink-0 flex items-start justify-between gap-3 px-5 py-4 border-b border-border bg-muted/30">
        <div className="min-w-0">
          <h3 className="font-display text-base text-foreground tracking-tight">{title}</h3>
          {description && (
            <p className="text-xs text-muted-foreground mt-0.5">{description}</p>
          )}
        </div>
        {actions && <div className="shrink-0">{actions}</div>}
      </div>
      <div className={cn(bodyClassName ?? 'p-5')}>{children}</div>
    </div>
  )
}
