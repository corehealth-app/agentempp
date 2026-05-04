import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[
        { label: 'Operação' },
        { label: 'Usuários', href: '/users' },
        { label: 'Carregando…' },
      ]}
      title="Paciente"
      cards={5}
      rows={5}
    />
  )
}
