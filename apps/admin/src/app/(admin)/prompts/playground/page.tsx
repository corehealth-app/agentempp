import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { PlaygroundForm } from './form'

export default function PlaygroundPage() {
  return (
    <div className="space-y-6 p-6 max-w-5xl">
      <div>
        <h1 className="text-3xl font-bold">Playground</h1>
        <p className="text-muted-foreground">
          Teste o agente em tempo real. Cada mensagem aqui passa pela mesma pipeline que o
          WhatsApp usaria — incluindo regras, tools e cálculo TACO.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Conversa de teste</CardTitle>
          <CardDescription>
            Use um número de WhatsApp simulado. Pode usar /reset para apagar o usuário e começar
            de novo.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <PlaygroundForm />
        </CardContent>
      </Card>
    </div>
  )
}
