'use client'

import { Search, X } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

interface Hit {
  id: string
  user_id: string
  user_name: string | null
  user_wpp: string
  direction: string
  content: string
  agent_stage: string | null
  created_at: string
  rank: number
}

export function SearchTrigger() {
  const [open, setOpen] = useState(false)

  // Atalho `/` abre busca
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (
        e.key === '/' &&
        !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)
      ) {
        e.preventDefault()
        setOpen(true)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  return (
    <>
      <Button size="sm" variant="outline" onClick={() => setOpen(true)} className="h-7 text-xs">
        <Search className="h-3 w-3 mr-1" />
        Buscar
        <kbd className="ml-2 text-[10px] font-mono bg-muted/50 px-1 py-0.5 rounded">/</kbd>
      </Button>
      {open && <SearchModal onClose={() => setOpen(false)} />}
    </>
  )
}

function SearchModal({ onClose }: { onClose: () => void }) {
  const router = useRouter()
  const [query, setQuery] = useState('')
  const [hits, setHits] = useState<Hit[]>([])
  const [loading, setLoading] = useState(false)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    if (!query || query.length < 2) {
      setHits([])
      return
    }
    setLoading(true)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(async () => {
      const supabase = createClient()
      const { data } = await supabase.rpc(
        'search_messages' as 'search_food_trgm',
        { p_query: query, p_limit: 20 } as Record<string, unknown> as never,
      )
      setHits((data ?? []) as unknown as Hit[])
      setLoading(false)
    }, 250)
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [query])

  function go(hit: Hit) {
    onClose()
    router.push(`/messages?user=${hit.user_id}`)
  }

  return (
    <div
      className="fixed inset-0 z-[100] bg-background/60 backdrop-blur-sm flex items-start justify-center pt-[10vh] px-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-2xl glass-card overflow-hidden shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 border-b border-border px-4 py-3">
          <Search className="h-4 w-4 text-muted-foreground shrink-0" />
          <Input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder='Buscar em conversas... (ex: "almocei pão", "ansiedade")'
            className="border-0 shadow-none focus-visible:ring-0 px-0 text-sm"
          />
          <button
            type="button"
            onClick={onClose}
            className="h-7 w-7 rounded hover:bg-muted flex items-center justify-center"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="max-h-[60vh] overflow-y-auto">
          {loading && (
            <div className="p-6 text-center text-sm text-muted-foreground">buscando…</div>
          )}
          {!loading && query.length < 2 && (
            <div className="p-6 text-center text-sm text-muted-foreground">
              Digite pelo menos 2 caracteres
            </div>
          )}
          {!loading && query.length >= 2 && hits.length === 0 && (
            <div className="p-6 text-center text-sm text-muted-foreground">
              Sem resultados pra &quot;{query}&quot;
            </div>
          )}
          {hits.map((h) => (
            <button
              key={h.id}
              type="button"
              onClick={() => go(h)}
              className="w-full text-left p-3 border-b border-border/40 hover:bg-muted/40 transition-colors"
            >
              <div className="flex items-center gap-2 mb-1">
                <span
                  className={`text-[10px] font-mono uppercase tracking-widest px-1.5 py-0.5 rounded ${
                    h.direction === 'in'
                      ? 'bg-ink-900/10 text-foreground'
                      : 'bg-moss-500/10 text-moss-700'
                  }`}
                >
                  {h.direction === 'in' ? '← user' : '→ agente'}
                </span>
                <span className="text-sm font-medium text-foreground">
                  {h.user_name ?? h.user_wpp}
                </span>
                {h.agent_stage && (
                  <span className="text-[10px] font-mono text-muted-foreground">
                    {h.agent_stage}
                  </span>
                )}
                <span className="ml-auto text-[10px] font-mono text-muted-foreground">
                  {new Date(h.created_at).toLocaleString('pt-BR')}
                </span>
              </div>
              <p className="text-xs text-foreground/80 line-clamp-2">
                {highlightMatch(h.content, query)}
              </p>
            </button>
          ))}
        </div>

        <div className="border-t border-border px-3 py-2 flex items-center justify-between text-[10px] font-mono text-muted-foreground/70">
          <span>
            <kbd className="bg-muted/50 px-1 py-0.5 rounded">/</kbd> abrir ·{' '}
            <kbd className="bg-muted/50 px-1 py-0.5 rounded">esc</kbd> fechar
          </span>
          {hits.length > 0 && <span>{hits.length} resultados</span>}
        </div>
      </div>
    </div>
  )
}

function highlightMatch(text: string, query: string): React.ReactNode {
  if (!query) return text
  const idx = text.toLowerCase().indexOf(query.toLowerCase())
  if (idx === -1) return text.slice(0, 200)
  const start = Math.max(0, idx - 60)
  const end = Math.min(text.length, idx + query.length + 60)
  const before = text.slice(start, idx)
  const match = text.slice(idx, idx + query.length)
  const after = text.slice(idx + query.length, end)
  return (
    <>
      {start > 0 && '…'}
      {before}
      <mark className="bg-amber-500/30 rounded px-0.5">{match}</mark>
      {after}
      {end < text.length && '…'}
    </>
  )
}
