import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[{ label: 'Tutorial' }]}
      title="O que dá pra mexer"
      cards={5}
      rows={4}
    />
  )
}
