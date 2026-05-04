import { FormSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <FormSkeleton
      breadcrumbs={[{ label: 'Configuração' }, { label: 'Cálculos' }]}
      title="Constantes de cálculo"
      groups={4}
    />
  )
}
