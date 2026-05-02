import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { CalcConfigForm } from './form'

export const dynamic = 'force-dynamic'

interface ConfigItem {
  key: string
  value: unknown
  description: string | null
}

export default async function CalcConfigPage() {
  const svc = createServiceClient()
  const { data: rows } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        like: (col: string, val: string) => {
          order: (col: string) => Promise<{ data: ConfigItem[] | null }>
        }
      }
    }
  })
    .from('global_config')
    .select('key, value, description')
    .like('key', 'calc.%')
    .order('key')

  const items = rows ?? []

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Cálculos' }]}
        title="Constantes de cálculo"
        description="Toda fórmula determinística do MPP — BMR, TDEE, proteína, IMC, %BF, blocos 7700, XP, badges. Mudanças aqui afetam novos cálculos imediatamente."
      />

      <div className="glass-card border-l-4 border-l-amber-500/60 p-4 text-xs space-y-1">
        <p className="font-medium text-amber-700 uppercase tracking-widest text-[10px]">
          ⚠️ Alterações têm impacto clínico
        </p>
        <p className="text-muted-foreground">
          Mudanças nessas constantes afetam recomendações nutricionais e de treino. Os valores
          padrão seguem literatura científica (Mifflin-St Jeor, Katch-McArdle). Toda mudança vai
          pro <code className="font-mono bg-muted px-1 py-0.5 rounded">audit_log</code>.
        </p>
      </div>

      {items.length === 0 ? (
        <ContentCard title="Sem dados">
          <p className="text-sm text-muted-foreground">
            Nenhuma constante <code>calc.*</code> encontrada em <code>global_config</code>.
            Aplique a migration <code>20260502213000_calc_config.sql</code>.
          </p>
        </ContentCard>
      ) : (
        <CalcConfigForm items={items} />
      )}
    </div>
  )
}
