'use client'

import {
  AlertTriangle,
  Bot,
  Check,
  ChevronRight,
  Edit3,
  Flag,
  RefreshCw,
  Sparkles,
  User as UserIcon,
} from 'lucide-react'
import { useEffect, useRef, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { formatUSD } from '@/lib/utils'
import {
  flagMessageAction,
  reprocessMessageAction,
  type ReviewFlag,
} from './actions'
import { MediaPreview } from './media-preview'
import { ToolCallBadge } from './tool-call-badge'

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
}

const FLAG_OPTIONS: Array<{ value: ReviewFlag; label: string; icon: React.ReactNode }> = [
  { value: 'hallucination', label: 'Alucinação', icon: <AlertTriangle className="h-3.5 w-3.5" /> },
  { value: 'great_response', label: 'Boa resposta', icon: <Sparkles className="h-3.5 w-3.5" /> },
  { value: 'tone_off', label: 'Tom errado', icon: <Flag className="h-3.5 w-3.5" /> },
  { value: 'wrong_tool', label: 'Tool errada', icon: <Flag className="h-3.5 w-3.5" /> },
  { value: 'too_long', label: 'Muito longa', icon: <Flag className="h-3.5 w-3.5" /> },
  { value: 'needs_review', label: 'Revisar', icon: <Flag className="h-3.5 w-3.5" /> },
]

export function ConversationThread({
  user,
  thread,
}: {
  user: User
  thread: Message[]
}) {
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [user.id])

  // Agrupa por dia
  const grouped: Array<{ date: string; messages: Message[] }> = []
  for (const m of thread) {
    const day = new Date(m.created_at).toLocaleDateString('pt-BR')
    const last = grouped[grouped.length - 1]
    if (last && last.date === day) {
      last.messages.push(m)
    } else {
      grouped.push({ date: day, messages: [m] })
    }
  }

  return (
    <>
      {/* Header do thread */}
      <div className="shrink-0 flex items-center justify-between p-3 border-b border-border bg-muted/30">
        <div className="flex items-center gap-3 min-w-0">
          <div className="shrink-0 h-9 w-9 rounded-full bg-ink-900 text-cream-100 flex items-center justify-center text-xs font-medium">
            {(user.name ?? 'U').slice(0, 2).toUpperCase()}
          </div>
          <div className="min-w-0">
            <div className="font-medium text-sm text-foreground truncate">
              {user.name ?? '(sem nome)'}
            </div>
            <div className="text-[10px] font-mono text-muted-foreground">
              +{user.wpp} · {thread.length} msgs
            </div>
          </div>
        </div>
        <a
          href={`/users/${user.id}`}
          className="text-xs text-muted-foreground hover:text-foreground inline-flex items-center gap-1 underline-offset-2 hover:underline"
        >
          Perfil completo
          <ChevronRight className="h-3 w-3" />
        </a>
      </div>

      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3 bg-background/50">
        {grouped.map((g, i) => (
          <div key={i} className="space-y-3">
            <DateSeparator date={g.date} />
            {g.messages.map((m) => (
              <MessageBubble key={m.id} m={m} userWpp={user.wpp} />
            ))}
          </div>
        ))}
      </div>
    </>
  )
}

function DateSeparator({ date }: { date: string }) {
  const today = new Date().toLocaleDateString('pt-BR')
  const yest = new Date(Date.now() - 86400_000).toLocaleDateString('pt-BR')
  const label = date === today ? 'Hoje' : date === yest ? 'Ontem' : date
  return (
    <div className="flex items-center gap-3 my-2">
      <div className="flex-1 h-px bg-border/60" />
      <span className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
        {label}
      </span>
      <div className="flex-1 h-px bg-border/60" />
    </div>
  )
}

function MessageBubble({ m, userWpp }: { m: Message; userWpp: string }) {
  const isOut = m.direction === 'out'
  const [showFlagMenu, setShowFlagMenu] = useState(false)
  const [pending, startTransition] = useTransition()

  const raw = m.raw_payload as Record<string, unknown> | null
  const imgId = (raw?.image as { id?: string } | undefined)?.id
  const audioId = (raw?.audio as { id?: string } | undefined)?.id

  function applyFlag(flag: ReviewFlag | null) {
    setShowFlagMenu(false)
    startTransition(async () => {
      const r = await flagMessageAction(m.id, flag)
      if (r.error) toast.error(r.error)
      else toast.success(flag ? `Marcada: ${flag}` : 'Flag removida')
    })
  }

  function reprocess() {
    if (!confirm('Forçar reprocessamento desta mensagem? Vai gerar nova resposta.')) return
    startTransition(async () => {
      const r = await reprocessMessageAction(m.id)
      if (r.error) toast.error(r.error)
      else toast.success('Reprocessamento disparado. Aguarde nova OUT no thread.')
    })
  }

  return (
    <div className={`group flex gap-2 ${isOut ? 'justify-end' : 'justify-start'}`}>
      {!isOut && (
        <div className="shrink-0 h-7 w-7 rounded-full bg-ink-900 text-cream-100 flex items-center justify-center mt-1">
          <UserIcon className="h-3 w-3" />
        </div>
      )}
      <div className={`max-w-[70%] ${isOut ? 'order-2' : ''}`}>
        <div
          className={`relative px-4 py-2.5 rounded-2xl text-sm whitespace-pre-wrap break-words ${
            isOut
              ? 'bg-moss-700 text-cream-100 rounded-br-sm'
              : 'bg-muted text-foreground rounded-bl-sm'
          } ${m.review_flag ? 'ring-2 ring-rose-400/50' : ''}`}
        >
          {m.content ?? <span className="italic opacity-60">({m.content_type})</span>}

          {/* Mídia inline */}
          {(imgId || audioId) && (
            <MediaPreview
              userWpp={userWpp}
              mediaId={imgId ?? audioId ?? ''}
              kind={imgId ? 'image' : 'audio'}
              isOut={isOut}
            />
          )}

          {/* Flag visível */}
          {m.review_flag && (
            <div className="mt-2 pt-2 border-t border-cream-100/20 flex items-center gap-1 text-[10px] font-mono uppercase tracking-widest">
              🚩 {m.review_flag}
              {m.review_note && <span className="opacity-70">· {m.review_note}</span>}
            </div>
          )}

          {/* Ações flutuantes */}
          <div
            className={`absolute ${isOut ? '-left-2' : '-right-2'} top-2 opacity-0 group-hover:opacity-100 transition-opacity`}
          >
            <div className="flex items-center gap-1">
              {isOut && (
                <button
                  type="button"
                  onClick={() => setShowFlagMenu(!showFlagMenu)}
                  className="h-6 w-6 rounded-full bg-background border border-border shadow-sm flex items-center justify-center hover:bg-muted"
                  title="Marcar pra revisão"
                  disabled={pending}
                >
                  <Flag className="h-3 w-3" />
                </button>
              )}
              {!isOut && (
                <button
                  type="button"
                  onClick={reprocess}
                  className="h-6 w-6 rounded-full bg-background border border-border shadow-sm flex items-center justify-center hover:bg-muted"
                  title="Forçar reprocessamento"
                  disabled={pending}
                >
                  <RefreshCw className={`h-3 w-3 ${pending ? 'animate-spin' : ''}`} />
                </button>
              )}
              {!isOut && m.content && (
                <a
                  href={`/prompts/playground?seed=${encodeURIComponent(m.content.slice(0, 200))}&wpp=${userWpp}`}
                  className="h-6 w-6 rounded-full bg-background border border-border shadow-sm flex items-center justify-center hover:bg-muted"
                  title="Fork to playground"
                >
                  <Edit3 className="h-3 w-3" />
                </a>
              )}
            </div>
          </div>

          {/* Menu de flag */}
          {showFlagMenu && (
            <div
              className={`absolute ${isOut ? 'right-0' : 'left-0'} top-full mt-1 z-10 glass-card p-1.5 min-w-[170px] shadow-xl`}
              onMouseLeave={() => setShowFlagMenu(false)}
            >
              {FLAG_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  type="button"
                  onClick={() => applyFlag(opt.value)}
                  className="w-full flex items-center gap-2 px-2 py-1.5 text-xs hover:bg-muted rounded text-foreground"
                >
                  {opt.icon}
                  {opt.label}
                </button>
              ))}
              {m.review_flag && (
                <button
                  type="button"
                  onClick={() => applyFlag(null)}
                  className="w-full flex items-center gap-2 px-2 py-1.5 text-xs hover:bg-muted rounded text-rose-500 border-t border-border mt-1 pt-2"
                >
                  <Check className="h-3.5 w-3.5" />
                  Limpar flag
                </button>
              )}
            </div>
          )}
        </div>

        {/* Metadata */}
        <div
          className={`flex items-center gap-2 mt-1 text-[10px] font-mono text-muted-foreground tabular-nums flex-wrap ${
            isOut ? 'justify-end' : ''
          }`}
        >
          <span>
            {new Date(m.created_at).toLocaleTimeString('pt-BR', {
              hour: '2-digit',
              minute: '2-digit',
            })}
          </span>
          {m.agent_stage && (
            <span className="text-moss-600 px-1 py-0.5 rounded bg-moss-500/10">
              {m.agent_stage}
            </span>
          )}
          {m.cost_usd != null && Number(m.cost_usd) > 0 && (
            <span>{formatUSD(Number(m.cost_usd), 5)}</span>
          )}
          {m.latency_ms != null && m.latency_ms > 0 && <span>{m.latency_ms}ms</span>}
          {m.prompt_tokens != null && (
            <span>
              {m.prompt_tokens}+{m.completion_tokens}t
            </span>
          )}
        </div>

        {/* Tool calls (apenas em OUT, se houver) */}
        {isOut && m.id && <ToolCallBadge messageId={m.id} userId={m.user_id} createdAt={m.created_at} />}
      </div>
      {isOut && (
        <div className="shrink-0 h-7 w-7 rounded-full bg-moss-700 text-cream-100 flex items-center justify-center mt-1">
          <Bot className="h-3 w-3" />
        </div>
      )}
    </div>
  )
}
