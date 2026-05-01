import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import Link from 'next/link'
import { ChevronRight, Flame, TrendingUp } from 'lucide-react'

const PROTOCOL_LABELS: Record<string, string> = {
  recomposicao: 'Recomposição',
  ganho_massa: 'Ganho de Massa',
  manutencao: 'Manutenção',
}

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
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Operação' }, { label: 'Usuários' }]}
        title="Usuários"
        description="Últimos 100 usuários por atividade. Clique para detalhes."
      />

      <ContentCard>
        {!users || users.length === 0 ? (
          <p className="text-sm text-muted-foreground py-4">
            Nenhum usuário ainda. Cadastre um pelo Playground.
          </p>
        ) : (
          <ul className="divide-y divide-border -mx-5 -my-5">
            {users.map((u) => {
              const p = profMap.get(u.id)
              const pr = progMap.get(u.id)
              const initials = (u.name ?? u.wpp ?? '?').slice(0, 2).toUpperCase()
              return (
                <li key={u.id}>
                  <Link
                    href={`/users/${u.id}`}
                    className="group flex items-center gap-4 px-5 py-3.5 hover:bg-muted/40 transition-colors"
                  >
                    <div className="h-10 w-10 shrink-0 rounded-full bg-moss-700 text-cream-100 flex items-center justify-center text-xs font-medium font-display">
                      {initials}
                    </div>

                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-medium text-foreground">
                          {u.name ?? <span className="italic text-muted-foreground">sem nome</span>}
                        </span>
                        <span className="text-xs font-mono text-muted-foreground">{u.wpp}</span>
                        <span
                          className={`inline-flex text-[10px] uppercase tracking-widest font-mono px-2 py-0.5 rounded-full ${
                            u.status === 'active'
                              ? 'bg-moss-100 text-moss-700'
                              : 'bg-muted text-muted-foreground'
                          }`}
                        >
                          {u.status}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 text-xs text-muted-foreground mt-1">
                        <span>
                          {p?.onboarding_completed ? '✓' : '⏳'}{' '}
                          {p?.current_protocol
                            ? PROTOCOL_LABELS[p.current_protocol] ?? p.current_protocol
                            : 'sem protocolo'}
                        </span>
                        {p?.weight_kg && (
                          <>
                            <span className="text-border">·</span>
                            <span className="font-mono">{p.weight_kg}kg</span>
                          </>
                        )}
                        {pr && (
                          <>
                            <span className="text-border">·</span>
                            <span className="flex items-center gap-1">
                              <TrendingUp className="h-3 w-3" />
                              <span className="font-mono">L{pr.level} · {pr.xp_total}xp</span>
                            </span>
                            {pr.current_streak > 0 && (
                              <span className="flex items-center gap-1 text-bronze">
                                <Flame className="h-3 w-3" />
                                <span className="font-mono">{pr.current_streak}d</span>
                              </span>
                            )}
                          </>
                        )}
                      </div>
                    </div>

                    <div className="shrink-0 flex items-center gap-3 text-xs text-muted-foreground">
                      <span className="hidden sm:inline font-mono">
                        {formatDateTime(u.updated_at)}
                      </span>
                      <ChevronRight className="h-4 w-4 group-hover:translate-x-0.5 transition-transform" />
                    </div>
                  </Link>
                </li>
              )
            })}
          </ul>
        )}
      </ContentCard>
    </div>
  )
}
