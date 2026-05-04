import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[{ label: 'Configuração' }, { label: 'Stripe' }]}
      title="Stripe"
      cards={2}
    />
  )
}
