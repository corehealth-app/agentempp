import Link from 'next/link'
import { Bot, ChevronRight, MessageSquare, User as UserIcon } from 'lucide-react'
import { PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatUSD } from '@/lib/utils'
import { MessagesRealtimeListener } from './realtime-listener'

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
}

interface User {
  id: string
  name: string | null
  wpp: string
}

interface ConversationSummary {
  user: User
  lastMessage: Message
  inLast24h: number
  outLast24h: number
  lastErrorAgo: number | null // minutos
  status: 'live' | 'recent' | 'cooling' | 'silent'
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

  // Pega últimas 200 msgs e agrega por user
  const { data: rawMessages } = await svc
    .from('messages')
    .select(
      'id, user_id, direction, content, content_type, agent_stage, model_used, prompt_tokens, completion_tokens, cost_usd, latency_ms, created_at',
    )
    .order('created_at', { ascending: false })
    .limit(200)
  const messages = (rawMessages ?? []) as Message[]

  const userIds = [...new Set(messages.map((m) => m.user_id))]
  const { data: rawUsers } = await svc
    .from('users')
    .select('id, name, wpp')
    .in('id', userIds.length ? userIds : ['00000000-0000-0000-0000-000000000000'])
  const userMap = new Map<string, User>(
    ((rawUsers ?? []) as User[]).map((u) => [u.id, u]),
  )

  // Agrupa por user (último é o primeiro do array, já ordenado desc)
  const summaries = new Map<string, ConversationSummary>()
  const now = new Date()
  for (const m of messages) {
    const u = userMap.get(m.user_id)
    if (!u) continue
    if (!summaries.has(m.user_id)) {
      const minutesAgo = diffMinutes(now, new Date(m.created_at))
      const status: ConversationSummary['status'] =
        minutesAgo <= 60 ? 'live' :
        minutesAgo <= 24 * 60 ? 'recent' :
        minutesAgo <= 72 * 60 ? 'cooling' : 'silent'
      summaries.set(m.user_id, {
        user: u,
        lastMessage: m,
        inLast24h: 0,
        outLast24h: 0,
        lastErrorAgo: null,
        status,
      })
    }
    const s = summaries.get(m.user_id)!
    const minutesAgo = diffMinutes(now, new Date(m.created_at))
    if (minutesAgo <= 24 * 60) {
      if (m.direction === 'in') s.inLast24h++
      else s.outLast24h++
    }
  }

  let conversations = [...summaries.values()]

  // Filtros
  const filter = params.filter
  if (filter === 'live') conversations = conversations.filter((c) => c.status === 'live')
  if (filter === 'silent') conversations = conversations.filter((c) => c.status === 'silent')
  if (filter === 'cooling') conversations = conversations.filter((c) => c.status === 'cooling')

  // Conversa selecionada
  const selectedUserId = params.user ?? conversations[0]?.user.id
  const thread = selectedUserId
    ? messages.filter((m) => m.user_id === selectedUserId).reverse()
    : []
  const selectedUser = selectedUserId ? userMap.get(selectedUserId) : undefined

  return (
    <div className="space-y-3">
      <MessagesRealtimeListener />
      <PageHeader
        breadcrumbs={[{ label: 'Operação' }, { label: 'Conversas' }]}
        title="Conversas"
        description={
          <span className="inline-flex items-center gap-2">
            Inbox unificada por paciente. Últimas 200 mensagens.
            <span className="inline-flex items-center gap-1 text-[10px] font-mono text-moss-700">
              <span className="relative inline-block h-1.5 w-1.5 rounded-full bg-moss-500">
                <span className="absolute inset-0 rounded-full animate-ping opacity-60 bg-moss-500" />
              </span>
              live
            </span>
          </span>
        }
      />

      <div className="grid gap-3 lg:grid-cols-[340px_1fr] min-h-[600px]">
        {/* === Painel esquerdo: lista === */}
        <div className="flex flex-col content-card overflow-hidden">
          {/* Filtros */}
          <div className="flex gap-1 p-2 border-b border-border bg-muted/30">
            <FilterChip href="/messages" label="Todas" active={!filter} count={summaries.size} />
            <FilterChip
              href="/messages?filter=live"
              label="Ativas"
              active={filter === 'live'}
              count={[...summaries.values()].filter((c) => c.status === 'live').length}
              tone="moss"
            />
            <FilterChip
              href="/messages?filter=silent"
              label="Silenciados"
              active={filter === 'silent'}
              count={[...summaries.values()].filter((c) => c.status === 'silent').length}
              tone="rose"
            />
          </div>

          <ul className="flex-1 overflow-y-auto divide-y divide-border/40">
            {conversations.length === 0 ? (
              <li className="p-6 text-sm text-muted-foreground text-center">
                Nenhuma conversa neste filtro.
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
                        {c.lastMessage.content?.slice(0, 60) ?? `(${c.lastMessage.content_type})`}
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        <StatusDot status={c.status} />
                        {c.inLast24h > 0 && (
                          <span className="text-[10px] font-mono text-muted-foreground">
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

        {/* === Painel direito: thread === */}
        <div className="flex flex-col content-card overflow-hidden">
          {selectedUser ? (
            <>
              {/* Header do thread */}
              <div className="flex items-center justify-between p-3 border-b border-border bg-muted/30">
                <div className="flex items-center gap-3">
                  <Avatar name={selectedUser.name} status="live" />
                  <div>
                    <div className="font-medium text-sm text-foreground">
                      {selectedUser.name ?? '(sem nome)'}
                    </div>
                    <div className="text-[10px] font-mono text-muted-foreground">
                      +{selectedUser.wpp} · {thread.length} msg
                    </div>
                  </div>
                </div>
                <Link
                  href={`/users/${selectedUser.id}`}
                  className="text-xs text-muted-foreground hover:text-foreground inline-flex items-center gap-1 underline-offset-2 hover:underline"
                >
                  Ver perfil
                  <ChevronRight className="h-3 w-3" />
                </Link>
              </div>

              <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-background/50">
                {thread.map((m) => (
                  <MessageBubble key={m.id} m={m} />
                ))}
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center text-sm text-muted-foreground">
              <div className="text-center">
                <MessageSquare className="h-8 w-8 mx-auto mb-2 text-muted-foreground/30" />
                Selecione uma conversa à esquerda
              </div>
            </div>
          )}
        </div>
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
      className={`flex-1 px-2.5 py-1.5 text-[11px] font-medium rounded text-center transition-colors ${
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
    live: 'bg-moss-500',
    recent: 'bg-amber-400',
    cooling: 'bg-amber-600',
    silent: 'bg-muted-foreground/30',
  }[status]
  const label = {
    live: 'ativa',
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

function Avatar({ name, status }: { name: string | null; status: ConversationSummary['status'] }) {
  const initials = (name ?? 'U').slice(0, 2).toUpperCase()
  const ringTone = {
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

function MessageBubble({ m }: { m: Message }) {
  const isOut = m.direction === 'out'
  return (
    <div className={`flex gap-2 ${isOut ? 'justify-end' : 'justify-start'}`}>
      {!isOut && (
        <div className="shrink-0 h-7 w-7 rounded-full bg-ink-900 text-cream-100 flex items-center justify-center mt-1">
          <UserIcon className="h-3 w-3" />
        </div>
      )}
      <div className={`max-w-[70%] ${isOut ? 'order-2' : ''}`}>
        <div
          className={`px-4 py-2.5 rounded-2xl text-sm whitespace-pre-wrap break-words ${
            isOut
              ? 'bg-moss-700 text-cream-100 rounded-br-sm'
              : 'bg-muted text-foreground rounded-bl-sm'
          }`}
        >
          {m.content ?? <span className="italic opacity-60">({m.content_type})</span>}
        </div>
        <div
          className={`flex items-center gap-2 mt-1 text-[10px] font-mono text-muted-foreground tabular-nums ${
            isOut ? 'justify-end' : ''
          }`}
        >
          <span>{new Date(m.created_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</span>
          {m.agent_stage && <span className="text-moss-600">{m.agent_stage}</span>}
          {m.cost_usd != null && Number(m.cost_usd) > 0 && (
            <span>{formatUSD(Number(m.cost_usd), 5)}</span>
          )}
          {m.latency_ms != null && <span>{m.latency_ms}ms</span>}
        </div>
      </div>
      {isOut && (
        <div className="shrink-0 h-7 w-7 rounded-full bg-moss-700 text-cream-100 flex items-center justify-center mt-1">
          <Bot className="h-3 w-3" />
        </div>
      )}
    </div>
  )
}
