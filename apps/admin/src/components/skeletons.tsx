/**
 * Skeletons reutilizáveis pra loading.tsx das rotas.
 * Mantém a aparência consistente em toda a plataforma.
 */
import { PageHeader } from '@/components/page-header'

export function PageSkeleton({
  breadcrumbs,
  title,
  cards = 3,
  rows = 4,
}: {
  breadcrumbs: Array<{ label: string; href?: string }>
  title: string
  cards?: number
  rows?: number
}) {
  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={breadcrumbs}
        title={title}
        description="Carregando..."
      />
      {Array.from({ length: cards }).map((_, i) => (
        <div key={i} className="content-card p-5 space-y-3">
          <div className="h-4 w-48 rounded bg-muted animate-pulse" />
          {Array.from({ length: rows }).map((_, j) => (
            <div
              key={j}
              className="h-3 rounded bg-muted/50 animate-pulse"
              style={{ width: `${60 + ((i * 7 + j * 11) % 35)}%` }}
            />
          ))}
        </div>
      ))}
    </div>
  )
}

export function TableSkeleton({
  breadcrumbs,
  title,
  rows = 8,
}: {
  breadcrumbs: Array<{ label: string; href?: string }>
  title: string
  rows?: number
}) {
  return (
    <div className="space-y-4">
      <PageHeader breadcrumbs={breadcrumbs} title={title} description="Carregando..." />
      <div className="content-card overflow-hidden">
        <div className="border-b border-border bg-muted/30 px-5 py-3 flex gap-6">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="h-3 w-20 rounded bg-muted animate-pulse" />
          ))}
        </div>
        <div className="divide-y divide-border/40">
          {Array.from({ length: rows }).map((_, i) => (
            <div key={i} className="px-5 py-3 flex items-center gap-6">
              <div className="h-8 w-8 rounded-full bg-muted/70 animate-pulse" />
              <div className="flex-1 space-y-1.5">
                <div className="h-3 w-1/3 rounded bg-muted animate-pulse" />
                <div className="h-2 w-1/2 rounded bg-muted/40 animate-pulse" />
              </div>
              <div className="h-3 w-16 rounded bg-muted/50 animate-pulse" />
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

export function FormSkeleton({
  breadcrumbs,
  title,
  groups = 3,
}: {
  breadcrumbs: Array<{ label: string; href?: string }>
  title: string
  groups?: number
}) {
  return (
    <div className="space-y-4">
      <PageHeader breadcrumbs={breadcrumbs} title={title} description="Carregando..." />
      {Array.from({ length: groups }).map((_, g) => (
        <div key={g} className="content-card p-5 space-y-4">
          <div className="h-5 w-40 rounded bg-muted animate-pulse" />
          <div className="grid gap-3 md:grid-cols-2">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="glass-subtle p-3 space-y-2">
                <div className="h-3 w-24 rounded bg-muted animate-pulse" />
                <div className="h-9 w-full rounded bg-muted/50 animate-pulse" />
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
