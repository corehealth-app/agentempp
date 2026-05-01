import Link from 'next/link'
import {
  Activity,
  ArrowRight,
  CheckCircle2,
  CreditCard,
  DollarSign,
  MessageSquare,
  Users,
  Zap,
} from 'lucide-react'
import { ContentCard, PageHeader } from '@/components/page-header'
import { KpiCard } from '@/components/kpi-card'
import { Sparkline } from '@/components/sparkline'
import { createServiceClient } from '@/lib/supabase/server'
import { formatNumber, formatUSD } from '@/lib/utils'

interface DailyKpi {
  day: string
  dau: number
  messages_in: number
  messages_out: number
  cost_usd: number
  p50_latency_ms: number
  p95_latency_ms: number
  new_users: number
  tools_called: number
  tools_ok: number
  tools_err: number
  tool_success_rate: number | null
}

interface AttentionItem {
  kind: string
  priority: number
  user_id: string
  name: string | null
  message: string
  created_at: string
}

interface FunnelRow {
  cohort_week: string
  cohort_size: number
  s1_messaged: number
  s2_onboarded: number
  s3_logged_meal: number
  s4_closed_block: number
  s5_paying: number
}

interface MrrRow {
  active_subs: number
  mrr_brl: number | null
  new_30d: number
  churned_30d: number
  churn_rate_30d: number | null
}

const ATTENTION_LABELS: Record<string, { emoji: string; tone: string }> = {
  error_recent: { emoji: '🚨', tone: 'border-rose-500/40' },
  payment_failed: { emoji: '💸', tone: 'border-rose-400/40' },
  onboarding_stuck: { emoji: '⏳', tone: 'border-amber-500/40' },
  silent_user: { emoji: '😴', tone: 'border-muted-foreground/20' },
  block_milestone: { emoji: '🏆', tone: 'border-moss-500/40' },
}

function sumLast(rows: DailyKpi[], n: number, key: keyof DailyKpi): number {
  return rows
    .slice(-n)
    .reduce((s, r) => s + Number(r[key] ?? 0), 0)
}

function avgLast(rows: DailyKpi[], n: number, key: keyof DailyKpi): number {
  const slice = rows.slice(-n)
  if (slice.length === 0) return 0
  return slice.reduce((s, r) => s + Number(r[key] ?? 0), 0) / slice.length
}

export default async function DashboardPage() {
  const svc = createServiceClient()

  // KPIs diários (mv_kpis_daily — última 30d)
  const { data: rawKpis } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        order: (col: string, opt: { ascending: boolean }) => Promise<{ data: DailyKpi[] | null }>
      }
    }
  })
    .from('mv_kpis_daily')
    .select('*')
    .order('day', { ascending: true })
  const kpis = rawKpis ?? []

  // Atenção: top 5
  const { data: rawAttention } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        order: (col: string, opt: { ascending: boolean }) => {
          limit: (n: number) => Promise<{ data: AttentionItem[] | null }>
        }
      }
    }
  })
    .from('v_attention_items')
    .select('*')
    .order('priority', { ascending: false })
    .limit(5)
  const attention = rawAttention ?? []

  // Funil
  const { data: rawFunnel } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        order: (col: string, opt: { ascending: boolean }) => {
          limit: (n: number) => Promise<{ data: FunnelRow[] | null }>
        }
      }
    }
  })
    .from('v_funnel_activation')
    .select('*')
    .order('cohort_week', { ascending: false })
    .limit(4)
  const funnel = rawFunnel ?? []

  // MRR
  const { data: rawMrr } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        maybeSingle: () => Promise<{ data: MrrRow | null }>
      }
    }
  })
    .from('v_mrr_summary')
    .select('*')
    .maybeSingle()
  const mrr = rawMrr ?? null

  // Sparkline data: últimos 14d
  const dauSeries = kpis.slice(-14).map((k) => Number(k.dau))
  const costSeries = kpis.slice(-14).map((k) => Number(k.cost_usd))
  const latencySeries = kpis.slice(-14).map((k) => Number(k.p95_latency_ms))
  const inSeries = kpis.slice(-14).map((k) => Number(k.messages_in))

  const dau7 = sumLast(kpis, 7, 'dau')
  const dauPrev7 = avgLast(kpis.slice(0, -7), 7, 'dau') * 7
  const messagesIn7 = sumLast(kpis, 7, 'messages_in')
  const messagesInPrev7 = sumLast(kpis.slice(0, -7), 7, 'messages_in')
  const cost7 = sumLast(kpis, 7, 'cost_usd')
  const costPrev7 = sumLast(kpis.slice(0, -7), 7, 'cost_usd')
  const p95Now = avgLast(kpis, 7, 'p95_latency_ms')
  const p95Prev = avgLast(kpis.slice(0, -7), 7, 'p95_latency_ms')
  const newUsers7 = sumLast(kpis, 7, 'new_users')
  const newUsersPrev7 = sumLast(kpis.slice(0, -7), 7, 'new_users')

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Hoje' }]}
        title="Hoje"
        description="O que você precisa saber e onde precisa agir."
      />

      {/* === Atenção necessária — quem precisa de mim agora === */}
      <ContentCard
        title="Quem precisa da sua atenção"
        description={
          attention.length === 0
            ? 'Tudo limpo no momento.'
            : `${attention.length} item${attention.length === 1 ? '' : 's'} priorizad${attention.length === 1 ? 'o' : 'os'}`
        }
      >
        {attention.length === 0 ? (
          <div className="flex items-center gap-3 py-2 text-sm text-muted-foreground">
            <CheckCircle2 className="h-5 w-5 text-moss-600" />
            Nenhuma ação pendente. Volta de tempos em tempos.
          </div>
        ) : (
          <ul className="space-y-2">
            {attention.map((a, i) => {
              const meta = ATTENTION_LABELS[a.kind] ?? {
                emoji: '•',
                tone: 'border-muted-foreground/20',
              }
              return (
                <li key={`${a.user_id}-${i}`}>
                  <Link
                    href={`/users/${a.user_id}`}
                    className={`group glass-subtle flex items-start gap-3 p-3 border-l-2 ${meta.tone} hover:bg-muted/40 transition-colors`}
                  >
                    <span className="text-xl shrink-0 leading-none mt-0.5">{meta.emoji}</span>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-baseline gap-2 flex-wrap">
                        <span className="font-medium text-foreground">
                          {a.name ?? '(sem nome)'}
                        </span>
                        <span className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
                          {a.kind.replace('_', ' ')}
                        </span>
                      </div>
                      <p className="text-sm text-muted-foreground mt-0.5 line-clamp-2">
                        {a.message}
                      </p>
                    </div>
                    <ArrowRight className="h-4 w-4 text-muted-foreground/40 group-hover:text-foreground transition-colors mt-1 shrink-0" />
                  </Link>
                </li>
              )
            })}
          </ul>
        )}
      </ContentCard>

      {/* === KPIs com sparklines === */}
      <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Usuários ativos (7d)"
          value={formatNumber(dau7)}
          series={dauSeries}
          previousValue={dauPrev7}
          currentValue={dau7}
          subtitle="vs 7d anteriores"
          icon={Users}
        />
        <KpiCard
          label="Msgs recebidas (7d)"
          value={formatNumber(messagesIn7)}
          series={inSeries}
          previousValue={messagesInPrev7}
          currentValue={messagesIn7}
          subtitle="vs 7d anteriores"
          icon={MessageSquare}
        />
        <KpiCard
          label="Custo IA (7d)"
          value={formatUSD(cost7, 2)}
          series={costSeries}
          previousValue={costPrev7}
          currentValue={cost7}
          higherIsBetter={false}
          subtitle="vs 7d anteriores"
          icon={DollarSign}
        />
        <KpiCard
          label="Latência P95 (7d avg)"
          value={`${formatNumber(p95Now)} ms`}
          series={latencySeries}
          previousValue={p95Prev}
          currentValue={p95Now}
          higherIsBetter={false}
          subtitle="vs 7d anteriores"
          icon={Zap}
        />
      </div>

      {/* === Funil + MRR === */}
      <div className="grid gap-4 lg:grid-cols-3">
        <ContentCard
          title="Funil de ativação"
          description="Cohorts semanais — onde cada grupo mora"
          className="lg:col-span-2"
        >
          {funnel.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem cohorts ainda.</p>
          ) : (
            <div className="space-y-4">
              {funnel.map((f) => (
                <FunnelRow key={f.cohort_week} f={f} />
              ))}
            </div>
          )}
        </ContentCard>

        <div className="space-y-3">
          <KpiCard
            label="MRR"
            value={mrr?.mrr_brl ? `R$ ${mrr.mrr_brl}` : 'R$ 0'}
            subtitle={`${mrr?.active_subs ?? 0} ativas`}
            icon={CreditCard}
          />
          <KpiCard
            label="Novos pacientes (7d)"
            value={formatNumber(newUsers7)}
            previousValue={newUsersPrev7}
            currentValue={newUsers7}
            subtitle="vs 7d anteriores"
            icon={Users}
          />
          <KpiCard
            label="Churn 30d"
            value={`${((mrr?.churn_rate_30d ?? 0) * 100).toFixed(1)}%`}
            subtitle={`${mrr?.churned_30d ?? 0} cancelaram`}
            higherIsBetter={false}
            icon={Activity}
          />
        </div>
      </div>

      {/* === Saúde do agente === */}
      <ContentCard
        title="Saúde do agente"
        description="Tools, sucesso e modelos mais usados"
      >
        <div className="grid gap-4 md:grid-cols-3">
          <div>
            <div className="section-eyebrow mb-2">Tool success rate</div>
            <div className="font-display text-3xl tracking-tight">
              {kpis.length > 0
                ? `${(avgLast(kpis, 7, 'tool_success_rate') * 100).toFixed(1)}%`
                : 'N/A'}
            </div>
            <Sparkline
              data={kpis.slice(-14).map((k) => (k.tool_success_rate ?? 0) * 100)}
              width={180}
              height={32}
              className="mt-2"
            />
          </div>
          <div>
            <div className="section-eyebrow mb-2">Tools called (7d)</div>
            <div className="font-display text-3xl tracking-tight">
              {formatNumber(sumLast(kpis, 7, 'tools_called'))}
            </div>
            <div className="text-xs font-mono text-muted-foreground mt-2">
              {sumLast(kpis, 7, 'tools_err')} falharam · {sumLast(kpis, 7, 'tools_ok')} ok
            </div>
          </div>
          <div>
            <div className="section-eyebrow mb-2">P50 / P95</div>
            <div className="font-display text-3xl tracking-tight">
              {formatNumber(avgLast(kpis, 7, 'p50_latency_ms'))} /{' '}
              {formatNumber(avgLast(kpis, 7, 'p95_latency_ms'))}
              <span className="text-base text-muted-foreground ml-1.5 font-sans">ms</span>
            </div>
            <div className="text-xs font-mono text-muted-foreground mt-2">
              percentis em últimas 7d
            </div>
          </div>
        </div>
      </ContentCard>

      <div className="text-[10px] font-mono text-muted-foreground/60 text-right pt-2">
        Dados via mv_kpis_daily · refresh 1×/h ·{' '}
        <Link href="/messages" className="underline hover:text-foreground">
          ver mensagens recentes →
        </Link>
      </div>
    </div>
  )
}

function FunnelRow({ f }: { f: FunnelRow }) {
  const max = Math.max(f.cohort_size, 1)
  const steps = [
    { label: 'Cohort', n: f.cohort_size, color: 'bg-muted-foreground/30' },
    { label: 'Mensagem 1', n: f.s1_messaged, color: 'bg-moss-300' },
    { label: 'Onboarding ✓', n: f.s2_onboarded, color: 'bg-moss-400' },
    { label: '1ª refeição', n: f.s3_logged_meal, color: 'bg-moss-500' },
    { label: '1º bloco', n: f.s4_closed_block, color: 'bg-moss-600' },
    { label: 'Pagou', n: f.s5_paying, color: 'bg-moss-700' },
  ]
  const week = new Date(f.cohort_week).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  })
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <span className="text-[11px] font-mono text-muted-foreground uppercase tracking-widest">
          Semana {week}
        </span>
        <span className="text-[11px] font-mono text-muted-foreground">
          {f.cohort_size} {f.cohort_size === 1 ? 'paciente' : 'pacientes'}
        </span>
      </div>
      <div className="space-y-1">
        {steps.slice(1).map((s) => {
          const pct = (s.n / max) * 100
          return (
            <div key={s.label} className="flex items-center gap-2 text-xs">
              <span className="w-24 text-muted-foreground shrink-0">{s.label}</span>
              <div className="flex-1 h-2 bg-muted/40 rounded-sm relative overflow-hidden">
                <div
                  className={`absolute inset-y-0 left-0 ${s.color} rounded-sm transition-all`}
                  style={{ width: `${pct}%` }}
                />
              </div>
              <span className="w-16 text-right tabular-nums font-mono">
                {s.n} <span className="text-muted-foreground">({pct.toFixed(0)}%)</span>
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
