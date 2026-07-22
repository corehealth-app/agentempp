import { Skeleton } from '@/components/ui/skeleton'

export default function ContentLoading() {
  return (
    <div className="space-y-4" role="status" aria-label="Carregando publicacoes">
      <div className="content-card p-4">
        <Skeleton className="h-7 w-48" />
        <Skeleton className="mt-2 h-4 w-64 max-w-full" />
      </div>
      <div className="content-card p-4">
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {[
            'status',
            'locale',
            'category',
            'author',
            'reviewer',
            'schedule',
            'featured',
            'text',
          ].map((key) => (
            <Skeleton key={key} className="h-9 w-full" />
          ))}
        </div>
      </div>
      <div className="content-card p-4">
        {['one', 'two', 'three', 'four', 'five', 'six', 'seven'].map((key) => (
          <Skeleton key={key} className="mb-3 h-10 w-full last:mb-0" />
        ))}
      </div>
    </div>
  )
}
