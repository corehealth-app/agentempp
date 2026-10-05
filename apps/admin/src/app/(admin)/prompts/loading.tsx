import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Flow' }, { label: 'Regras' }]}
      title="Regras"
      rows={12}
    />
  )
}
