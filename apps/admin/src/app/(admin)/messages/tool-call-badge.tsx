'use client'

import { ChevronDown, ChevronRight, Wrench } from 'lucide-react'
import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface ToolCall {
  id: string
  tool_name: string
  arguments: Record<string, unknown> | null
  result: Record<string, unknown> | null
  duration_ms: number
  success: boolean
  error: string | null
  created_at: string
}

/**
 * Badge inline mostrando tools chamadas no turno.
 * Busca tools_audit por user_id + janela [-60s, +5s] do created_at da OUT.
 * Só RENDERIZA se houver tools chamadas — evita ruído visual em
 * msgs de engagement (que nunca chamam tools).
 */
export function ToolCallBadge({
  userId,
  createdAt,
}: {
  messageId: string
  userId: string
  createdAt: string
}) {
  const [open, setOpen] = useState(false)
  const [calls, setCalls] = useState<ToolCall[] | null>(null)

  // Fetch ao montar — assim sabemos se há calls antes de renderizar.
  useEffect(() => {
    let cancelled = false
    const supabase = createClient()
    const before = new Date(new Date(createdAt).getTime() - 60_000).toISOString()
    const after = new Date(new Date(createdAt).getTime() + 5_000).toISOString()
    supabase
      .from('tools_audit')
      .select('*')
      .eq('user_id', userId)
      .gte('created_at', before)
      .lte('created_at', after)
      .order('created_at', { ascending: true })
      .then(({ data }) => {
        if (!cancelled) setCalls((data ?? []) as ToolCall[])
      })
    return () => {
      cancelled = true
    }
  }, [userId, createdAt])

  // Antes de saber: render nada (não pisca).
  // Depois de saber: só renderiza se houver calls.
  if (!calls || calls.length === 0) return null

  return (
    <div className="mt-1">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground hover:text-foreground inline-flex items-center gap-1"
      >
        {open ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
        <Wrench className="h-3 w-3" />
        {calls.length} tool{calls.length === 1 ? '' : 's'}
      </button>

      {open && (
        <div className="mt-1 space-y-1 max-w-[380px]">
          {calls.map((c) => (
            <div
              key={c.id}
              className={`glass-subtle p-2 text-[10px] font-mono space-y-1 border-l-2 ${
                c.success ? 'border-moss-500/60' : 'border-rose-500/60'
              }`}
            >
              <div className="flex items-center justify-between gap-2">
                <span className="text-foreground">{c.tool_name}</span>
                <span className="text-muted-foreground">
                  {c.success ? '✓' : '✗'} {c.duration_ms}ms
                </span>
              </div>
              {c.arguments && Object.keys(c.arguments).length > 0 && (
                <pre className="text-[9px] text-muted-foreground whitespace-pre-wrap break-all">
                  args: {JSON.stringify(c.arguments)}
                </pre>
              )}
              {c.error && <div className="text-rose-500 text-[9px]">err: {c.error}</div>}
              {c.result && c.success && (
                <pre className="text-[9px] text-muted-foreground/70 whitespace-pre-wrap break-all line-clamp-2">
                  → {JSON.stringify(c.result).slice(0, 120)}
                </pre>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
