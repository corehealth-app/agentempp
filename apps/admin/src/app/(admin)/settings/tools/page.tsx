import { PageHeader } from '@/components/page-header'
import { ALL_TOOLS } from '@mpp/agent'
import { createServiceClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'

const STAGE_LABELS: Record<string, string> = {
  coleta_dados: 'Coleta',
  recomposicao: 'Recomp',
  ganho_massa: 'Ganho',
  manutencao: 'Manut.',
  analista_diario: 'Analista',
  engajamento: 'Engaj.',
}

export default async function ToolsPage() {
  const svc = createServiceClient()

  // Carrega allowed_tools por stage pra mostrar onde cada tool roda
  const { data: configs } = await svc
    .from('agent_configs')
    .select('stage, allowed_tools')
    .eq('status', 'active')

  // Map: tool_name → stages onde está habilitada
  const toolStages: Record<string, string[]> = {}
  for (const t of ALL_TOOLS) toolStages[t.name] = []
  for (const cfg of configs ?? []) {
    const allowed = cfg.allowed_tools as string[] | null
    if (!allowed || allowed.length === 0) {
      // null = todas
      for (const t of ALL_TOOLS) toolStages[t.name]!.push(cfg.stage)
    } else {
      for (const name of allowed) {
        if (toolStages[name]) toolStages[name]!.push(cfg.stage)
      }
    }
  }

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Persona' }, { label: 'Tools' }]}
        title="Tools (capabilities do agente)"
        description={
          <>
            Todas as tools que o LLM pode chamar. Description = instrução de QUANDO usar (vai pro
            modelo). Editar uma tool exige código + deploy. Pra ligar/desligar uma tool num stage,
            use{' '}
            <a href="/settings/agents" className="underline">
              /settings/agents
            </a>{' '}
            (allowed_tools).
          </>
        }
      />

      <div className="space-y-3">
        {ALL_TOOLS.map((tool) => (
          <div key={tool.name} className="content-card p-4">
            <div className="flex items-start justify-between gap-4 mb-2">
              <div>
                <h3 className="font-mono text-sm font-bold">{tool.name}</h3>
                <div className="flex flex-wrap gap-1 mt-1.5">
                  {(toolStages[tool.name] ?? []).length === 0 ? (
                    <span className="text-[10px] text-muted-foreground">
                      ⚠️ não habilitada em nenhum stage
                    </span>
                  ) : (
                    (toolStages[tool.name] ?? []).map((stage) => (
                      <span
                        key={stage}
                        className="text-[10px] uppercase tracking-wide font-mono px-2 py-0.5 rounded bg-moss-100 text-moss-700"
                      >
                        {STAGE_LABELS[stage] ?? stage}
                      </span>
                    ))
                  )}
                </div>
              </div>
              <span className="text-[10px] text-muted-foreground font-mono shrink-0">
                {Object.keys(getZodShape(tool.parameters)).length} parâmetro(s)
              </span>
            </div>

            <p className="text-xs text-foreground/80 leading-relaxed whitespace-pre-wrap">
              {tool.description}
            </p>

            <details className="mt-3">
              <summary className="text-[10px] font-mono text-muted-foreground cursor-pointer hover:text-foreground">
                Parâmetros JSON Schema
              </summary>
              <pre className="mt-2 text-[10px] font-mono bg-muted/40 rounded p-2 overflow-x-auto">
                {JSON.stringify(getZodShape(tool.parameters), null, 2)}
              </pre>
            </details>
          </div>
        ))}
      </div>
    </div>
  )
}

// Helper: extrai shape básico do Zod schema pra exibição (sem trazer biblioteca pesada)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getZodShape(schema: any): Record<string, string> {
  try {
    const shape = schema._def?.shape?.() ?? schema.shape ?? {}
    const out: Record<string, string> = {}
    for (const [key, value] of Object.entries(shape)) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const v = value as any
      const inner = v._def?.innerType?._def ?? v._def
      const typeName = inner?.typeName ?? 'unknown'
      const optional = v.isOptional?.() ? '?' : ''
      const desc = v.description ? ` — ${v.description.slice(0, 80)}` : ''
      out[`${key}${optional}`] = `${typeName.replace('Zod', '')}${desc}`
    }
    return out
  } catch {
    return {}
  }
}
