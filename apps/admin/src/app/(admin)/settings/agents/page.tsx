import { ContentCard, PageHeader } from '@/components/page-header'
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
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Persona' }, { label: 'Sub-agentes' }]}
        title="Sub-agentes"
        description="Configuração de modelo, temperatura e tokens por estágio. Cada mudança gera uma versão em agent_configs_versions."
      />

      <div className="grid gap-4">
        {(configs ?? []).map((cfg) => (
          <ContentCard
            key={cfg.id}
            title={STAGE_LABELS[cfg.stage]?.label ?? cfg.stage}
            description={STAGE_LABELS[cfg.stage]?.description}
            actions={
              <div className="flex flex-col items-end gap-1">
                <span className="inline-flex items-center text-[10px] uppercase tracking-widest font-mono px-2 py-1 rounded-full bg-moss-100 text-moss-700">
                  v{cfg.version}
                </span>
                <span className="text-[10px] text-muted-foreground font-mono">{cfg.name}</span>
              </div>
            }
          >
            <AgentConfigForm
              id={cfg.id}
              stage={cfg.stage}
              model={cfg.model}
              temperature={Number(cfg.temperature)}
              maxTokens={cfg.max_tokens}
              waitSeconds={cfg.wait_seconds}
              modelOptions={POPULAR_MODELS}
              {...(() => {
                const c = cfg as unknown as {
                  top_p?: number | null
                  frequency_penalty?: number
                  presence_penalty?: number
                  max_tool_iterations?: number
                  buffer_debounce_ms?: number
                  llm_timeout_ms?: number
                  vision_timeout_ms?: number
                  stt_timeout_ms?: number
                  allowed_tools?: string[] | null
                  helicone_cache?: boolean
                  streaming?: boolean
                }
                return {
                  top_p: c.top_p ?? null,
                  frequency_penalty: Number(c.frequency_penalty ?? 0),
                  presence_penalty: Number(c.presence_penalty ?? 0),
                  maxToolIterations: c.max_tool_iterations ?? 5,
                  bufferDebounceMs: c.buffer_debounce_ms ?? 8000,
                  llmTimeoutMs: c.llm_timeout_ms ?? 90000,
                  visionTimeoutMs: c.vision_timeout_ms ?? 60000,
                  sttTimeoutMs: c.stt_timeout_ms ?? 30000,
                  allowedTools: c.allowed_tools ?? null,
                  heliconeCache: c.helicone_cache ?? false,
                  streaming: c.streaming ?? false,
                }
              })()}
            />
          </ContentCard>
        ))}
      </div>
    </div>
  )
}
