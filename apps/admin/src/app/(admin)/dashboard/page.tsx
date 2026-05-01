import { PageHeader, StatCard } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatNumber, formatUSD } from '@/lib/utils'
import {
  AlertCircle,
  CheckCircle2,
  Circle,
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

  const avgCostPerOut = (k.messages_out ?? 0) > 0
    ? Number(k.cost_usd_total ?? 0) / (k.messages_out ?? 1)
    : 0

  return (
    <div className="px-10 py-12 max-w-[1280px]">
      <PageHeader
        chapter="01"
        eyebrow="Visão geral · últimos 7 dias"
        title="Dashboard"
        description="Estado do método e do agente. Métricas atualizadas a cada requisição."
      />

      {/* === Status row === */}
      <section className="mb-10">
        <div className="grid gap-3 md:grid-cols-3">
          <div className="border border-border bg-cream-50 p-5 rounded-sm">
            <div className="flex items-center justify-between mb-3">
              <span className="section-eyebrow">Status do agente</span>
              <CheckCircle2 className="h-4 w-4 text-moss-500" />
            </div>
            <div className="font-display text-2xl text-ink-900 tracking-tight">Operacional</div>
            <div className="mt-1 text-xs font-mono text-ink-500">
              MESSAGING_PROVIDER=console
            </div>
          </div>

          <div className="border border-border bg-cream-50 p-5 rounded-sm">
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
                <AlertCircle className="h-4 w-4 text-ink-400" />
              )}
            </div>
            <div className="font-display text-2xl text-ink-900 tracking-tight">
              {phoneStatus?.quality_rating ?? 'N/D'}
            </div>
            <div className="mt-1 text-xs font-mono text-ink-500">
              {phoneStatus?.messaging_limit_tier ?? 'WhatsApp não conectado'}
            </div>
          </div>

          <div className="border border-border bg-cream-50 p-5 rounded-sm">
            <div className="flex items-center justify-between mb-3">
              <span className="section-eyebrow">Latência média</span>
              <span className="font-mono text-xs text-ink-500">p50</span>
            </div>
            <div className="font-display text-2xl text-ink-900 tracking-tight">
              <span className="num">{formatNumber(k.avg_latency_ms ?? 0)}</span>
              <span className="text-base text-ink-500 ml-1.5 font-sans">ms</span>
            </div>
            <div className="mt-1 text-xs font-mono text-ink-500">por turno do agente</div>
          </div>
        </div>
      </section>

      {/* === KPIs row === */}
      <section className="mb-10">
        <div className="flex items-baseline gap-3 mb-4 px-1">
          <span className="font-mono text-xs text-ink-500 tabular-nums">§ 1.1</span>
          <h2 className="font-display text-xl text-ink-900 tracking-tight">Métricas principais</h2>
        </div>
        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
          <StatCard
            label="Usuários ativos"
            value={`${formatNumber(k.users_active_period ?? 0)}`}
            subtitle={`de ${formatNumber(k.users_total ?? 0)} totais`}
          />
          <StatCard
            label="Mensagens trocadas"
            value={formatNumber((k.messages_in ?? 0) + (k.messages_out ?? 0))}
            subtitle={`${formatNumber(k.messages_in ?? 0)} in · ${formatNumber(k.messages_out ?? 0)} out`}
          />
          <StatCard
            label="Custo IA acumulado"
            value={formatUSD(Number(k.cost_usd_total ?? 0), 2)}
            subtitle={`média ${formatUSD(avgCostPerOut, 5)}/turno`}
            variant="feature"
          />
          <StatCard
            label="Assinaturas"
            value={formatNumber(k.subscriptions_active ?? 0)}
            subtitle="ativas + trial"
          />
        </div>
      </section>

      {/* === Atividade row === */}
      <section className="mb-10">
        <div className="flex items-baseline gap-3 mb-4 px-1">
          <span className="font-mono text-xs text-ink-500 tabular-nums">§ 1.2</span>
          <h2 className="font-display text-xl text-ink-900 tracking-tight">Atividade no método</h2>
        </div>
        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
          <StatCard label="Refeições registradas" value={formatNumber(k.meals_logged ?? 0)} />
          <StatCard label="Treinos" value={formatNumber(k.workouts_logged ?? 0)} />
          <StatCard
            label="Tool calls"
            value={formatNumber(k.tools_called ?? 0)}
            subtitle={
              k.tools_failed
                ? `${formatNumber(k.tools_failed)} falharam`
                : 'todas com sucesso'
            }
          />
          <StatCard
            label="Custo médio/turno"
            value={formatUSD(avgCostPerOut, 5)}
            subtitle="só LLM, sem TTS/STT"
          />
        </div>
      </section>

      {/* === Two-column data === */}
      <section className="grid gap-3 lg:grid-cols-2 mb-10">
        {/* Top models */}
        <div className="border border-border bg-cream-50 rounded-sm">
          <div className="border-b border-border px-5 py-3 flex items-baseline gap-3">
            <span className="font-mono text-xs text-ink-500 tabular-nums">§ 1.3</span>
            <h3 className="font-display text-base text-ink-900">Modelos mais usados</h3>
          </div>
          <div className="p-5">
            {(k.top_models ?? []).length === 0 ? (
              <p className="text-sm text-ink-500">Sem dados ainda.</p>
            ) : (
              <ul className="space-y-2">
                {(k.top_models ?? []).map((m, idx) => {
                  const max = Math.max(...(k.top_models ?? []).map((x) => x.calls))
                  const pct = (m.calls / max) * 100
                  return (
                    <li key={m.model} className="space-y-1">
                      <div className="flex items-center justify-between text-xs">
                        <span className="flex items-center gap-2">
                          <span className="font-mono text-ink-400 tabular-nums">
                            {String(idx + 1).padStart(2, '0')}
                          </span>
                          <code className="font-mono text-[11px] text-ink-700">{m.model}</code>
                        </span>
                        <span className="font-mono text-xs tabular-nums text-ink-900">
                          {formatNumber(m.calls)}
                        </span>
                      </div>
                      <div className="h-px bg-cream-200 relative overflow-hidden">
                        <div
                          className="absolute inset-y-0 left-0 bg-moss-500"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    </li>
                  )
                })}
              </ul>
            )}
          </div>
        </div>

        {/* Recent messages */}
        <div className="border border-border bg-cream-50 rounded-sm">
          <div className="border-b border-border px-5 py-3 flex items-baseline gap-3">
            <span className="font-mono text-xs text-ink-500 tabular-nums">§ 1.4</span>
            <h3 className="font-display text-base text-ink-900">Mensagens recentes</h3>
          </div>
          <div className="p-5">
            {!recentMessages || recentMessages.length === 0 ? (
              <p className="text-sm text-ink-500">Sem mensagens ainda.</p>
            ) : (
              <ul className="space-y-2">
                {recentMessages.map((m) => (
                  <li key={m.id} className="flex items-start gap-3 text-xs leading-tight">
                    <span
                      className={`shrink-0 mt-1 inline-block h-1.5 w-1.5 rounded-full ${m.direction === 'in' ? 'bg-moss-500' : 'bg-bronze'}`}
                    />
                    <div className="flex-1 min-w-0">
                      <div className="text-[10px] uppercase tracking-widest font-mono text-ink-500 mb-0.5">
                        {m.direction === 'in' ? 'usuário' : 'agente'}
                        {m.agent_stage ? ` · ${m.agent_stage.replace('_', ' ')}` : ''}
                      </div>
                      <div className="text-ink-700 truncate">
                        {m.content?.slice(0, 100) ?? '(mídia)'}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </section>

      {/* Footer note */}
      <footer className="hairline pt-6 flex items-center justify-between text-[10px] font-mono uppercase tracking-widest text-ink-500">
        <span>Atualizado em tempo real</span>
        <span>—</span>
        <span>Agente MPP · CoreHealth</span>
      </footer>
    </div>
  )
}
