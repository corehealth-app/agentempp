import { FormSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <FormSkeleton
      breadcrumbs={[{ label: 'Flow' }, { label: 'Sub-agentes' }]}
      title="Sub-agentes"
      groups={6}
    />
  )
}
