import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { CreditCard, ExternalLink } from 'lucide-react'

export default async function BillingPage() {
  const svc = createServiceClient()

  const [{ data: subs }, { data: events }] = await Promise.all([
    svc
      .from('subscriptions')
      .select('id, user_id, plan, status, current_period_end, trial_ends_at, created_at')
      .order('created_at', { ascending: false })
      .limit(50),
    svc
      .from('subscription_events')
      .select('id, event_type, amount_cents, currency, created_at, user_id')
      .order('created_at', { ascending: false })
      .limit(20),
  ])

  const counts = (subs ?? []).reduce<Record<string, number>>((acc, s) => {
    acc[s.status] = (acc[s.status] ?? 0) + 1
    return acc
  }, {})

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Billing' }]}
        title="Billing"
        description="Assinaturas Stripe e eventos de cobrança."
      />

      {/* Stats */}
      <div className="grid gap-4 md:grid-cols-4">
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Total
          </div>
          <div className="font-display text-3xl tabular-nums">{subs?.length ?? 0}</div>
          <div className="mt-1 text-xs font-mono text-muted-foreground">assinaturas</div>
        </div>
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Active
          </div>
          <div className="font-display text-3xl tabular-nums text-moss-700">
            {counts.active ?? 0}
          </div>
        </div>
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Trial
          </div>
          <div className="font-display text-3xl tabular-nums text-bronze">
            {counts.trial ?? 0}
          </div>
        </div>
        <div className="glass-card p-5">
          <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-3">
            Past due / canceled
          </div>
          <div className="font-display text-3xl tabular-nums text-destructive">
            {(counts.past_due ?? 0) + (counts.canceled ?? 0) + (counts.expired ?? 0)}
          </div>
        </div>
      </div>

      {/* Setup hint */}
      {(!subs || subs.length === 0) && (
        <div className="glass-card border-l-4 border-l-bronze p-4 text-sm text-foreground/80 leading-relaxed">
          <strong className="text-foreground">Stripe não configurado ou sem dados ainda.</strong>{' '}
          Webhook em <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">/functions/v1/webhook-stripe</code>.
          Adicione <code className="font-mono text-xs">STRIPE_SECRET_KEY</code> e{' '}
          <code className="font-mono text-xs">STRIPE_WEBHOOK_SECRET</code> em{' '}
          <code className="font-mono text-xs">/settings/api-keys</code> e configure o endpoint no
          dashboard Stripe.
        </div>
      )}

      {/* Subscriptions */}
      <ContentCard title="Assinaturas" description="Últimas 50">
        {!subs || subs.length === 0 ? (
          <p className="text-sm text-muted-foreground py-2">Sem assinaturas ainda.</p>
        ) : (
          <ul className="divide-y divide-border -mx-5 -my-5">
            {subs.map((s) => (
              <li
                key={s.id}
                className="flex items-center gap-4 px-5 py-3.5 hover:bg-muted/30 transition-colors"
              >
                <CreditCard className="h-4 w-4 text-muted-foreground shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="text-xs font-mono text-muted-foreground">{s.user_id.slice(0, 8)}…</div>
                  <div className="text-sm flex items-center gap-2 flex-wrap mt-0.5">
                    <span className="font-medium uppercase text-xs tracking-widest font-mono bg-muted px-2 py-0.5 rounded">
                      {s.plan}
                    </span>
                    <span
                      className={`inline-flex text-[10px] uppercase tracking-widest font-mono px-2 py-0.5 rounded-full ${
                        s.status === 'active'
                          ? 'bg-moss-100 text-moss-700'
                          : s.status === 'trial'
                            ? 'bg-bronze/15 text-bronze'
                            : 'bg-destructive/15 text-destructive'
                      }`}
                    >
                      {s.status}
                    </span>
                    {s.current_period_end && (
                      <span className="text-xs text-muted-foreground font-mono">
                        até {formatDateTime(s.current_period_end)}
                      </span>
                    )}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </ContentCard>

      {/* Events */}
      <ContentCard title="Eventos Stripe" description="Últimos 20 eventos do webhook">
        {!events || events.length === 0 ? (
          <p className="text-sm text-muted-foreground py-2">Sem eventos.</p>
        ) : (
          <ul className="divide-y divide-border -mx-5 -my-5">
            {events.map((e) => (
              <li key={e.id} className="px-5 py-3 text-sm flex items-center gap-3">
                <ExternalLink className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
                <span className="font-mono text-xs bg-muted px-2 py-0.5 rounded">
                  {e.event_type}
                </span>
                {e.amount_cents != null && (
                  <span className="font-mono text-xs">
                    {(e.amount_cents / 100).toLocaleString('pt-BR', {
                      style: 'currency',
                      currency: e.currency ?? 'BRL',
                    })}
                  </span>
                )}
                <span className="text-xs font-mono text-muted-foreground ml-auto">
                  {formatDateTime(e.created_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </ContentCard>
    </div>
  )
}
