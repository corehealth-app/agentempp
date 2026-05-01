import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { AgentConfigForm } from './form'

const STAGE_LABELS: Record<string, { label: string; description: string }> = {
  coleta_dados: {
    label: 'Coleta de Dados',
    description: 'Onboarding: 11 perguntas iniciais até definir o protocolo.',
  },
  recomposicao: {
    label: 'Recomposição Corporal',
    description: 'Protocolo de redução de gordura preservando massa magra.',
  },
  ganho_massa: {
    label: 'Ganho de Massa',
    description: 'Hipertrofia controlada com superávit calórico.',
  },
  manutencao: {
    label: 'Manutenção',
    description: 'Estabilidade após atingir meta.',
  },
  analista_diario: {
    label: 'Analista Diário (cron)',
    description:
      'Roda 1×/dia: lê histórico do dia, consolida daily_snapshots, atualiza progresso.',
  },
  engajamento: {
    label: 'Engajamento (cron)',
    description: 'Mensagens proativas ao longo do dia. 5 disparos.',
  },
}

const POPULAR_MODELS = [
  'x-ai/grok-4.1-fast',
  'anthropic/claude-3.7-sonnet:thinking',
  'anthropic/claude-3.5-sonnet',
  'anthropic/claude-haiku-4.5',
  'deepseek/deepseek-v3',
  'openai/gpt-4o',
  'openai/gpt-4o-mini',
  'google/gemini-2.0-flash-001',
  'meta-llama/llama-3.3-70b-instruct',
]

export default async function AgentsPage() {
  const supabase = createServiceClient()
  const { data: configs } = await supabase
    .from('agent_configs')
    .select('*')
    .eq('status', 'active')
    .order('stage')

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Sub-agentes</h1>
        <p className="text-muted-foreground">
          Configuração de modelo, temperatura e tokens por estágio. Cada mudança gera uma versão
          em <code>agent_configs_versions</code>.
        </p>
      </div>

      <div className="grid gap-4">
        {(configs ?? []).map((cfg) => (
          <Card key={cfg.id}>
            <CardHeader className="flex flex-row items-start justify-between space-y-0">
              <div className="space-y-1">
                <CardTitle className="text-lg">
                  {STAGE_LABELS[cfg.stage]?.label ?? cfg.stage}
                </CardTitle>
                <CardDescription>
                  {STAGE_LABELS[cfg.stage]?.description}
                </CardDescription>
              </div>
              <div className="flex flex-col items-end gap-1">
                <Badge variant="default">v{cfg.version}</Badge>
                <span className="text-xs text-muted-foreground">{cfg.name}</span>
              </div>
            </CardHeader>
            <CardContent>
              <AgentConfigForm
                id={cfg.id}
                stage={cfg.stage}
                model={cfg.model}
                temperature={Number(cfg.temperature)}
                maxTokens={cfg.max_tokens}
                waitSeconds={cfg.wait_seconds}
                modelOptions={POPULAR_MODELS}
              />
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
