import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[{ label: 'Crescimento' }, { label: 'Funil & Cohorts' }]}
      title="Funil de ativação"
      cards={3}
      rows={4}
    />
  )
}
