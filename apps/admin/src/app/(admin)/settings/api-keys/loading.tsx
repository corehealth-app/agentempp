import { FormSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <FormSkeleton
      breadcrumbs={[{ label: 'Configuração' }, { label: 'API Keys' }]}
      title="API Keys"
      groups={4}
    />
  )
}
