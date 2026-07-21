import { Skeleton } from '@/components/ui/skeleton'

export default function CoachMessagesLoading() {
  return (
    <div
      className="space-y-4"
      role="status"
      aria-busy="true"
      aria-label="Carregando catálogo de mensagens"
    >
      <div className="content-card space-y-3 p-6">
        <Skeleton className="h-4 w-44" />
        <Skeleton className="h-8 w-80 max-w-full" />
        <Skeleton className="h-4 w-full max-w-2xl" />
      </div>
      <Skeleton className="h-20 w-full" />
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-[420px] w-full" />
    </div>
  )
}
