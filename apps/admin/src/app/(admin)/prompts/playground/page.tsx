import { AdminAccessDenied } from '@/components/admin-access-denied'
import { ContentCard, PageHeader } from '@/components/page-header'
import { guardAdminPage } from '@/lib/admin-page-guard'
import { PlaygroundForm } from './form'

export default async function PlaygroundPage() {
  const access = await guardAdminPage('/prompts/playground')
  if (!access.ok) return <AdminAccessDenied access={access} />

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Legado (WhatsApp)' }, { label: 'Playground' }]}
        title="Playground"
        description="Teste o agente em tempo real. Cada mensagem passa pela mesma pipeline que o WhatsApp usaria — incluindo regras, tools e cálculo TACO."
      />
      <ContentCard className="overflow-visible">
        <PlaygroundForm />
      </ContentCard>
    </div>
  )
}
