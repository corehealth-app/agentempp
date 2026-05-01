import { ContentCard, PageHeader } from '@/components/page-header'
import { PlaygroundForm } from './form'

export default function PlaygroundPage() {
  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Persona', href: '/prompts' }, { label: 'Playground' }]}
        title="Playground"
        description="Teste o agente em tempo real. Cada mensagem passa pela mesma pipeline que o WhatsApp usaria — incluindo regras, tools e cálculo TACO."
      />
      <ContentCard className="overflow-visible">
        <PlaygroundForm />
      </ContentCard>
    </div>
  )
}
