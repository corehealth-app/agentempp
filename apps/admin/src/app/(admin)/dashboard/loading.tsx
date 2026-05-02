import { PageHeader } from '@/components/page-header'

export default function DashboardLoading() {
  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Hoje' }]}
        title="Hoje"
        description="Carregando dados do dia..."
      />
      <div className="content-card p-5 space-y-2">
        <div className="h-3 w-40 rounded bg-muted animate-pulse" />
        <div className="h-6 w-72 rounded bg-muted/70 animate-pulse" />
      </div>
      <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <KpiSkeleton key={i} />
        ))}
      </div>
      <div className="grid gap-4 lg:grid-cols-3">
        <div className="content-card lg:col-span-2 p-5 space-y-3">
          <div className="h-4 w-48 rounded bg-muted animate-pulse" />
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="h-3 rounded bg-muted/50 animate-pulse" />
          ))}
        </div>
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <KpiSkeleton key={i} />
          ))}
        </div>
      </div>
    </div>
  )
}

function KpiSkeleton() {
  return (
    <div className="glass-card p-5 space-y-3">
      <div className="h-2 w-20 rounded bg-muted animate-pulse" />
      <div className="h-8 w-16 rounded bg-muted/80 animate-pulse" />
      <div className="h-2 w-24 rounded bg-muted/50 animate-pulse" />
    </div>
  )
}
