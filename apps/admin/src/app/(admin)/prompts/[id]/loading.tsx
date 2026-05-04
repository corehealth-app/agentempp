import { PageSkeleton } from '@/components/skeletons'

export default function Loading() {
  return (
    <PageSkeleton
      breadcrumbs={[{ label: 'Agente' }, { label: 'Regras', href: '/prompts' }, { label: 'Carregando…' }]}
      title="Regra"
      cards={2}
      rows={6}
    />
  )
}
