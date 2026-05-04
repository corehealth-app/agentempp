import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Operação' }, { label: 'Usuários' }]}
      title="Usuários"
      rows={10}
    />
  )
}
