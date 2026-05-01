import { CreditCard, TrendingDown, TrendingUp, Users } from 'lucide-react'
import { ContentCard, PageHeader } from '@/components/page-header'
import { KpiCard } from '@/components/kpi-card'
import { createServiceClient } from '@/lib/supabase/server'
import { formatNumber } from '@/lib/utils'

interface MrrRow {
  active_subs: number
  mrr_brl: number | null
  new_30d: number
  churned_30d: number
  churn_rate_30d: number | null
}

interface SubEvent {
  id: string
  user_id: string | null
  event_type: string
  amount_cents: number | null
  currency: string
  created_at: string
}

interface Subscription {
  id: string
  user_id: string
  plan: string
  status: string
  current_period_start: string | null
  current_period_end: string | null
  cancel_at_period_end: boolean
  created_at: string
}

export default async function ReceitaPage() {
  const svc = createServiceClient()

  const [{ data: rawMrr }, { data: subs }, { data: events }] = await Promise.all([
    (svc as unknown as {
      from: (t: string) => {
        select: (s: string) => {
          maybeSingle: () => Promise<{ data: MrrRow | null }>
        }
      }
    })
      .from('v_mrr_summary')
      .select('*')
      .maybeSingle(),
    svc
      .from('subscriptions')
      .select('*')
      .order('updated_at', { ascending: false })
      .limit(50),
    svc
      .from('subscription_events')
      .select('id, user_id, event_type, amount_cents, currency, created_at')
      .order('created_at', { ascending: false })
      .limit(20),
  ])

  const mrr = rawMrr
  const subsTyped = (subs ?? []) as Subscription[]
  const eventsTyped = (events ?? []) as SubEvent[]

  // Distribuição por plano
  const byPlan = new Map<string, number>()
  for (const s of subsTyped) {
    if (s.status === 'active' || s.status === 'trial') {
      byPlan.set(s.plan, (byPlan.get(s.plan) ?? 0) + 1)
    }
  }

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Crescimento' }, { label: 'Receita' }]}
        title="Receita"
        description="MRR, churn, novas assinaturas. Atualiza em tempo real via webhook Stripe."
      />

      {/* === KPIs === */}
      <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="MRR atual"
          value={mrr?.mrr_brl ? `R$ ${mrr.mrr_brl}` : 'R$ 0'}
          subtitle="receita mensal recorrente"
          icon={CreditCard}
        />
        <KpiCard
          label="Assinaturas ativas"
          value={formatNumber(mrr?.active_subs ?? 0)}
          subtitle="active + trial"
          icon={Users}
        />
        <KpiCard
          label="Novas (30d)"
          value={formatNumber(mrr?.new_30d ?? 0)}
          subtitle="cadastradas"
          icon={TrendingUp}
        />
        <KpiCard
          label="Churn 30d"
          value={`${((mrr?.churn_rate_30d ?? 0) * 100).toFixed(1)}%`}
          subtitle={`${mrr?.churned_30d ?? 0} cancelaram`}
          higherIsBetter={false}
          icon={TrendingDown}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        {/* === Por plano === */}
        <ContentCard
          title="Distribuição por plano"
          description="Apenas active + trial"
          className="lg:col-span-1"
        >
          {byPlan.size === 0 ? (
            <p className="text-sm text-muted-foreground">
              Nenhuma assinatura ativa.{' '}
              <a
                href="/settings/api-keys"
                className="underline hover:text-foreground"
              >
                Configure Stripe →
              </a>
            </p>
          ) : (
            <div className="space-y-3">
              {[...byPlan.entries()].map(([plan, n]) => {
                const pct = (n / (mrr?.active_subs ?? 1)) * 100
                return (
                  <div key={plan} className="space-y-1">
                    <div className="flex items-center justify-between text-xs">
                      <span className="font-medium capitalize">{plan}</span>
                      <span className="font-mono tabular-nums">
                        {n} <span className="text-muted-foreground">({pct.toFixed(0)}%)</span>
                      </span>
                    </div>
                    <div className="h-2 bg-muted/40 rounded-sm relative overflow-hidden">
                      <div
                        className="absolute inset-y-0 left-0 bg-moss-500 rounded-sm"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </ContentCard>

        {/* === Últimas assinaturas === */}
        <ContentCard
          title="Últimas assinaturas"
          description="Top 10 por updated_at"
          className="lg:col-span-2"
        >
          {subsTyped.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem assinaturas ainda.</p>
          ) : (
            <ul className="space-y-2">
              {subsTyped.slice(0, 10).map((s) => (
                <li
                  key={s.id}
                  className="glass-subtle flex items-center gap-3 p-2.5 text-xs"
                >
                  <span
                    className={`shrink-0 inline-block h-2 w-2 rounded-full ${
                      s.status === 'active'
                        ? 'bg-moss-500'
                        : s.status === 'trial'
                          ? 'bg-amber-500'
                          : 'bg-rose-500'
                    }`}
                  />
                  <a
                    href={`/users/${s.user_id}`}
                    className="font-mono text-foreground hover:underline truncate flex-1"
                  >
                    {s.user_id.slice(0, 8)}
                  </a>
                  <span className="font-mono uppercase tracking-widest text-[10px] text-muted-foreground w-16 text-right">
                    {s.plan}
                  </span>
                  <span className="font-mono uppercase tracking-widest text-[10px] text-muted-foreground w-20 text-right">
                    {s.status}
                  </span>
                  {s.cancel_at_period_end && (
                    <span className="px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-700 text-[10px] font-mono">
                      cancelando
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </ContentCard>
      </div>

      {/* === Eventos === */}
      <ContentCard
        title="Eventos Stripe recentes"
        description="Webhook subscription_events"
      >
        {eventsTyped.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Sem eventos ainda. Quando o Stripe webhook receber pagamentos, aparecerão aqui.
          </p>
        ) : (
          <ul className="space-y-1.5">
            {eventsTyped.map((e) => (
              <li
                key={e.id}
                className="flex items-center gap-3 text-xs font-mono py-1.5 border-b border-border/40 last:border-0"
              >
                <span className="text-muted-foreground tabular-nums shrink-0 w-32">
                  {new Date(e.created_at).toLocaleString('pt-BR')}
                </span>
                <span className="text-foreground flex-1 truncate">{e.event_type}</span>
                {e.user_id && (
                  <a
                    href={`/users/${e.user_id}`}
                    className="text-muted-foreground hover:underline tabular-nums"
                  >
                    {e.user_id.slice(0, 8)}
                  </a>
                )}
                {e.amount_cents != null && e.amount_cents > 0 && (
                  <span className="font-mono tabular-nums text-foreground w-20 text-right">
                    {e.currency.toUpperCase()} {(e.amount_cents / 100).toFixed(2)}
                  </span>
                )}
              </li>
            ))}
          </ul>
        )}
      </ContentCard>
    </div>
  )
}
