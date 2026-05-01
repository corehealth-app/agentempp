import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import Link from 'next/link'
import { ChevronRight } from 'lucide-react'

export default async function UsersPage() {
  const svc = createServiceClient()
  const { data: users } = await svc
    .from('users')
    .select('id, name, wpp, status, created_at, updated_at')
    .order('updated_at', { ascending: false })
    .limit(100)

  const ids = (users ?? []).map((u) => u.id)
  const { data: profiles } = await svc
    .from('user_profiles')
    .select('user_id, current_protocol, onboarding_completed, weight_kg')
    .in('user_id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000'])
  const { data: progress } = await svc
    .from('user_progress')
    .select('user_id, xp_total, level, current_streak, blocks_completed')
    .in('user_id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000'])

  const profMap = new Map(profiles?.map((p) => [p.user_id, p]) ?? [])
  const progMap = new Map(progress?.map((p) => [p.user_id, p]) ?? [])

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">Usuários</h1>
        <p className="text-muted-foreground">
          Últimos 100 usuários por atividade. Clique para detalhes.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Lista</CardTitle>
        </CardHeader>
        <CardContent>
          {!users || users.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Nenhum usuário ainda. Cadastre um pelo /prompts/playground.
            </p>
          ) : (
            <ul className="divide-y">
              {users.map((u) => {
                const p = profMap.get(u.id)
                const pr = progMap.get(u.id)
                return (
                  <li key={u.id}>
                    <Link
                      href={`/users/${u.id}`}
                      className="flex items-center justify-between gap-4 py-3 px-2 hover:bg-muted/50 rounded transition"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <span className="font-medium">{u.name ?? '(sem nome)'}</span>
                          <span className="text-xs text-muted-foreground">{u.wpp}</span>
                          <Badge variant={u.status === 'active' ? 'default' : 'outline'}>
                            {u.status}
                          </Badge>
                        </div>
                        <div className="text-xs text-muted-foreground mt-0.5">
                          {p?.onboarding_completed ? '✅ onboarded' : '⏳ onboarding'} ·{' '}
                          {p?.current_protocol ?? 'sem protocolo'}
                          {p?.weight_kg && ` · ${p.weight_kg}kg`}
                          {pr && ` · XP ${pr.xp_total} L${pr.level} · 🔥${pr.current_streak}d`}
                        </div>
                      </div>
                      <div className="text-xs text-muted-foreground shrink-0 flex items-center gap-1">
                        {formatDateTime(u.updated_at)}
                        <ChevronRight className="h-4 w-4" />
                      </div>
                    </Link>
                  </li>
                )
              })}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
