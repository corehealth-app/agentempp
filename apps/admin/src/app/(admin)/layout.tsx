import { Sidebar } from '@/components/sidebar'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  // Verifica se é admin
  const { data: adminRow } = await supabase
    .from('admin_users')
    .select('id, email, name, role')
    .eq('id', user.id)
    .maybeSingle()

  if (!adminRow) {
    return (
      <div className="flex min-h-screen items-center justify-center p-6">
        <div className="max-w-md text-center space-y-4">
          <h1 className="text-2xl font-semibold">Acesso negado</h1>
          <p className="text-muted-foreground">
            Seu email <strong>{user.email}</strong> não está autorizado neste painel. Peça a um
            admin para te adicionar à tabela <code>admin_users</code>.
          </p>
          <form action="/auth/signout" method="post">
            <button className="text-sm text-primary underline" type="submit">
              Sair
            </button>
          </form>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen">
      <Sidebar userEmail={user.email ?? ''} />
      <main className="flex-1 overflow-y-auto bg-muted/20">{children}</main>
    </div>
  )
}
