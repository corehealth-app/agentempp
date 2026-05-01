'use client'
import { cn } from '@/lib/utils'
import {
  Activity,
  Bot,
  Clock,
  Cpu,
  FileText,
  Key,
  LayoutDashboard,
  LogOut,
  MessageSquare,
  Settings,
  Sparkles,
  Users,
} from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

interface NavItem {
  num: string
  label: string
  href: string
  icon: React.ComponentType<{ className?: string }>
}

interface NavGroup {
  label: string
  items: NavItem[]
}

const NAV: NavGroup[] = [
  {
    label: 'Visão',
    items: [
      { num: '01', label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { num: '02', label: 'Mensagens', href: '/messages', icon: MessageSquare },
      { num: '03', label: 'Avaliações LLM', href: '/evaluations', icon: Sparkles },
    ],
  },
  {
    label: 'Persona',
    items: [
      { num: '04', label: 'Regras', href: '/prompts', icon: FileText },
      { num: '05', label: 'Playground', href: '/prompts/playground', icon: Bot },
      { num: '06', label: 'Sub-agentes', href: '/settings/agents', icon: Cpu },
    ],
  },
  {
    label: 'Sistema',
    items: [
      { num: '07', label: 'API Keys', href: '/settings/api-keys', icon: Key },
      { num: '08', label: 'Crons', href: '/settings/crons', icon: Clock },
      { num: '09', label: 'Admins', href: '/settings/admins', icon: Settings },
    ],
  },
  {
    label: 'Operação',
    items: [
      { num: '10', label: 'Usuários', href: '/users', icon: Users },
      { num: '11', label: 'Auditoria', href: '/audit', icon: Activity },
    ],
  },
]

export function Sidebar({ userEmail }: { userEmail: string }) {
  const pathname = usePathname()
  const supabase = createClient()

  async function signOut() {
    await supabase.auth.signOut()
    window.location.href = '/login'
  }

  return (
    <aside className="flex h-screen w-72 shrink-0 flex-col border-r border-border bg-cream-50">
      {/* Logo */}
      <div className="flex h-16 items-center border-b border-border px-6">
        <Link href="/dashboard" className="flex items-center gap-3 group">
          <div className="h-9 w-9 rounded-sm bg-ink-900 text-cream-100 flex items-center justify-center font-display text-lg font-medium transition-transform group-hover:rotate-3">
            M
          </div>
          <div className="flex flex-col leading-none">
            <span className="font-display text-base text-ink-900 tracking-tight">
              Agente MPP
            </span>
            <span className="text-[10px] tracking-widest uppercase text-ink-500 font-mono mt-0.5">
              CoreHealth
            </span>
          </div>
        </Link>
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto px-4 py-6">
        {NAV.map((group, gIdx) => (
          <div key={group.label} className={cn('mb-7', gIdx === 0 && 'mt-0')}>
            <div className="px-3 mb-2 flex items-center justify-between">
              <span className="section-eyebrow">{group.label}</span>
              <span className="font-mono text-[10px] text-ink-400">
                {String(gIdx + 1).padStart(2, '0')}
              </span>
            </div>
            <ul className="space-y-px">
              {group.items.map((item) => {
                const active =
                  pathname === item.href ||
                  (item.href !== '/dashboard' && pathname.startsWith(item.href))
                const Icon = item.icon
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      className={cn(
                        'group flex items-center gap-3 px-3 py-2 rounded-sm text-sm transition-all relative',
                        active
                          ? 'bg-ink-900 text-cream-100'
                          : 'text-ink-700 hover:bg-cream-200',
                      )}
                    >
                      <span
                        className={cn(
                          'font-mono text-[10px] tabular-nums w-5 transition-colors',
                          active ? 'text-cream-100/50' : 'text-ink-400',
                        )}
                      >
                        {item.num}
                      </span>
                      <Icon
                        className={cn(
                          'h-3.5 w-3.5 transition-transform',
                          active ? 'text-cream-100' : 'text-ink-500',
                        )}
                      />
                      <span className={cn('flex-1', active ? 'font-medium' : '')}>
                        {item.label}
                      </span>
                      {active && (
                        <span className="h-1 w-1 rounded-full bg-moss-400 shrink-0" />
                      )}
                    </Link>
                  </li>
                )
              })}
            </ul>
          </div>
        ))}
      </nav>

      {/* User footer */}
      <div className="border-t border-border p-4">
        <div className="flex items-center gap-3 group">
          <div className="h-8 w-8 rounded-sm bg-moss-700 text-cream-100 flex items-center justify-center text-xs font-display font-medium">
            {userEmail.charAt(0).toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-xs font-medium text-ink-900 truncate">{userEmail}</div>
            <div className="text-[10px] font-mono uppercase tracking-widest text-ink-500">
              admin
            </div>
          </div>
          <button
            onClick={signOut}
            className="h-8 w-8 rounded-sm flex items-center justify-center text-ink-500 hover:text-ink-900 hover:bg-cream-200 transition-colors focus-ring"
            title="Sair"
          >
            <LogOut className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
    </aside>
  )
}
