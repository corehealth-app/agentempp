import { PageHeader } from '@/components/page-header'
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

const TIPO_ACCENTS: Record<string, string> = {
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

  // Agrupa por tipo se sem filtro
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
    <div className="px-10 py-12 max-w-[1100px]">
      <PageHeader
        chapter="04"
        eyebrow="Persona · regras de comportamento"
        title="Persona do agente"
        description={`${totalRules} regras compõem o comportamento. Cada edição cria uma versão imutável em agent_rules_versions.`}
        actions={
          <Link href="/prompts/playground">
            <Button className="bg-ink-900 hover:bg-ink-800 text-cream-100 rounded-sm">
              <Sparkles className="h-4 w-4 mr-2" />
              Playground
            </Button>
          </Link>
        }
      />

      {/* Filter pills */}
      <div className="mb-8 flex flex-wrap gap-2">
        <Link
          href="/prompts"
          className={`text-xs font-mono uppercase tracking-wider px-3 py-1.5 rounded-sm border transition-colors ${
            !params.tipo
              ? 'bg-ink-900 text-cream-100 border-ink-900'
              : 'bg-cream-50 text-ink-700 border-border hover:bg-cream-200'
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
              className={`text-xs font-mono uppercase tracking-wider px-3 py-1.5 rounded-sm border transition-colors flex items-center gap-2 ${
                params.tipo === tipo
                  ? 'bg-ink-900 text-cream-100 border-ink-900'
                  : 'bg-cream-50 text-ink-700 border-border hover:bg-cream-200'
              }`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${TIPO_ACCENTS[tipo] ?? 'bg-ink-500'}`}
              />
              {TIPO_LABELS[tipo] ?? tipo} · {n}
            </Link>
          ))}
      </div>

      {/* Lista */}
      {grouped ? (
        <div className="space-y-10">
          {grouped.map(([tipo, list]) => (
            <section key={tipo}>
              <div className="flex items-center gap-3 mb-4 px-1">
                <span
                  className={`h-2 w-2 rounded-full ${TIPO_ACCENTS[tipo] ?? 'bg-ink-500'}`}
                />
                <h2 className="font-display text-xl text-ink-900 tracking-tight">
                  {TIPO_LABELS[tipo] ?? tipo}
                </h2>
                <span className="font-mono text-xs text-ink-500 tabular-nums">
                  {list?.length ?? 0} regras
                </span>
              </div>
              <ul className="border border-border bg-cream-50 rounded-sm divide-y divide-border">
                {(list ?? []).map((r, idx) => (
                  <RuleRow key={r.id} rule={r} idx={idx} />
                ))}
              </ul>
            </section>
          ))}
        </div>
      ) : (
        <ul className="border border-border bg-cream-50 rounded-sm divide-y divide-border">
          {(rules ?? []).map((r, idx) => (
            <RuleRow key={r.id} rule={r} idx={idx} />
          ))}
        </ul>
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
        className="group flex items-center gap-4 px-5 py-4 hover:bg-cream-200/60 transition-colors"
      >
        <span className="font-mono text-xs text-ink-400 tabular-nums shrink-0 w-6">
          {String(idx + 1).padStart(2, '0')}
        </span>
        <div className="flex-1 min-w-0">
          <div className="font-medium text-ink-900 truncate">{rule.topic}</div>
          <div className="text-xs font-mono text-ink-500 mt-0.5 truncate">
            {rule.slug} · ~{rule.token_estimate ?? 0} tokens
          </div>
        </div>
        <ChevronRight className="h-4 w-4 text-ink-400 group-hover:text-ink-700 group-hover:translate-x-0.5 transition-all" />
      </Link>
    </li>
  )
}
