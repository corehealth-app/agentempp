import { PageHeader } from '@/components/page-header'

export default function MessagesLoading() {
  return (
    <div className="space-y-3">
      <PageHeader
        breadcrumbs={[{ label: 'Operação' }, { label: 'Conversas' }]}
        title="Conversas"
        description="Carregando inbox..."
      />
      <div className="grid gap-3 lg:grid-cols-[340px_1fr] min-h-[600px]">
        <div className="content-card overflow-hidden">
          <div className="flex gap-1 p-2 border-b border-border bg-muted/30">
            <SkeletonChip /> <SkeletonChip /> <SkeletonChip />
          </div>
          <div className="flex flex-col gap-0">
            {Array.from({ length: 8 }).map((_, i) => (
              <SkeletonRow key={i} />
            ))}
          </div>
        </div>
        <div className="content-card flex items-center justify-center text-sm text-muted-foreground">
          carregando…
        </div>
      </div>
    </div>
  )
}

function SkeletonChip() {
  return <div className="flex-1 h-7 rounded bg-muted animate-pulse" />
}

function SkeletonRow() {
  return (
    <div className="flex items-start gap-3 p-3 border-b border-border/40">
      <div className="shrink-0 h-9 w-9 rounded-full bg-muted animate-pulse" />
      <div className="flex-1 space-y-2">
        <div className="h-3 w-24 rounded bg-muted animate-pulse" />
        <div className="h-3 w-40 rounded bg-muted/70 animate-pulse" />
      </div>
    </div>
  )
}
