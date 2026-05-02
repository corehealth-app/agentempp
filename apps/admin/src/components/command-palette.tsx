'use client'

import { Command } from 'cmdk'
import {
  Activity,
  Bot,
  Clock,
  CreditCard,
  FileText,
  Key,
  LayoutDashboard,
  MessageSquare,
  Search,
  Settings,
  Sparkles,
  Trophy,
  TrendingUp,
  UserCog,
  Users,
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useCallback, useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface UserHit {
  id: string
  name: string | null
  wpp: string
}

const NAV_ITEMS = [
  { label: 'Hoje (dashboard)', href: '/dashboard', icon: LayoutDashboard, group: 'Operação' },
  { label: 'Conversas', href: '/messages', icon: MessageSquare, group: 'Operação' },
  { label: 'Pacientes', href: '/users', icon: Users, group: 'Operação' },
  { label: 'Conquistas', href: '/crescimento/conquistas', icon: Trophy, group: 'Crescimento' },
  { label: 'Funil & Cohorts', href: '/crescimento/funil', icon: TrendingUp, group: 'Crescimento' },
  { label: 'Receita', href: '/crescimento/receita', icon: CreditCard, group: 'Crescimento' },
  { label: 'Regras (prompts)', href: '/prompts', icon: FileText, group: 'Agente' },
  { label: 'Playground', href: '/prompts/playground', icon: Bot, group: 'Agente' },
  { label: 'Sub-agentes', href: '/settings/agents', icon: Settings, group: 'Agente' },
  { label: 'Avaliações LLM', href: '/evaluations', icon: Sparkles, group: 'Agente' },
  { label: 'Auditoria de tools', href: '/audit', icon: Activity, group: 'Agente' },
  { label: 'API Keys', href: '/settings/api-keys', icon: Key, group: 'Configuração' },
  { label: 'Stripe', href: '/settings/stripe', icon: CreditCard, group: 'Configuração' },
  { label: 'Crons', href: '/settings/crons', icon: Clock, group: 'Configuração' },
  { label: 'Admins', href: '/settings/admins', icon: UserCog, group: 'Configuração' },
]

export function CommandPalette() {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [users, setUsers] = useState<UserHit[]>([])
  const [searching, setSearching] = useState(false)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Atalhos: Cmd/Ctrl+K abre/fecha
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.key === 'k' || e.key === 'K') && (e.metaKey || e.ctrlKey)) {
        e.preventDefault()
        setOpen((v) => !v)
      }
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // Limpa query ao abrir
  useEffect(() => {
    if (open) {
      setQuery('')
      setUsers([])
    }
  }, [open])

  // Search de pacientes (debounced 200ms)
  const searchUsers = useCallback(async (q: string) => {
    if (!q || q.length < 2) {
      setUsers([])
      return
    }
    setSearching(true)
    const supabase = createClient()
    const { data } = await supabase
      .from('users')
      .select('id, name, wpp')
      .or(`name.ilike.%${q}%,wpp.ilike.%${q}%`)
      .limit(8)
    setUsers((data ?? []) as UserHit[])
    setSearching(false)
  }, [])

  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => searchUsers(query), 200)
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [query, searchUsers])

  const go = (href: string) => {
    setOpen(false)
    router.push(href)
  }

  if (!open) return null

  // Agrupa nav items
  const grouped: Record<string, typeof NAV_ITEMS> = {}
  for (const item of NAV_ITEMS) {
    grouped[item.group] = grouped[item.group] ?? []
    grouped[item.group]!.push(item)
  }

  return (
    <div
      className="fixed inset-0 z-[100] bg-background/60 backdrop-blur-sm flex items-start justify-center pt-[12vh] px-4"
      onClick={() => setOpen(false)}
    >
      <Command
        className="w-full max-w-xl glass-card overflow-hidden shadow-2xl"
        onClick={(e) => e.stopPropagation()}
        loop
        label="Command palette"
      >
        <div className="flex items-center gap-2 border-b border-border px-4 py-3">
          <Search className="h-4 w-4 text-muted-foreground shrink-0" />
          <Command.Input
            value={query}
            onValueChange={setQuery}
            placeholder="Buscar pacientes, ir pra página..."
            className="flex-1 bg-transparent outline-none text-sm placeholder:text-muted-foreground"
            autoFocus
          />
          <kbd className="text-[10px] font-mono text-muted-foreground/70 bg-muted/50 px-1.5 py-0.5 rounded">
            esc
          </kbd>
        </div>

        <Command.List className="max-h-[60vh] overflow-y-auto p-2">
          <Command.Empty className="py-8 text-center text-sm text-muted-foreground">
            {searching ? 'Buscando...' : 'Sem resultados.'}
          </Command.Empty>

          {users.length > 0 && (
            <Command.Group
              heading="Pacientes"
              className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground/70 px-2 py-1"
            >
              {users.map((u) => (
                <Command.Item
                  key={u.id}
                  value={`paciente ${u.name ?? ''} ${u.wpp}`}
                  onSelect={() => go(`/users/${u.id}`)}
                  className="flex items-center gap-3 px-2 py-2 rounded text-sm cursor-pointer aria-selected:bg-accent aria-selected:text-foreground"
                >
                  <div className="h-7 w-7 shrink-0 rounded-full bg-ink-900 text-cream-100 flex items-center justify-center text-[10px] font-medium">
                    {(u.name ?? 'U').slice(0, 2).toUpperCase()}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-foreground truncate">{u.name ?? '(sem nome)'}</div>
                    <div className="text-[11px] font-mono text-muted-foreground truncate">
                      +{u.wpp}
                    </div>
                  </div>
                </Command.Item>
              ))}
            </Command.Group>
          )}

          {Object.entries(grouped).map(([group, items]) => (
            <Command.Group
              key={group}
              heading={group}
              className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground/70 px-2 py-1 mt-2"
            >
              {items.map((item) => {
                const Icon = item.icon
                return (
                  <Command.Item
                    key={item.href}
                    value={`${group} ${item.label}`}
                    onSelect={() => go(item.href)}
                    className="flex items-center gap-3 px-2 py-2 rounded text-sm cursor-pointer aria-selected:bg-accent aria-selected:text-foreground"
                  >
                    <Icon className="h-4 w-4 shrink-0 text-muted-foreground" />
                    <span className="flex-1">{item.label}</span>
                    <span className="text-[10px] font-mono text-muted-foreground/60">
                      {item.href}
                    </span>
                  </Command.Item>
                )
              })}
            </Command.Group>
          ))}
        </Command.List>

        <div className="border-t border-border px-3 py-2 flex items-center justify-between text-[10px] font-mono text-muted-foreground/70">
          <span>
            <kbd className="bg-muted/50 px-1 py-0.5 rounded">↑↓</kbd> navegar ·{' '}
            <kbd className="bg-muted/50 px-1 py-0.5 rounded">↵</kbd> selecionar
          </span>
          <span>
            <kbd className="bg-muted/50 px-1 py-0.5 rounded">⌘K</kbd> toggle
          </span>
        </div>
      </Command>
    </div>
  )
}
