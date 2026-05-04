import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[{ label: 'Crescimento' }]}
      title="Crescimento"
      cards={5}
      rows={4}
    />
  )
}
