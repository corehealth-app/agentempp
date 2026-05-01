import { Sidebar } from '@/components/sidebar'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

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
      <div className="min-h-screen flex items-center justify-center p-6 paper">
        <div className="max-w-md w-full space-y-6 animate-fade-up">
          <div className="section-eyebrow">Acesso restrito</div>
          <h1 className="font-display text-4xl text-ink-900 tracking-tight">Não autorizado</h1>
          <p className="text-ink-600 text-pretty">
            O email <strong className="font-medium text-ink-900">{user.email}</strong> não está
            cadastrado em <code className="font-mono text-xs bg-cream-200 px-1.5 py-0.5 rounded">admin_users</code>.
            Peça a um admin atual para te incluir, ou rode o script <code className="font-mono text-xs">bootstrap-admin</code>.
          </p>
          <form action="/auth/signout" method="post" className="pt-4">
            <button
              type="submit"
              className="text-sm text-ink-500 hover:text-ink-900 underline underline-offset-4 focus-ring rounded px-1 -mx-1"
            >
              Sair desta conta
            </button>
          </form>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen">
      <Sidebar userEmail={user.email ?? ''} />
      <main className="flex-1 overflow-y-auto bg-cream-100 paper">
        <div className="animate-fade-in">{children}</div>
      </main>
    </div>
  )
}
