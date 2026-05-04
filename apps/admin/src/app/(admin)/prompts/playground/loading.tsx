import { FormSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <FormSkeleton
      breadcrumbs={[{ label: 'Agente' }, { label: 'Playground' }]}
      title="Playground"
      groups={2}
    />
  )
}
