import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { createServiceClient } from '@/lib/supabase/server'
import { Edit3, FileText } from 'lucide-react'
import Link from 'next/link'

const TIPO_LABELS: Record<string, string> = {
  regras_gerais: 'Regras Gerais',
  coleta_dados: 'Coleta de Dados',
  recomposicao: 'Recomposição',
  ganho_massa: 'Ganho de Massa',
  manutencao: 'Manutenção',
}

const TIPO_COLORS: Record<string, string> = {
  regras_gerais: 'bg-slate-500/10 text-slate-600 dark:text-slate-400',
  coleta_dados: 'bg-blue-500/10 text-blue-600 dark:text-blue-400',
  recomposicao: 'bg-purple-500/10 text-purple-600 dark:text-purple-400',
  ganho_massa: 'bg-orange-500/10 text-orange-600 dark:text-orange-400',
  manutencao: 'bg-green-500/10 text-green-600 dark:text-green-400',
}

export default async function PromptsPage({
  searchParams,
}: {
  searchParams: Promise<{ tipo?: string; q?: string }>
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
  if (params.q) query = query.ilike('topic', `%${params.q}%`)

  const { data: rules } = await query

  // Conta por tipo
  const { data: counts } = await supabase
    .from('agent_rules')
    .select('tipo')
    .eq('status', 'active')

  const byTipo = (counts ?? []).reduce<Record<string, number>>((acc, r) => {
    acc[r.tipo] = (acc[r.tipo] ?? 0) + 1
    return acc
  }, {})

  return (
    <div className="space-y-6 p-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-3xl font-bold">Persona / Regras do Agente</h1>
          <p className="text-muted-foreground">
            {rules?.length ?? 0} regras compõem o comportamento do agente. Edição cria versão
            imutável em <code>agent_rules_versions</code>.
          </p>
        </div>
        <Link href="/prompts/playground">
          <Button>
            <FileText className="h-4 w-4 mr-1" />
            Playground
          </Button>
        </Link>
      </div>

      {/* Filtros */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Filtrar por tipo</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          <Link href="/prompts">
            <Badge variant={!params.tipo ? 'default' : 'outline'} className="cursor-pointer">
              Todas ({Object.values(byTipo).reduce((a, b) => a + b, 0)})
            </Badge>
          </Link>
          {Object.entries(byTipo)
            .sort()
            .map(([tipo, n]) => (
              <Link key={tipo} href={`/prompts?tipo=${tipo}`}>
                <Badge
                  variant={params.tipo === tipo ? 'default' : 'outline'}
                  className="cursor-pointer"
                >
                  {TIPO_LABELS[tipo] ?? tipo} ({n})
                </Badge>
              </Link>
            ))}
        </CardContent>
      </Card>

      {/* Lista */}
      <Card>
        <CardHeader>
          <CardTitle>Regras ativas</CardTitle>
          <CardDescription>Clique em uma regra para editar</CardDescription>
        </CardHeader>
        <CardContent>
          <ul className="divide-y">
            {(rules ?? []).map((r) => (
              <li key={r.id}>
                <Link
                  href={`/prompts/${r.id}`}
                  className="flex items-center justify-between gap-4 py-3 hover:bg-muted/50 px-2 rounded transition"
                >
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 mb-0.5">
                      <span
                        className={`text-xs px-2 py-0.5 rounded ${TIPO_COLORS[r.tipo] ?? ''}`}
                      >
                        {TIPO_LABELS[r.tipo] ?? r.tipo}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        ~{r.token_estimate ?? 0} tokens
                      </span>
                    </div>
                    <div className="font-medium truncate">{r.topic}</div>
                    <div className="text-xs text-muted-foreground truncate">{r.slug}</div>
                  </div>
                  <Edit3 className="h-4 w-4 text-muted-foreground shrink-0" />
                </Link>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}
