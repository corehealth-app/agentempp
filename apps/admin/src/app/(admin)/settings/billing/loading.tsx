import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Configuração' }, { label: 'Billing' }]}
      title="Billing"
      rows={8}
    />
  )
}
