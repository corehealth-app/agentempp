import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Configuração' }, { label: 'Admins' }]}
      title="Admins"
      rows={5}
    />
  )
}
