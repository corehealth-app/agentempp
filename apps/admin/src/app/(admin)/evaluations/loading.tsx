import { TableSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <TableSkeleton
      breadcrumbs={[{ label: 'Agente' }, { label: 'Avaliações LLM' }]}
      title="Avaliações LLM"
      rows={10}
    />
  )
}
