import { AdminAccessDenied } from '@/components/admin-access-denied'
import { PageHeader } from '@/components/page-header'
import { guardAdminPage } from '@/lib/admin-page-guard'
import { createServiceClient } from '@/lib/supabase/server'
import { GlobalConfigForm } from './form'

export const dynamic = 'force-dynamic'

export default async function GlobalConfigPage() {
  const access = await guardAdminPage('/settings/global')
  if (!access.ok) return <AdminAccessDenied access={access} />

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

  // Exclui prefixo 'calc.*' — tem página dedicada (/settings/calc) com UI
  // específica por tipo (BMR record, badges JSON-array, etc). Mostrar aqui
  // duplicaria com editor genérico inferior.
  const items = (rows ?? []).filter((r) => !r.key.startsWith('calc.'))

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Global' }]}
        title="Config Global"
        description={
          <>
            Configurações gerais do motor: visão (leitura de fotos), validador numérico, alertas e
            atenção. Os grupos do canal de WhatsApp, encerrado, aparecem rotulados como legado.{' '}
            <strong>Constantes de cálculo (BMR, IMC, badges, XP)</strong> ficam em{' '}
            <a href="/settings/calc" className="underline hover:text-foreground">
              /settings/calc
            </a>{' '}
            (UI dedicada).
          </>
        }
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
