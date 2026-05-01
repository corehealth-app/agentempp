import { ContentCard, PageHeader, StatCard } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatNumber, formatUSD } from '@/lib/utils'
import {
  Activity,
  AlertCircle,
  Bot,
  CheckCircle2,
  Circle,
  CreditCard,
  DollarSign,
  Dumbbell,
  MessageSquare,
  UtensilsCrossed,
  Users,
  Zap,
} from 'lucide-react'

interface KPIs {
  period_days: number
  users_total: number
  users_active_period: number
  messages_in: number
  messages_out: number
  cost_usd_total: number
  avg_latency_ms: number
  tools_called: number
  tools_failed: number
  meals_logged: number
  workouts_logged: number
  subscriptions_active: number
  top_models: Array<{ model: string; calls: number }>
}

export default async function DashboardPage() {
  const supabase = createServiceClient()
  const { data: kpis } = await supabase.rpc('agent_kpis', { days: 7 })
  const k = (kpis ?? {}) as unknown as KPIs

  const { data: recentMessages } = await supabase
    .from('messages')
    .select('id, direction, content, agent_stage, model_used, cost_usd, latency_ms, created_at')
    .order('created_at', { ascending: false })
    .limit(8)

  const { data: phoneStatus } = await supabase
    .from('whatsapp_phone_status')
    .select('*')
    .limit(1)
    .maybeSingle()

  const avgCostPerOut =
    (k.messages_out ?? 0) > 0 ? Number(k.cost_usd_total ?? 0) / (k.messages_out ?? 1) : 0

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Dashboard' }]}
        title="Dashboard"
        description="Visão geral dos últimos 7 dias do método e do agente."
      />

      {/* === Status row === */}
      <div className="grid gap-4 md:grid-cols-3">
        <div className="glass-card p-5">
          <div className="flex items-center justify-between mb-3">
            <span className="section-eyebrow">Status do agente</span>
            <CheckCircle2 className="h-4 w-4 text-moss-500" />
          </div>
          <div className="font-display text-2xl text-foreground tracking-tight">Operacional</div>
          <div className="mt-1 text-xs font-mono text-muted-foreground">
            MESSAGING_PROVIDER=console
          </div>
        </div>

        <div className="glass-card p-5">
          <div className="flex items-center justify-between mb-3">
            <span className="section-eyebrow">Quality WhatsApp</span>
            {phoneStatus ? (
              <Circle
                className={`h-3 w-3 ${
                  phoneStatus.quality_rating === 'GREEN'
                    ? 'fill-moss-500 text-moss-500'
                    : phoneStatus.quality_rating === 'YELLOW'
                      ? 'fill-amber-500 text-amber-500'
                      : 'fill-red-500 text-red-500'
                }`}
              />
            ) : (
              <AlertCircle className="h-4 w-4 text-muted-foreground" />
            )}
          </div>
          <div className="font-display text-2xl text-foreground tracking-tight">
            {phoneStatus?.quality_rating ?? 'N/D'}
          </div>
          <div className="mt-1 text-xs font-mono text-muted-foreground">
            {phoneStatus?.messaging_limit_tier ?? 'WhatsApp não conectado'}
          </div>
        </div>

        <div className="glass-card p-5">
          <div className="flex items-center justify-between mb-3">
            <span className="section-eyebrow">Latência média</span>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </div>
          <div className="font-display text-2xl text-foreground tracking-tight">
            <span className="num">{formatNumber(k.avg_latency_ms ?? 0)}</span>
            <span className="text-base text-muted-foreground ml-1.5 font-sans">ms</span>
          </div>
          <div className="mt-1 text-xs font-mono text-muted-foreground">por turno do agente</div>
        </div>
      </div>

      {/* === KPIs row === */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="Usuários ativos"
          value={`${formatNumber(k.users_active_period ?? 0)}`}
          subtitle={`de ${formatNumber(k.users_total ?? 0)} totais`}
          icon={Users}
        />
        <StatCard
          label="Mensagens trocadas"
          value={formatNumber((k.messages_in ?? 0) + (k.messages_out ?? 0))}
          subtitle={`${formatNumber(k.messages_in ?? 0)} in · ${formatNumber(k.messages_out ?? 0)} out`}
          icon={MessageSquare}
        />
        <StatCard
          label="Custo IA acumulado"
          value={formatUSD(Number(k.cost_usd_total ?? 0), 2)}
          subtitle={`média ${formatUSD(avgCostPerOut, 5)}/turno`}
          variant="feature"
          icon={DollarSign}
        />
        <StatCard
          label="Assinaturas"
          value={formatNumber(k.subscriptions_active ?? 0)}
          subtitle="ativas + trial"
          icon={CreditCard}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="Refeições registradas"
          value={formatNumber(k.meals_logged ?? 0)}
          icon={UtensilsCrossed}
        />
        <StatCard
          label="Treinos"
          value={formatNumber(k.workouts_logged ?? 0)}
          icon={Dumbbell}
        />
        <StatCard
          label="Tool calls"
          value={formatNumber(k.tools_called ?? 0)}
          subtitle={
            k.tools_failed
              ? `${formatNumber(k.tools_failed)} falharam`
              : 'todas com sucesso'
          }
          icon={Activity}
        />
        <StatCard
          label="Custo médio/turno"
          value={formatUSD(avgCostPerOut, 5)}
          subtitle="só LLM, sem TTS/STT"
          icon={Bot}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <ContentCard title="Modelos mais usados" description="Distribuição por modelo no período">
          {(k.top_models ?? []).length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem dados ainda.</p>
          ) : (
            <ul className="space-y-2.5">
              {(k.top_models ?? []).map((m, idx) => {
                const max = Math.max(...(k.top_models ?? []).map((x) => x.calls))
                const pct = (m.calls / max) * 100
                return (
                  <li key={m.model} className="space-y-1">
                    <div className="flex items-center justify-between text-xs">
                      <span className="flex items-center gap-2">
                        <span className="font-mono text-muted-foreground tabular-nums">
                          {String(idx + 1).padStart(2, '0')}
                        </span>
                        <code className="font-mono text-[11px] text-foreground">{m.model}</code>
                      </span>
                      <span className="font-mono text-xs tabular-nums">
                        {formatNumber(m.calls)}
                      </span>
                    </div>
                    <div className="h-1 bg-muted rounded-full relative overflow-hidden">
                      <div
                        className="absolute inset-y-0 left-0 bg-moss-500 rounded-full"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </ContentCard>

        <ContentCard title="Mensagens recentes" description="Últimas 8 entradas/saídas">
          {!recentMessages || recentMessages.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem mensagens.</p>
          ) : (
            <ul className="space-y-2.5">
              {recentMessages.map((m) => (
                <li key={m.id} className="flex items-start gap-3 text-xs leading-tight">
                  <span
                    className={`shrink-0 mt-1 inline-block h-1.5 w-1.5 rounded-full ${m.direction === 'in' ? 'bg-moss-500' : 'bg-bronze'}`}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-0.5">
                      {m.direction === 'in' ? 'usuário' : 'agente'}
                      {m.agent_stage ? ` · ${m.agent_stage.replace('_', ' ')}` : ''}
                    </div>
                    <div className="text-foreground truncate">
                      {m.content?.slice(0, 100) ?? '(mídia)'}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </ContentCard>
      </div>
    </div>
  )
}
