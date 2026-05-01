import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { notFound } from 'next/navigation'
import { RuleEditor } from './editor'

const TIPO_LABELS: Record<string, string> = {
  regras_gerais: 'Regras Gerais',
  coleta_dados: 'Coleta de Dados',
  recomposicao: 'Recomposição',
  ganho_massa: 'Ganho de Massa',
  manutencao: 'Manutenção',
}

export default async function RuleEditPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = createServiceClient()
  const { data: rule } = await supabase
    .from('agent_rules')
    .select('*')
    .eq('id', id)
    .maybeSingle()

  if (!rule) notFound()

  const { data: versions } = await supabase
    .from('agent_rules_versions')
    .select('version_num, status, change_reason, changed_at')
    .eq('rule_id', id)
    .order('version_num', { ascending: false })
    .limit(20)

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[
          { label: 'Persona', href: '/prompts' },
          { label: TIPO_LABELS[rule.tipo] ?? rule.tipo, href: `/prompts?tipo=${rule.tipo}` },
          { label: rule.topic },
        ]}
        title={rule.topic}
        description={`${rule.slug} · ~${rule.token_estimate ?? 0} tokens · atualizado em ${formatDateTime(rule.updated_at)}`}
      />

      <RuleEditor
        id={rule.id}
        topic={rule.topic}
        tipo={rule.tipo}
        content={rule.content}
        status={rule.status}
        displayOrder={rule.display_order}
      />

      <ContentCard
        title="Histórico de versões"
        description="Últimas 20 alterações registradas pelo trigger imutável"
      >
        {!versions || versions.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sem histórico ainda.</p>
        ) : (
          <ul className="divide-y divide-border -mx-5 -my-5">
            {versions.map((v) => (
              <li
                key={v.version_num}
                className="flex items-center justify-between gap-3 px-5 py-3 text-sm hover:bg-muted/30 transition-colors"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <code className="font-mono text-xs bg-muted text-foreground px-2 py-0.5 rounded shrink-0">
                    v{v.version_num}
                  </code>
                  <span
                    className={`text-[10px] uppercase tracking-widest font-mono px-2 py-0.5 rounded-full shrink-0 ${
                      v.status === 'active'
                        ? 'bg-moss-100 text-moss-700'
                        : v.status === 'draft'
                          ? 'bg-cream-300 text-foreground/80'
                          : 'bg-muted text-muted-foreground'
                    }`}
                  >
                    {v.status}
                  </span>
                  <span className="text-foreground/80 truncate">
                    {v.change_reason ?? <span className="text-muted-foreground italic">sem motivo</span>}
                  </span>
                </div>
                <span className="text-xs font-mono text-muted-foreground shrink-0">
                  {formatDateTime(v.changed_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </ContentCard>
    </div>
  )
}
