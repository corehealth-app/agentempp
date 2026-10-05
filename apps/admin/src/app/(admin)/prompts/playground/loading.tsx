import { FormSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <FormSkeleton
      breadcrumbs={[{ label: 'Legado (WhatsApp)' }, { label: 'Playground' }]}
      title="Playground"
      groups={2}
    />
  )
}
