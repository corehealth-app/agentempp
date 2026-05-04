import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Configuração' }, { label: 'Crons' }]}
      title="Cron Jobs"
      rows={10}
    />
  )
}
