import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Agente' }, { label: 'Auditoria' }]}
      title="Auditoria"
      rows={12}
    />
  )
}
