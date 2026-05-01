import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { createServiceClient } from '@/lib/supabase/server'
import { formatNumber, formatUSD } from '@/lib/utils'
import {
  Activity,
  AlertCircle,
  Bot,
  CheckCircle2,
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
    .limit(10)

  const { data: phoneStatus } = await supabase
    .from('whatsapp_phone_status')
    .select('*')
    .limit(1)
    .maybeSingle()

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <p className="text-muted-foreground">Visão geral dos últimos {k.period_days ?? 7} dias</p>
      </div>

      {/* Status do agente */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Status do agente</CardTitle>
            <Bot className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-2">
              <CheckCircle2 className="h-5 w-5 text-green-500" />
              <span className="text-lg font-semibold">Operacional</span>
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              MESSAGING_PROVIDER=console (WhatsApp ainda não plugado)
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">WhatsApp Quality</CardTitle>
            <MessageSquare className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-2">
              {phoneStatus ? (
                <>
                  <span
                    className={`inline-block h-3 w-3 rounded-full ${
                      phoneStatus.quality_rating === 'GREEN'
                        ? 'bg-green-500'
                        : phoneStatus.quality_rating === 'YELLOW'
                          ? 'bg-yellow-500'
                          : 'bg-red-500'
                    }`}
                  />
                  <span className="text-lg font-semibold">{phoneStatus.quality_rating}</span>
                </>
              ) : (
                <>
                  <AlertCircle className="h-5 w-5 text-muted-foreground" />
                  <span className="text-lg font-semibold">N/A</span>
                </>
              )}
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              {phoneStatus?.messaging_limit_tier ?? 'WhatsApp não conectado'}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Latência média</CardTitle>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatNumber(k.avg_latency_ms ?? 0)} ms
            </div>
            <p className="text-xs text-muted-foreground mt-1">por turno do agente</p>
          </CardContent>
        </Card>
      </div>

      {/* KPIs principais */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <KPICard
          title="Usuários ativos"
          value={`${formatNumber(k.users_active_period ?? 0)} / ${formatNumber(k.users_total ?? 0)}`}
          subtitle="período / total"
          icon={Users}
        />
        <KPICard
          title="Mensagens"
          value={`${formatNumber((k.messages_in ?? 0) + (k.messages_out ?? 0))}`}
          subtitle={`${formatNumber(k.messages_in ?? 0)} in / ${formatNumber(k.messages_out ?? 0)} out`}
          icon={MessageSquare}
        />
        <KPICard
          title="Custo IA"
          value={formatUSD(Number(k.cost_usd_total ?? 0))}
          subtitle="OpenRouter + outros"
          icon={DollarSign}
        />
        <KPICard
          title="Assinaturas"
          value={formatNumber(k.subscriptions_active ?? 0)}
          subtitle="ativas + trial"
          icon={CreditCard}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <KPICard
          title="Refeições logadas"
          value={formatNumber(k.meals_logged ?? 0)}
          icon={UtensilsCrossed}
        />
        <KPICard
          title="Treinos"
          value={formatNumber(k.workouts_logged ?? 0)}
          icon={Dumbbell}
        />
        <KPICard
          title="Tool calls"
          value={`${formatNumber(k.tools_called ?? 0)}`}
          subtitle={`${formatNumber(k.tools_failed ?? 0)} falharam`}
          icon={Activity}
        />
        <KPICard
          title="Custo médio/turno"
          value={
            (k.messages_out ?? 0) > 0
              ? formatUSD(Number(k.cost_usd_total ?? 0) / (k.messages_out ?? 1))
              : '$0.0000'
          }
          icon={DollarSign}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {/* Modelos mais usados */}
        <Card>
          <CardHeader>
            <CardTitle>Modelos mais usados</CardTitle>
            <CardDescription>Distribuição por modelo no período</CardDescription>
          </CardHeader>
          <CardContent>
            {(k.top_models ?? []).length === 0 ? (
              <p className="text-sm text-muted-foreground">Sem dados ainda.</p>
            ) : (
              <ul className="space-y-2">
                {(k.top_models ?? []).map((m) => (
                  <li key={m.model} className="flex items-center justify-between text-sm">
                    <code className="text-xs bg-muted px-2 py-0.5 rounded">{m.model}</code>
                    <span className="font-medium">{formatNumber(m.calls)}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        {/* Mensagens recentes */}
        <Card>
          <CardHeader>
            <CardTitle>Mensagens recentes</CardTitle>
            <CardDescription>Últimas 10 entradas/saídas</CardDescription>
          </CardHeader>
          <CardContent>
            {!recentMessages || recentMessages.length === 0 ? (
              <p className="text-sm text-muted-foreground">Sem mensagens.</p>
            ) : (
              <ul className="space-y-2 text-xs">
                {recentMessages.map((m) => (
                  <li
                    key={m.id}
                    className="flex items-start gap-2 border-b pb-1 last:border-0"
                  >
                    <span
                      className={`shrink-0 mt-0.5 inline-block h-2 w-2 rounded-full ${m.direction === 'in' ? 'bg-blue-500' : 'bg-green-500'}`}
                    />
                    <span className="flex-1 truncate">
                      <span className="text-muted-foreground">
                        [{m.direction}] {m.agent_stage ?? '—'}{' '}
                      </span>
                      {m.content?.slice(0, 80) ?? '(mídia)'}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

function KPICard({
  title,
  value,
  subtitle,
  icon: Icon,
}: {
  title: string
  value: string
  subtitle?: string
  icon: React.ComponentType<{ className?: string }>
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <Icon className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
        {subtitle && <p className="text-xs text-muted-foreground mt-1">{subtitle}</p>}
      </CardContent>
    </Card>
  )
}
