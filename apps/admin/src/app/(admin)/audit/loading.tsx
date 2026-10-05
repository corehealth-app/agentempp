import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Flow' }, { label: 'Auditoria' }]}
      title="Auditoria"
      rows={12}
    />
  )
}
