import { PageHeader } from '@/components/page-header'
import { PlaygroundForm } from './form'

export default function PlaygroundPage() {
  return (
    <div className="px-10 py-12 max-w-[1100px]">
      <PageHeader
        chapter="05"
        eyebrow="Persona · teste em tempo real"
        title="Playground"
        description="Teste o agente em tempo real. Cada mensagem passa pela mesma pipeline que o WhatsApp usaria — incluindo regras, tools e cálculo TACO."
      />
      <PlaygroundForm />
    </div>
  )
}
