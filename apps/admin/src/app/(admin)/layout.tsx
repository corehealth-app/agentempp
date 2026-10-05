import { redirect } from 'next/navigation'
import { Suspense } from 'react'
import { AdminAccessDenied } from '@/components/admin-access-denied'
import { CommandPalette } from '@/components/command-palette'
import { KeyboardShortcuts } from '@/components/keyboard-shortcuts'
import { Sidebar } from '@/components/sidebar'
import { StatusBar } from '@/components/status-bar'
import { canOpenAdminPath } from '@/lib/admin-access'
import { loadAdminSession } from '@/lib/admin-page-guard'
import { ContentHistoryTracker } from '@/lib/content/navigation-guard'

export const dynamic = 'force-dynamic'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  // Mesma leitura que `guardAdminPage` faz em cada página (uma só por pedido).
  // O layout decide a moldura; quem barra o DADO é o guarda da página.
  const session = await loadAdminSession()

  if (session.kind === 'anonymous') redirect('/login')

  if (session.kind === 'not_admin') {
    return (
      <AdminAccessDenied
        fullScreen
        access={{ ok: false, reason: 'not_admin', userEmail: session.userEmail }}
      />
    )
  }

  const { admin } = session
  // A barra de status traz números de operação (crons, custo, atenção) e leva
  // a telas de operação: só aparece para quem abre o dashboard.
  const showStatusBar = canOpenAdminPath(admin.role, '/dashboard')

  return (
    <div className="h-screen bg-background flex overflow-hidden">
      <ContentHistoryTracker />
      <Sidebar
        userEmail={session.userEmail ?? ''}
        userName={admin.name ?? undefined}
        role={admin.role}
      />
      <div className="flex-1 flex flex-col min-w-0 h-full overflow-hidden">
        {showStatusBar && (
          <Suspense fallback={<div className="h-9 border-b border-border" />}>
            <StatusBar />
          </Suspense>
        )}
        <main className="flex-1 min-h-0 px-4 sm:px-6 py-4 overflow-y-auto pb-20 lg:pb-4">
          {children}
        </main>
      </div>
      <CommandPalette role={admin.role} />
      <KeyboardShortcuts role={admin.role} />
    </div>
  )
}
