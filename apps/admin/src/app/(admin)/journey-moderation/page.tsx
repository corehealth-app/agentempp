import { AdminAccessDenied } from '@/components/admin-access-denied'
import { PageHeader } from '@/components/page-header'
import { guardAdminPage } from '@/lib/admin-page-guard'
import { journeyModerationAction } from './actions'
import { ConnectedModerationPanel } from './connected-panel'

export const dynamic = 'force-dynamic'
export default async function JourneyModerationPage() {
  const access = await guardAdminPage('/journey-moderation')
  if (!access.ok) return <AdminAccessDenied access={access} />
  const result = await journeyModerationAction({
    type: 'queue',
    context: null,
    query: { limit: 20, cursor: null },
  })
  return (
    <div className="space-y-6">
      <PageHeader
        title="Moderação da Jornada"
        description="Denúncias e participação pública, com decisões registradas e acesso operacional restrito."
      />
      {result.ok && result.type === 'queue' ? (
        <ConnectedModerationPanel initial={result} action={journeyModerationAction} />
      ) : (
        <section className="glass-card p-6" role="status">
          <h2 className="font-semibold">Moderação em preparação ou indisponível</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            Nenhuma ação foi enviada. Reabra a página depois de conferir seu acesso e a
            disponibilidade da Jornada social.
          </p>
        </section>
      )}
    </div>
  )
}
