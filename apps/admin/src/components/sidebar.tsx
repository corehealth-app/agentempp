'use client'
import { cn } from '@/lib/utils'
import {
  Activity,
  Bot,
  ChevronLeft,
  ChevronRight,
  Clock,
  Cpu,
  FileText,
  Key,
  LayoutDashboard,
  LogOut,
  Menu,
  MessageSquare,
  Settings,
  Sparkles,
  UserCog,
  Users,
  X,
} from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

interface NavItem {
  label: string
  href: string
  icon: React.ComponentType<{ className?: string }>
  badge?: number
}

interface NavCategory {
  label: string
  items: NavItem[]
}

const NAV_CATEGORIES: NavCategory[] = [
  {
    label: 'PRINCIPAL',
    items: [
      { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Mensagens', href: '/messages', icon: MessageSquare },
      { label: 'Avaliações LLM', href: '/evaluations', icon: Sparkles },
    ],
  },
  {
    label: 'PERSONA',
    items: [
      { label: 'Regras', href: '/prompts', icon: FileText },
      { label: 'Playground', href: '/prompts/playground', icon: Bot },
      { label: 'Sub-agentes', href: '/settings/agents', icon: Cpu },
    ],
  },
  {
    label: 'CONFIGURAÇÃO',
    items: [
      { label: 'API Keys', href: '/settings/api-keys', icon: Key },
      { label: 'Crons', href: '/settings/crons', icon: Clock },
      { label: 'Admins', href: '/settings/admins', icon: UserCog },
    ],
  },
  {
    label: 'OPERAÇÃO',
    items: [
      { label: 'Usuários', href: '/users', icon: Users },
      { label: 'Auditoria', href: '/audit', icon: Activity },
    ],
  },
]

export function Sidebar({ userEmail, userName }: { userEmail: string; userName?: string }) {
  const pathname = usePathname()
  const supabase = createClient()
  const [collapsed, setCollapsed] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)

  async function signOut() {
    await supabase.auth.signOut()
    window.location.href = '/login'
  }

  const initials = (userName || userEmail || 'A').slice(0, 2).toUpperCase()

  const navContent = (isCollapsed: boolean) => (
    <div className="flex flex-col h-full">
      {/* Logo header */}
      <div
        className={cn(
          'flex items-center justify-between px-4 py-3 border-b border-sidebar-border',
          isCollapsed && 'justify-center px-2',
        )}
      >
        <Link
          href="/dashboard"
          className={cn(
            'glass-card flex items-center gap-2.5 transition',
            isCollapsed ? 'p-2' : 'px-3 py-2 flex-1 min-w-0',
          )}
        >
          <div className="h-7 w-7 shrink-0 rounded-md bg-ink-900 dark:bg-moss-500 text-cream-100 flex items-center justify-center font-display text-base font-medium">
            M
          </div>
          {!isCollapsed && (
            <div className="flex flex-col leading-none min-w-0">
              <span className="font-display text-sm tracking-tight text-foreground truncate">
                Agente MPP
              </span>
              <span className="text-[9px] tracking-widest uppercase text-muted-foreground font-mono mt-0.5">
                CoreHealth
              </span>
            </div>
          )}
        </Link>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-3 flex flex-col gap-1 overflow-y-auto nav-scroll">
        {NAV_CATEGORIES.map((category) => (
          <div key={category.label} className="mb-1">
            {!isCollapsed && (
              <div className="px-3.5 pt-3 pb-1.5 text-[10px] font-mono font-semibold uppercase tracking-widest text-muted-foreground/70">
                {category.label}
              </div>
            )}
            {isCollapsed && <div className="my-1.5 mx-2 border-t border-sidebar-border/40" />}
            <div className="flex flex-col gap-0.5">
              {category.items.map((item) => {
                const active =
                  pathname === item.href ||
                  (item.href !== '/dashboard' && pathname.startsWith(item.href))
                const Icon = item.icon
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    aria-current={active ? 'page' : undefined}
                    onClick={() => setMobileOpen(false)}
                    className={cn(
                      'nav-card-glass flex items-center gap-2.5 px-3.5 py-2.5 text-sm relative',
                      active && 'nav-card-active',
                      isCollapsed && 'justify-center px-2',
                    )}
                    title={isCollapsed ? item.label : undefined}
                  >
                    <Icon className="h-4 w-4 shrink-0" />
                    {!isCollapsed && (
                      <>
                        <span className="flex-1 truncate">{item.label}</span>
                        {item.badge && item.badge > 0 && (
                          <span className="ml-auto h-5 min-w-[20px] px-1.5 text-[10px] font-mono rounded-full bg-destructive text-destructive-foreground flex items-center justify-center">
                            {item.badge}
                          </span>
                        )}
                      </>
                    )}
                  </Link>
                )
              })}
            </div>
          </div>
        ))}
      </nav>

      {/* Collapse toggle (desktop only) */}
      <div className={cn('px-3 py-2 border-t border-sidebar-border hidden lg:block')}>
        <button
          onClick={() => setCollapsed(!collapsed)}
          className={cn(
            'nav-card-glass flex items-center gap-2.5 px-3 py-2 text-xs w-full',
            isCollapsed && 'justify-center px-2',
          )}
          title={isCollapsed ? 'Expandir' : 'Recolher'}
        >
          {isCollapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}
          {!isCollapsed && <span>Recolher</span>}
        </button>
      </div>

      {/* User section */}
      <div className={cn('border-t border-sidebar-border p-2', isCollapsed && 'px-2')}>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              className={cn(
                'flex items-center gap-2 w-full p-2 rounded-lg hover:bg-sidebar-accent/50 transition-colors',
                isCollapsed && 'justify-center',
              )}
            >
              <div className="h-7 w-7 shrink-0 rounded-full bg-moss-700 text-cream-100 flex items-center justify-center text-[11px] font-medium font-display">
                {initials}
              </div>
              {!isCollapsed && (
                <div className="flex-1 text-left min-w-0">
                  <p className="text-xs font-medium text-foreground truncate">
                    {userName || userEmail.split('@')[0]}
                  </p>
                  <p className="text-[10px] text-muted-foreground truncate">Minha Conta</p>
                </div>
              )}
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel>
              <div className="flex flex-col">
                <span className="font-medium">{userName || 'Admin'}</span>
                <span className="text-xs font-normal text-muted-foreground truncate">
                  {userEmail}
                </span>
              </div>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem asChild>
              <Link href="/settings/admins" className="cursor-pointer">
                <Settings className="mr-2 h-4 w-4" />
                Configurações
              </Link>
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={signOut} className="text-destructive cursor-pointer">
              <LogOut className="mr-2 h-4 w-4" />
              Sair
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )

  return (
    <>
      {/* Mobile header */}
      <header className="lg:hidden sticky top-0 z-30 flex items-center justify-between px-4 py-3 bg-background border-b border-border">
        <button
          onClick={() => setMobileOpen(!mobileOpen)}
          aria-label={mobileOpen ? 'Fechar menu' : 'Abrir menu'}
          className="p-2 rounded-lg hover:bg-accent/20 transition-colors"
        >
          {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
        <Link href="/dashboard" className="flex items-center gap-2">
          <div className="h-7 w-7 rounded-md bg-ink-900 text-cream-100 flex items-center justify-center font-display text-base">
            M
          </div>
          <span className="font-display text-base">Agente MPP</span>
        </Link>
        <div className="w-9" />
      </header>

      {/* Desktop Sidebar */}
      <aside
        className={cn(
          'hidden lg:flex flex-col bg-sidebar border-r border-sidebar-border transition-all duration-200 ease-out h-screen overflow-hidden shrink-0',
          collapsed ? 'w-[72px]' : 'w-64',
        )}
      >
        {navContent(collapsed)}
      </aside>

      {/* Mobile Sidebar */}
      {mobileOpen && (
        <div
          onClick={() => setMobileOpen(false)}
          className="fixed inset-0 z-40 bg-background/80 backdrop-blur-sm lg:hidden"
        />
      )}
      <aside
        className={cn(
          'fixed inset-y-0 left-0 z-50 w-64 bg-sidebar border-r border-sidebar-border lg:hidden transition-transform duration-300 ease-out',
          mobileOpen ? 'translate-x-0' : '-translate-x-full',
        )}
      >
        {navContent(false)}
      </aside>
    </>
  )
}
