import { PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { GlobalConfigForm } from './form'

export const dynamic = 'force-dynamic'

export default async function GlobalConfigPage() {
  const svc = createServiceClient()
  const { data: rows } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        order: (col: string, opt: { ascending: boolean }) => Promise<{
          data: Array<{ key: string; value: unknown; description: string | null }> | null
        }>
      }
    }
  })
    .from('global_config')
    .select('key, value, description')
    .order('key', { ascending: true })

  const items = rows ?? []

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Global' }]}
        title="Config Global"
        description="Rate limits, alertas, parâmetros TTS e outras chaves globais. Cada save dispara entrada em audit_log."
      />

      {items.length === 0 ? (
        <div className="content-card p-6 text-sm text-muted-foreground">
          Nenhuma config global. Migration deve ter falhado.
        </div>
      ) : (
        <GlobalConfigForm items={items} />
      )}
    </div>
  )
}
