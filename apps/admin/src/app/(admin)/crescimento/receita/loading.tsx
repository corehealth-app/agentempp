import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[{ label: 'Crescimento' }, { label: 'Receita' }]}
      title="Receita"
      cards={3}
      rows={4}
    />
  )
}
