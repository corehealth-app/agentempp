import { Sidebar } from '@/components/sidebar'
import { StatusBar } from '@/components/status-bar'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { Suspense } from 'react'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: adminRow } = await supabase
    .from('admin_users')
    .select('id, email, name, role')
    .eq('id', user.id)
    .maybeSingle()

  if (!adminRow) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6">
        <div className="glass-card p-8 max-w-md w-full space-y-6">
          <div className="section-eyebrow">Acesso restrito</div>
          <h1 className="font-display text-3xl text-foreground tracking-tight">Não autorizado</h1>
          <p className="text-muted-foreground text-pretty">
            O email <strong className="font-medium text-foreground">{user.email}</strong> não está
            cadastrado em <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">admin_users</code>.
            Peça a um admin atual para te incluir.
          </p>
          <form action="/auth/signout" method="post" className="pt-4">
            <button
              type="submit"
              className="text-sm text-muted-foreground hover:text-foreground underline underline-offset-4 focus-ring rounded px-1 -mx-1"
            >
              Sair desta conta
            </button>
          </form>
        </div>
      </div>
    )
  }

  return (
    <div className="h-screen bg-background flex overflow-hidden">
      <Sidebar
        userEmail={user.email ?? ''}
        userName={(adminRow as { name?: string | null }).name ?? undefined}
      />
      <div className="flex-1 flex flex-col min-w-0 h-full overflow-hidden">
        <Suspense fallback={<div className="h-9 border-b border-border" />}>
          <StatusBar />
        </Suspense>
        <main className="flex-1 min-h-0 px-4 sm:px-6 py-4 overflow-y-auto pb-20 lg:pb-4">
          {children}
        </main>
      </div>
    </div>
  )
}
