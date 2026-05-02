'use client'

import { useRouter } from 'next/navigation'
import { useEffect, useRef, useState } from 'react'

/**
 * Atalhos globais estilo Vim/Linear:
 *   g d  → /dashboard
 *   g c  → /messages (conversas)
 *   g p  → /users (pacientes)
 *   g r  → /prompts (regras)
 *   g $  → /crescimento/receita
 *   g k  → /crescimento/conquistas
 *   g s  → /settings/agents
 *   ?    → toggle help overlay
 */
const SHORTCUTS: Array<{ keys: string; path: string; label: string }> = [
  { keys: 'd', path: '/dashboard', label: 'dashboard' },
  { keys: 'c', path: '/messages', label: 'conversas' },
  { keys: 'p', path: '/users', label: 'pacientes' },
  { keys: 'r', path: '/prompts', label: 'regras' },
  { keys: '$', path: '/crescimento/receita', label: 'receita' },
  { keys: 'k', path: '/crescimento/conquistas', label: 'conquistas' },
  { keys: 'f', path: '/crescimento/funil', label: 'funil' },
  { keys: 's', path: '/settings/agents', label: 'sub-agentes' },
  { keys: 'a', path: '/audit', label: 'auditoria' },
]

const PATH_BY_KEY: Record<string, string> = Object.fromEntries(
  SHORTCUTS.map((s) => [s.keys, s.path]),
)

export function KeyboardShortcuts() {
  const router = useRouter()
  const [helpOpen, setHelpOpen] = useState(false)
  const prefix = useRef<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const isInputFocused = () => {
      const t = document.activeElement
      if (!t) return false
      const tag = t.tagName.toLowerCase()
      return (
        tag === 'input' ||
        tag === 'textarea' ||
        tag === 'select' ||
        (t as HTMLElement).isContentEditable
      )
    }

    const onKey = (e: KeyboardEvent) => {
      if (isInputFocused()) return
      if (e.metaKey || e.ctrlKey || e.altKey) return

      if (e.key === '?') {
        e.preventDefault()
        setHelpOpen((v) => !v)
        return
      }
      if (e.key === 'Escape' && helpOpen) {
        setHelpOpen(false)
        return
      }

      if (e.key === 'g') {
        prefix.current = 'g'
        if (timer.current) clearTimeout(timer.current)
        timer.current = setTimeout(() => {
          prefix.current = null
        }, 800)
        return
      }

      if (prefix.current === 'g') {
        const path = PATH_BY_KEY[e.key]
        if (path) {
          e.preventDefault()
          router.push(path)
        }
        prefix.current = null
        if (timer.current) clearTimeout(timer.current)
      }
    }

    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [router, helpOpen])

  if (!helpOpen) return null

  return (
    <div
      className="fixed bottom-6 right-6 z-[200] glass-card p-4 max-w-xs shadow-2xl"
      onClick={() => setHelpOpen(false)}
    >
      <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground mb-2">
        Atalhos
      </div>
      <div className="text-sm space-y-1">
        <div className="flex items-center gap-2">
          <kbd className="bg-muted/50 px-1.5 py-0.5 rounded text-xs font-mono">⌘K</kbd>
          <span>command palette</span>
        </div>
        {SHORTCUTS.map((s) => (
          <div key={s.keys} className="flex items-center gap-2">
            <kbd className="bg-muted/50 px-1.5 py-0.5 rounded text-xs font-mono">g {s.keys}</kbd>
            <span>{s.label}</span>
          </div>
        ))}
      </div>
      <div className="mt-3 text-[10px] font-mono text-muted-foreground/60">
        Clique fora ou ESC pra fechar.
      </div>
    </div>
  )
}
