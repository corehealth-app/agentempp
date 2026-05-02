import { ContentCard, PageHeader } from '@/components/page-header'
import { Button } from '@/components/ui/button'
import { createServiceClient } from '@/lib/supabase/server'
import { ChevronRight, Sparkles } from 'lucide-react'
import Link from 'next/link'

const TIPO_LABELS: Record<string, string> = {
  regras_gerais: 'Regras Gerais',
  coleta_dados: 'Coleta de Dados',
  recomposicao: 'Recomposição',
  ganho_massa: 'Ganho de Massa',
  manutencao: 'Manutenção',
}

const TIPO_DOTS: Record<string, string> = {
  regras_gerais: 'bg-ink-700',
  coleta_dados: 'bg-moss-500',
  recomposicao: 'bg-moss-700',
  ganho_massa: 'bg-bronze',
  manutencao: 'bg-moss-400',
}

export default async function PromptsPage({
  searchParams,
}: {
  searchParams: Promise<{ tipo?: string }>
}) {
  const params = await searchParams
  const supabase = createServiceClient()
  let query = supabase
    .from('agent_rules')
    .select('id, topic, slug, tipo, status, token_estimate, updated_at, display_order')
    .eq('status', 'active')
    .order('tipo')
    .order('display_order')

  if (params.tipo) query = query.eq('tipo', params.tipo as 'regras_gerais')

  const { data: rules } = await query

  const { data: counts } = await supabase
    .from('agent_rules')
    .select('tipo')
    .eq('status', 'active')
  const byTipo = (counts ?? []).reduce<Record<string, number>>((acc, r) => {
    acc[r.tipo] = (acc[r.tipo] ?? 0) + 1
    return acc
  }, {})

  const totalRules = Object.values(byTipo).reduce((a, b) => a + b, 0)

  const grouped = !params.tipo
    ? Object.entries(
        (rules ?? []).reduce<Record<string, typeof rules>>((acc, r) => {
          if (!acc[r.tipo]) acc[r.tipo] = []
          acc[r.tipo]!.push(r)
          return acc
        }, {}),
      )
    : null

  return (
    <div className="flex flex-col h-full">
      <div className="shrink-0 mb-3">
        <PageHeader
          compact
          breadcrumbs={[{ label: 'Persona' }, { label: 'Regras' }]}
          title="Persona do agente"
          description={`${totalRules} regras compõem o comportamento. Cada edição cria versão imutável.`}
          actions={
            <Link href="/prompts/playground">
              <Button size="sm">
                <Sparkles className="h-4 w-4 mr-2" />
                Playground
              </Button>
            </Link>
          }
        />
      </div>

      <div className="shrink-0 glass-card p-3 mb-3 flex flex-wrap gap-2">
        <Link
          href="/prompts"
          className={`text-xs font-medium px-3 py-1.5 rounded-md border transition-colors ${
            !params.tipo
              ? 'bg-foreground text-background border-foreground'
              : 'bg-card text-foreground/80 border-border hover:bg-muted'
          }`}
        >
          Todas · {totalRules}
        </Link>
        {Object.entries(byTipo)
          .sort()
          .map(([tipo, n]) => (
            <Link
              key={tipo}
              href={`/prompts?tipo=${tipo}`}
              className={`text-xs font-medium px-3 py-1.5 rounded-md border transition-colors flex items-center gap-2 ${
                params.tipo === tipo
                  ? 'bg-foreground text-background border-foreground'
                  : 'bg-card text-foreground/80 border-border hover:bg-muted'
              }`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${TIPO_DOTS[tipo] ?? 'bg-foreground'}`}
              />
              {TIPO_LABELS[tipo] ?? tipo} · {n}
            </Link>
          ))}
      </div>

      {grouped ? (
        <div className="flex-1 min-h-0 overflow-y-auto space-y-4 pr-1 -mr-1">
          {grouped.map(([tipo, list]) => (
            <ContentCard
              key={tipo}
              title={TIPO_LABELS[tipo] ?? tipo}
              description={`${list?.length ?? 0} regras ativas`}
              bodyClassName="p-0"
            >
              <ul className="divide-y divide-border">
                {(list ?? []).map((r, idx) => (
                  <RuleRow key={r.id} rule={r} idx={idx} />
                ))}
              </ul>
            </ContentCard>
          ))}
        </div>
      ) : (
        <ContentCard className="flex-1 min-h-0 flex flex-col overflow-hidden !p-0">
          <ul className="flex-1 overflow-y-auto divide-y divide-border">
            {(rules ?? []).map((r, idx) => (
              <RuleRow key={r.id} rule={r} idx={idx} />
            ))}
          </ul>
        </ContentCard>
      )}
    </div>
  )
}

function RuleRow({
  rule,
  idx,
}: {
  rule: { id: string; topic: string; slug: string; tipo: string; token_estimate: number | null }
  idx: number
}) {
  return (
    <li>
      <Link
        href={`/prompts/${rule.id}`}
        className="group flex items-center gap-4 px-5 py-3.5 hover:bg-muted/50 transition-colors"
      >
        <span className="font-mono text-xs text-muted-foreground tabular-nums shrink-0 w-6">
          {String(idx + 1).padStart(2, '0')}
        </span>
        <div className="flex-1 min-w-0">
          <div className="font-medium text-foreground truncate">{rule.topic}</div>
          <div className="text-xs font-mono text-muted-foreground mt-0.5 truncate">
            {rule.slug} · ~{rule.token_estimate ?? 0} tokens
          </div>
        </div>
        <ChevronRight className="h-4 w-4 text-muted-foreground group-hover:text-foreground group-hover:translate-x-0.5 transition-all" />
      </Link>
    </li>
  )
}
