import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[{ label: 'Crescimento' }, { label: 'Conquistas' }]}
      title="Conquistas"
      cards={4}
      rows={5}
    />
  )
}
