'use client'
import { cn } from '@/lib/utils'
import {
  Activity,
  Bot,
  ChevronDown,
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
import { Button } from '@/components/ui/button'

interface NavItem {
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
    label: 'Visão geral',
    items: [
      { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Mensagens', href: '/messages', icon: MessageSquare },
      { label: 'Avaliações LLM', href: '/evaluations', icon: Sparkles },
    ],
  },
  {
    label: 'Personalização',
    items: [
      { label: 'Persona / Regras', href: '/prompts', icon: FileText },
      { label: 'Playground', href: '/prompts/playground', icon: Bot },
      { label: 'Sub-agentes', href: '/settings/agents', icon: Cpu },
    ],
  },
  {
    label: 'Configuração',
    items: [
      { label: 'API Keys', href: '/settings/api-keys', icon: Key },
      { label: 'Crons', href: '/settings/crons', icon: Clock },
      { label: 'Admins', href: '/settings/admins', icon: Settings },
    ],
  },
  {
    label: 'Operação',
    items: [
      { label: 'Usuários', href: '/users', icon: Users },
      { label: 'Auditoria', href: '/audit', icon: Activity },
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
    <aside className="flex h-screen w-64 flex-col border-r bg-card">
      <div className="flex h-14 items-center border-b px-4">
        <Link href="/dashboard" className="flex items-center gap-2 font-semibold">
          <div className="flex h-8 w-8 items-center justify-center rounded bg-primary/10 text-primary">
            🧠
          </div>
          <div className="flex flex-col leading-tight">
            <span className="text-sm">Agente MPP</span>
            <span className="text-xs text-muted-foreground">CoreHealth</span>
          </div>
        </Link>
      </div>

      <nav className="flex-1 overflow-y-auto p-3 text-sm">
        {NAV.map((group) => (
          <div key={group.label} className="mb-4">
            <div className="mb-1 px-2 text-xs font-medium uppercase text-muted-foreground">
              {group.label}
            </div>
            <ul className="space-y-0.5">
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
                        'flex items-center gap-2 rounded-md px-2 py-1.5 transition',
                        active
                          ? 'bg-primary/10 text-primary font-medium'
                          : 'text-muted-foreground hover:bg-muted hover:text-foreground',
                      )}
                    >
                      <Icon className="h-4 w-4" />
                      {item.label}
                    </Link>
                  </li>
                )
              })}
            </ul>
          </div>
        ))}
      </nav>

      <div className="border-t p-3">
        <div className="flex items-center gap-2 rounded-md px-2 py-1.5">
          <div className="flex h-7 w-7 items-center justify-center rounded-full bg-primary/10 text-primary text-xs">
            {userEmail.charAt(0).toUpperCase()}
          </div>
          <div className="flex-1 truncate text-xs">
            <div className="truncate font-medium">{userEmail}</div>
          </div>
          <Button variant="ghost" size="sm" onClick={signOut} title="Sair">
            <LogOut className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </aside>
  )
}
