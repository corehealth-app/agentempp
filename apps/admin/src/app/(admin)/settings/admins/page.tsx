import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { AdminInviteForm } from './form'

export default async function AdminsPage() {
  const svc = createServiceClient()
  const { data: admins } = await svc
    .from('admin_users')
    .select('*')
    .order('created_at', { ascending: false })

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Usuários do admin</h1>
        <p className="text-muted-foreground">
          Quem pode acessar este painel. Apenas role <Badge>admin</Badge> pode adicionar
          outros usuários.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Adicionar admin</CardTitle>
          <CardDescription>
            O usuário precisa ter feito login pelo menos uma vez via /login para que o ID seja
            conhecido. O email aqui deve ser o mesmo do magic link.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <AdminInviteForm />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Lista atual</CardTitle>
        </CardHeader>
        <CardContent>
          {!admins || admins.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Nenhum admin cadastrado ainda. O primeiro acesso é registrado via Edge Function ou
              pelo Supabase dashboard.
            </p>
          ) : (
            <ul className="divide-y">
              {admins.map((a) => (
                <li key={a.id} className="flex items-center justify-between py-3">
                  <div>
                    <div className="font-medium">{a.name ?? a.email}</div>
                    <div className="text-xs text-muted-foreground">{a.email}</div>
                  </div>
                  <div className="flex items-center gap-3">
                    <Badge>{a.role}</Badge>
                    <span className="text-xs text-muted-foreground">
                      {formatDateTime(a.created_at)}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
