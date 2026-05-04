import Link from 'next/link'
import { MessageSquare } from 'lucide-react'
import { PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { ConversationThread } from './conversation-thread'
import { ConversationSidebar } from './conversation-sidebar'
// Realtime listener + search modal são pesados (websocket / modal Radix)
// mas não bloqueiam conteúdo. Lazy carrega após hydration via wrapper client.
import { LazyRealtimeListener, LazySearchTrigger } from './lazy-extras'

interface Message {
  id: string
  user_id: string
  direction: 'in' | 'out'
  content: string | null
  content_type: string
  agent_stage: string | null
  model_used: string | null
  prompt_tokens: number | null
  completion_tokens: number | null
  cost_usd: number | null
  latency_ms: number | null
  created_at: string
  raw_payload: unknown
  review_flag: string | null
  review_note: string | null
}

interface User {
  id: string
  name: string | null
  wpp: string
  tags?: string[] | null
  admin_notes?: string | null
  metadata?: Record<string, unknown> | null
  status?: string
  country?: string | null
  country_confirmed?: boolean | null
}

interface ConversationSummary {
  user: User
  lastMessage: Message
  inLast24h: number
  outLast24h: number
  status: 'paused' | 'live' | 'recent' | 'cooling' | 'silent'
  hasFlag: boolean
}

function diffMinutes(a: Date, b: Date) {
  return Math.floor((a.getTime() - b.getTime()) / 60000)
}

export default async function ConversasPage({
  searchParams,
}: {
  searchParams: Promise<{ user?: string; filter?: string }>
}) {
  const svc = createServiceClient()
  const params = await searchParams

  const { data: rawMessages } = await svc
    .from('messages')
    .select(
      'id, user_id, direction, content, content_type, agent_stage, model_used, prompt_tokens, completion_tokens, cost_usd, latency_ms, created_at, raw_payload, review_flag, review_note',
    )
    .order('created_at', { ascending: false })
    .limit(300)
  const messages = (rawMessages ?? []) as unknown as Message[]

  const userIds = [...new Set(messages.map((m) => m.user_id))]
  const { data: rawUsers } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        in: (col: string, val: string[]) => Promise<{ data: User[] | null }>
      }
    }
  })
    .from('users')
    .select('id, name, wpp, tags, admin_notes, metadata, status, country, country_confirmed')
    .in('id', userIds.length ? userIds : ['00000000-0000-0000-0000-000000000000'])
  const userMap = new Map<string, User>(
    ((rawUsers ?? []) as User[]).map((u) => [u.id, u]),
  )

  // Agrupa por user
  const summaries = new Map<string, ConversationSummary>()
  const now = new Date()
  for (const m of messages) {
    const u = userMap.get(m.user_id)
    if (!u) continue
    if (!summaries.has(m.user_id)) {
      const minutesAgo = diffMinutes(now, new Date(m.created_at))
      const isPaused = !!(u.metadata?.paused_until &&
        new Date(u.metadata.paused_until as string) > now)
      const status: ConversationSummary['status'] = isPaused
        ? 'paused'
        : minutesAgo <= 60
          ? 'live'
          : minutesAgo <= 24 * 60
            ? 'recent'
            : minutesAgo <= 72 * 60
              ? 'cooling'
              : 'silent'
      summaries.set(m.user_id, {
        user: u,
        lastMessage: m,
        inLast24h: 0,
        outLast24h: 0,
        status,
        hasFlag: false,
      })
    }
    const s = summaries.get(m.user_id)!
    const minutesAgo = diffMinutes(now, new Date(m.created_at))
    if (minutesAgo <= 24 * 60) {
      if (m.direction === 'in') s.inLast24h++
      else s.outLast24h++
    }
    if (m.review_flag) s.hasFlag = true
  }

  let conversations = [...summaries.values()]
  const filter = params.filter
  if (filter === 'live') conversations = conversations.filter((c) => c.status === 'live')
  if (filter === 'silent') conversations = conversations.filter((c) => c.status === 'silent')
  if (filter === 'paused') conversations = conversations.filter((c) => c.status === 'paused')
  if (filter === 'flagged') conversations = conversations.filter((c) => c.hasFlag)

  const selectedUserId = params.user ?? conversations[0]?.user.id
  const thread = selectedUserId
    ? messages.filter((m) => m.user_id === selectedUserId).reverse()
    : []
  const selectedUser = selectedUserId ? userMap.get(selectedUserId) : undefined

  // Estatísticas do paciente selecionado pra sidebar
  let userExtras: {
    progress: {
      xp_total: number
      level: number
      current_streak: number
      blocks_completed: number
    } | null
    profile: {
      sex: string | null
      weight_kg: number | null
      height_cm: number | null
      onboarding_completed: boolean
      current_protocol: string | null
    } | null
    totalCost: number
    totalMessages: number
  } = { progress: null, profile: null, totalCost: 0, totalMessages: 0 }

  if (selectedUserId) {
    const [{ data: progress }, { data: profile }, { data: stats }] = await Promise.all([
      svc.from('user_progress').select('*').eq('user_id', selectedUserId).maybeSingle(),
      svc.from('user_profiles').select('*').eq('user_id', selectedUserId).maybeSingle(),
      svc
        .from('messages')
        .select('cost_usd', { count: 'exact', head: false })
        .eq('user_id', selectedUserId),
    ])
    userExtras = {
      progress: progress as typeof userExtras.progress,
      profile: profile as typeof userExtras.profile,
      totalCost: (stats ?? []).reduce(
        (s, m) => s + Number((m as { cost_usd: number | null }).cost_usd ?? 0),
        0,
      ),
      totalMessages: (stats ?? []).length,
    }
  }

  const flaggedCount = [...summaries.values()].filter((c) => c.hasFlag).length
  const pausedCount = [...summaries.values()].filter((c) => c.status === 'paused').length
  const liveCount = [...summaries.values()].filter((c) => c.status === 'live').length
  const silentCount = [...summaries.values()].filter((c) => c.status === 'silent').length

  return (
    <div className="flex flex-col h-full">
      <LazyRealtimeListener />
      <div className="shrink-0 mb-3">
        <PageHeader
          compact
          breadcrumbs={[{ label: 'Operação' }, { label: 'Conversas' }]}
          title="Conversas"
          description={
            <span className="inline-flex items-center gap-2">
              Observatório do agente em tempo real.
              <span className="inline-flex items-center gap-1 text-[10px] font-mono text-moss-700">
                <span className="relative inline-block h-1.5 w-1.5 rounded-full bg-moss-500">
                  <span className="absolute inset-0 rounded-full animate-ping opacity-60 bg-moss-500" />
                </span>
                live
              </span>
            </span>
          }
          actions={<LazySearchTrigger />}
        />
      </div>

      <div className="grid grid-rows-1 gap-3 lg:grid-cols-[300px_1fr_300px] flex-1 min-h-0 [&>*]:min-h-0 [&>*]:h-full">
        {/* === Esquerda: lista === */}
        <div className="flex flex-col content-card overflow-hidden">
          <div className="flex flex-wrap gap-1 p-2 border-b border-border bg-muted/30">
            <FilterChip href="/messages" label="Todas" active={!filter} count={summaries.size} />
            <FilterChip
              href="/messages?filter=live"
              label="Live"
              active={filter === 'live'}
              count={liveCount}
              tone="moss"
            />
            <FilterChip
              href="/messages?filter=flagged"
              label="Flag"
              active={filter === 'flagged'}
              count={flaggedCount}
              tone="rose"
            />
            <FilterChip
              href="/messages?filter=paused"
              label="Pausa"
              active={filter === 'paused'}
              count={pausedCount}
            />
            <FilterChip
              href="/messages?filter=silent"
              label="Silêncio"
              active={filter === 'silent'}
              count={silentCount}
            />
          </div>

          <ul className="flex-1 overflow-y-auto divide-y divide-border/40">
            {conversations.length === 0 ? (
              <li className="p-6 text-sm text-muted-foreground text-center">
                Nada nesse filtro.
              </li>
            ) : (
              conversations.map((c) => (
                <li key={c.user.id}>
                  <Link
                    href={`/messages?user=${c.user.id}${filter ? `&filter=${filter}` : ''}`}
                    className={`flex items-start gap-3 p-3 hover:bg-muted/40 transition-colors ${
                      selectedUserId === c.user.id ? 'bg-muted/60' : ''
                    }`}
                  >
                    <Avatar name={c.user.name} status={c.status} />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-baseline justify-between gap-2 mb-0.5">
                        <span className="font-medium text-sm text-foreground truncate">
                          {c.user.name ?? c.user.wpp}
                        </span>
                        <span className="text-[10px] font-mono text-muted-foreground shrink-0">
                          {timeAgoCompact(c.lastMessage.created_at)}
                        </span>
                      </div>
                      <div className="text-xs text-muted-foreground truncate">
                        {c.lastMessage.direction === 'out' ? '↩ ' : ''}
                        {c.lastMessage.content?.slice(0, 60) ??
                          `(${c.lastMessage.content_type})`}
                      </div>
                      <div className="flex items-center gap-2 mt-1 flex-wrap">
                        <StatusDot status={c.status} />
                        {c.hasFlag && <span className="text-[10px]">🚩</span>}
                        {(c.user.tags ?? []).slice(0, 2).map((t) => (
                          <span
                            key={t}
                            className="text-[9px] uppercase tracking-widest font-mono px-1 py-0.5 rounded bg-bronze/10 text-bronze"
                          >
                            {t}
                          </span>
                        ))}
                        {c.inLast24h > 0 && (
                          <span className="text-[10px] font-mono text-muted-foreground ml-auto">
                            ↓{c.inLast24h} ↑{c.outLast24h}
                          </span>
                        )}
                      </div>
                    </div>
                  </Link>
                </li>
              ))
            )}
          </ul>
        </div>

        {/* === Centro: thread === */}
        <div className="flex flex-col content-card overflow-hidden">
          {selectedUser ? (
            <ConversationThread user={selectedUser} thread={thread} />
          ) : (
            <div className="flex-1 flex items-center justify-center text-sm text-muted-foreground">
              <div className="text-center">
                <MessageSquare className="h-8 w-8 mx-auto mb-2 text-muted-foreground/30" />
                Selecione uma conversa
              </div>
            </div>
          )}
        </div>

        {/* === Direita: sidebar === */}
        {selectedUser && (
          <ConversationSidebar
            user={selectedUser}
            progress={userExtras.progress}
            profile={userExtras.profile}
            totalCost={userExtras.totalCost}
            totalMessages={userExtras.totalMessages}
          />
        )}
      </div>
    </div>
  )
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
function FilterChip({
  href,
  label,
  active,
  count,
  tone,
}: {
  href: string
  label: string
  active: boolean
  count: number
  tone?: 'moss' | 'rose'
}) {
  return (
    <Link
      href={href}
      className={`px-2.5 py-1.5 text-[11px] font-medium rounded text-center transition-colors ${
        active
          ? 'bg-foreground text-background'
          : 'text-muted-foreground hover:bg-muted hover:text-foreground'
      }`}
    >
      <span>{label}</span>
      <span
        className={`ml-1.5 text-[10px] font-mono ${
          active
            ? 'opacity-70'
            : tone === 'moss'
              ? 'text-moss-600'
              : tone === 'rose'
                ? 'text-rose-500'
                : 'text-muted-foreground/70'
        }`}
      >
        {count}
      </span>
    </Link>
  )
}

function StatusDot({ status }: { status: ConversationSummary['status'] }) {
  const tone = {
    paused: 'bg-amber-700',
    live: 'bg-moss-500',
    recent: 'bg-amber-400',
    cooling: 'bg-amber-600',
    silent: 'bg-muted-foreground/30',
  }[status]
  const label = {
    paused: '💤 pausada',
    live: 'live',
    recent: 'recente',
    cooling: 'esfriando',
    silent: 'silenciada',
  }[status]
  return (
    <div className="flex items-center gap-1">
      <span className={`inline-block h-1.5 w-1.5 rounded-full ${tone}`} />
      <span className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
        {label}
      </span>
    </div>
  )
}

function Avatar({
  name,
  status,
}: {
  name: string | null
  status: ConversationSummary['status']
}) {
  const initials = (name ?? 'U').slice(0, 2).toUpperCase()
  const ringTone = {
    paused: 'ring-amber-700',
    live: 'ring-moss-500',
    recent: 'ring-amber-400',
    cooling: 'ring-amber-600',
    silent: 'ring-transparent',
  }[status]
  return (
    <div
      className={`shrink-0 h-9 w-9 rounded-full bg-ink-900 text-cream-100 flex items-center justify-center text-xs font-medium ring-2 ring-offset-1 ring-offset-background ${ringTone}`}
    >
      {initials}
    </div>
  )
}

function timeAgoCompact(iso: string): string {
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (diff < 60) return `${diff}s`
  if (diff < 3600) return `${Math.floor(diff / 60)}m`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`
  return `${Math.floor(diff / 86400)}d`
}
