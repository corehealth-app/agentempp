/**
 * MINIMAL DEBUG VERSION — vai voltar pra completa quando achar o bug.
 */
import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { notFound } from 'next/navigation'

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const svc = createServiceClient()

  const { data: user, error: e1 } = await svc
    .from('users')
    .select('*')
    .eq('id', id)
    .maybeSingle()

  if (e1) throw new Error(`fetch user: ${e1.message}`)
  if (!user) notFound()

  // Tenta cada fetch isoladamente e captura qual falha
  const debug: Record<string, string> = {}

  try {
    const r = await svc.from('user_profiles').select('*').eq('user_id', id).maybeSingle()
    debug.profile = r.error ? `ERR: ${r.error.message}` : 'ok'
  } catch (e) {
    debug.profile = `THROW: ${e instanceof Error ? e.message : String(e)}`
  }
  try {
    const r = await svc.from('user_progress').select('*').eq('user_id', id).maybeSingle()
    debug.progress = r.error ? `ERR: ${r.error.message}` : 'ok'
  } catch (e) {
    debug.progress = `THROW: ${e instanceof Error ? e.message : String(e)}`
  }
  try {
    const r = await svc
      .from('messages')
      .select('id, direction, content, content_type, agent_stage, model_used, cost_usd, created_at')
      .eq('user_id', id)
      .order('created_at', { ascending: false })
      .limit(50)
    debug.messages = r.error ? `ERR: ${r.error.message}` : `ok (${r.data?.length})`
  } catch (e) {
    debug.messages = `THROW: ${e instanceof Error ? e.message : String(e)}`
  }
  try {
    const r = await svc
      .from('daily_snapshots')
      .select('*')
      .eq('user_id', id)
      .order('date', { ascending: false })
      .limit(14)
    debug.snapshots = r.error ? `ERR: ${r.error.message}` : `ok (${r.data?.length})`
  } catch (e) {
    debug.snapshots = `THROW: ${e instanceof Error ? e.message : String(e)}`
  }
  try {
    const r = await svc
      .from('subscriptions')
      .select('id, plan, status, current_period_end, trial_ends_at, cancel_at_period_end')
      .eq('user_id', id)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle()
    debug.subscription = r.error ? `ERR: ${r.error.message}` : r.data ? 'ok (sub)' : 'ok (no sub)'
  } catch (e) {
    debug.subscription = `THROW: ${e instanceof Error ? e.message : String(e)}`
  }

  const userTyped = user as {
    id: string
    name: string | null
    wpp: string
    country?: string | null
    country_confirmed?: boolean | null
  }

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[
          { label: 'Operação' },
          { label: 'Usuários', href: '/users' },
          { label: userTyped.name ?? userTyped.wpp },
        ]}
        title={userTyped.name ?? userTyped.wpp}
        description={`+${userTyped.wpp} · ${userTyped.id.slice(0, 8)}…`}
      />

      <ContentCard title="DEBUG: page minimal" description="Diagnóstico de qual fetch está falhando">
        <pre className="text-xs font-mono whitespace-pre-wrap bg-muted p-3 rounded">
          {JSON.stringify(debug, null, 2)}
        </pre>
        <p className="text-xs text-muted-foreground mt-3">
          user.id = {userTyped.id}
          {' · '}country = {userTyped.country ?? 'null'}
          {' · '}confirmed = {String(userTyped.country_confirmed)}
        </p>
      </ContentCard>
    </div>
  )
}
