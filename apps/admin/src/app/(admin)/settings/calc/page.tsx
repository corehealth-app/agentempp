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
        description="Toda fórmula determinística do MPP — BMR, TDEE, proteína, IMC, %BF, sono mínimo, blocos 7700, XP, badges. Mudanças aqui afetam novos cálculos imediatamente."
      />

      <div className="glass-card border-l-4 border-l-blue-500/60 p-4 text-xs space-y-1">
        <p className="font-medium text-blue-700 uppercase tracking-widest text-[10px]">
          📘 Fonte de verdade: doc MPP no Notion
        </p>
        <p className="text-muted-foreground">
          Todos os valores aqui seguem a documentação oficial do método MPP (Notion). As fórmulas
          incluem BMR Mifflin-St Jeor / Katch-McArdle, recomp = BMR × 1.2 − déficit, ganho = BMR ×
          atividade × 1.05, escada IMC [30, 25, 23, 22, 21], escada BF, levels (8 níveis), 17
          badges, fatores de proteína em cascata por hunger + treino, e critérios de elegibilidade
          (treino ≥ 3, sono ≥ 6h30, alimentação estruturada). Antes de alterar, verifique a doc
          original.
        </p>
      </div>

      <div className="glass-card border-l-4 border-l-amber-500/60 p-4 text-xs space-y-1">
        <p className="font-medium text-amber-700 uppercase tracking-widest text-[10px]">
          ⚠️ Alterações têm impacto clínico
        </p>
        <p className="text-muted-foreground">
          Mudanças nessas constantes afetam recomendações nutricionais e de treino de TODOS os
          pacientes em tempo real (sem deploy). Os valores padrão seguem literatura científica.
          Toda mudança é registrada em{' '}
          <code className="font-mono bg-muted px-1 py-0.5 rounded">audit_log</code> e usa cache de
          60s — alteração reflete em até 1 minuto.
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
