import { FormSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <FormSkeleton
      breadcrumbs={[{ label: 'Configuração' }, { label: 'Global' }]}
      title="Configuração Global"
      groups={5}
    />
  )
}
