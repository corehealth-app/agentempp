/**
 * Status bar persistente no topo do admin.
 * 4 indicadores em tempo (quase) real:
 *   - Sistema (webhook + crons)
 *   - WhatsApp (quality rating)
 *   - Custo 24h
 *   - Atenção (top items)
 *
 * Server component — re-renderiza a cada navegação. Para realtime,
 * dropar Supabase Realtime no client component (futuro).
 */
import Link from 'next/link'
import { AlertCircle, CheckCircle2, Circle, DollarSign, Phone } from 'lucide-react'
import { createServiceClient } from '@/lib/supabase/server'
import { cn } from '@/lib/utils'

interface StatusItem {
  href?: string
  icon: React.ComponentType<{ className?: string }>
  label: string
  value: string
  tone: 'ok' | 'warn' | 'err' | 'info'
}

async function loadStatuses(): Promise<StatusItem[]> {
  const svc = createServiceClient()

  // 1. Crons recentes — quantos rodaram com sucesso nas últimas 24h
  const { data: crons } = await svc
    .from('v_cron_jobs')
    .select('jobname, last_run, active')

  const cronsActive = (crons ?? []).filter((c) => c.active).length
  const cronsFailed = (crons ?? []).filter(
    (c) => (c.last_run as { status?: string } | null)?.status === 'failed',
  ).length

  // 2. WhatsApp quality
  const { data: phoneStatusRaw } = await svc
    .from('whatsapp_phone_status')
    .select('quality_rating, messaging_limit_tier, last_checked_at')
    .order('last_checked_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  const phoneStatus = phoneStatusRaw as
    | { quality_rating: string | null; messaging_limit_tier: string | null }
    | null

  // 3. Custo 24h
  const since24h = new Date(Date.now() - 24 * 3600_000).toISOString()
  const { data: costRows } = await svc
    .from('messages')
    .select('cost_usd')
    .gt('created_at', since24h)
  const cost24h = (costRows ?? []).reduce(
    (s, r) => s + Number((r as { cost_usd: number | null }).cost_usd ?? 0),
    0,
  )

  // 4. Atenção pendente — view não tipada ainda, casting explícito
  const { count: attentionCount } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string, opts?: { count: 'exact'; head: true }) => Promise<{ count: number | null }>
    }
  })
    .from('v_attention_items')
    .select('*', { count: 'exact', head: true })

  return [
    {
      href: '/settings/crons',
      icon: cronsFailed > 0 ? AlertCircle : CheckCircle2,
      label: 'Sistema',
      value:
        cronsFailed > 0
          ? `${cronsFailed} cron${cronsFailed > 1 ? 's' : ''} falhou`
          : `${cronsActive} crons ok`,
      tone: cronsFailed > 0 ? 'err' : 'ok',
    },
    {
      icon: Phone,
      label: 'WhatsApp',
      value: phoneStatus?.quality_rating
        ? `${phoneStatus.quality_rating} · tier ${phoneStatus.messaging_limit_tier ?? '?'}`
        : 'sem leitura',
      tone:
        phoneStatus?.quality_rating === 'GREEN'
          ? 'ok'
          : phoneStatus?.quality_rating === 'YELLOW'
            ? 'warn'
            : phoneStatus?.quality_rating === 'RED'
              ? 'err'
              : 'info',
    },
    {
      href: '/messages',
      icon: DollarSign,
      label: 'Custo 24h',
      value: `$${cost24h.toFixed(3)}`,
      tone: cost24h > 5 ? 'warn' : cost24h > 20 ? 'err' : 'ok',
    },
    {
      href: '/dashboard',
      icon: AlertCircle,
      label: 'Atenção',
      value:
        (attentionCount ?? 0) > 0
          ? `${attentionCount} item${attentionCount === 1 ? '' : 's'}`
          : 'tudo limpo',
      tone: (attentionCount ?? 0) > 5 ? 'err' : (attentionCount ?? 0) > 0 ? 'warn' : 'ok',
    },
  ]
}

const TONE_CLASSES: Record<StatusItem['tone'], string> = {
  ok: 'text-moss-700',
  warn: 'text-amber-600',
  err: 'text-rose-600',
  info: 'text-muted-foreground',
}
const DOT_CLASSES: Record<StatusItem['tone'], string> = {
  ok: 'bg-moss-500',
  warn: 'bg-amber-500',
  err: 'bg-rose-500',
  info: 'bg-muted-foreground/40',
}

export async function StatusBar() {
  const items = await loadStatuses()

  return (
    <div className="border-b border-border bg-background/80 backdrop-blur-md">
      <div className="px-4 sm:px-6 py-2 flex items-center gap-4 overflow-x-auto">
        {items.map((it, i) => {
          const Icon = it.icon
          const Wrapper = it.href ? Link : ('div' as const)
          const wrapperProps = it.href ? { href: it.href } : {}
          return (
            <Wrapper
              key={i}
              {...(wrapperProps as { href: string })}
              className={cn(
                'flex items-center gap-2 text-xs whitespace-nowrap shrink-0',
                it.href && 'hover:opacity-70 transition-opacity cursor-pointer',
              )}
            >
              <span className={cn('relative inline-block h-2 w-2 rounded-full', DOT_CLASSES[it.tone])}>
                {it.tone !== 'ok' && (
                  <span
                    className={cn(
                      'absolute inset-0 rounded-full animate-ping opacity-60',
                      DOT_CLASSES[it.tone],
                    )}
                  />
                )}
              </span>
              <Icon className={cn('h-3.5 w-3.5', TONE_CLASSES[it.tone])} />
              <span className="font-mono uppercase tracking-wider text-[10px] text-muted-foreground">
                {it.label}
              </span>
              <span className={cn('font-mono', TONE_CLASSES[it.tone])}>{it.value}</span>
            </Wrapper>
          )
        })}
        <div className="ml-auto flex items-center gap-1.5 text-[10px] font-mono text-muted-foreground">
          <Circle className="h-2 w-2 fill-current animate-pulse" />
          live
        </div>
      </div>
    </div>
  )
}
