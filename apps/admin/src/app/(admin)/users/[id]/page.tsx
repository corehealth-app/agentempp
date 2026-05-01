import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { notFound } from 'next/navigation'

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const svc = createServiceClient()

  const { data: user } = await svc.from('users').select('*').eq('id', id).maybeSingle()
  if (!user) notFound()

  const [{ data: profile }, { data: progress }, { data: messages }, { data: snapshots }] =
    await Promise.all([
      svc.from('user_profiles').select('*').eq('user_id', id).maybeSingle(),
      svc.from('user_progress').select('*').eq('user_id', id).maybeSingle(),
      svc
        .from('messages')
        .select(
          'id, direction, content, content_type, agent_stage, model_used, cost_usd, created_at',
        )
        .eq('user_id', id)
        .order('created_at', { ascending: false })
        .limit(50),
      svc
        .from('daily_snapshots')
        .select('*')
        .eq('user_id', id)
        .order('date', { ascending: false })
        .limit(14),
    ])

  return (
    <div className="space-y-6 p-6 max-w-6xl">
      <div>
        <h1 className="text-3xl font-bold">{user.name ?? user.wpp}</h1>
        <p className="text-muted-foreground font-mono text-sm">
          {user.wpp} · {user.id}
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        {/* Perfil */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Perfil</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1.5 text-sm">
            <Field label="Sexo" value={profile?.sex} />
            <Field label="Idade" value={profile?.birth_date} />
            <Field label="Altura" value={profile?.height_cm ? `${profile.height_cm} cm` : null} />
            <Field label="Peso" value={profile?.weight_kg ? `${profile.weight_kg} kg` : null} />
            <Field label="BF%" value={profile?.body_fat_percent?.toString()} />
            <Field label="Treino/sem" value={profile?.training_frequency?.toString()} />
            <Field label="Atividade" value={profile?.activity_level} />
            <Field label="Onboarding" value={profile?.onboarding_completed ? '✅' : '⏳'} />
          </CardContent>
        </Card>

        {/* Protocolo */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Protocolo</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1.5 text-sm">
            <Field label="Atual" value={profile?.current_protocol} />
            <Field label="Goal Type" value={profile?.goal_type} />
            <Field label="Goal Value" value={profile?.goal_value?.toString()} />
            <Field
              label="Déficit"
              value={profile?.deficit_level ? `${profile.deficit_level} kcal` : null}
            />
          </CardContent>
        </Card>

        {/* Gamificação */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Progresso</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1.5 text-sm">
            <Field label="XP" value={progress?.xp_total?.toString()} />
            <Field label="Level" value={progress?.level?.toString()} />
            <Field label="Streak" value={progress?.current_streak?.toString()} />
            <Field label="Maior streak" value={progress?.longest_streak?.toString()} />
            <Field label="Blocos 7700" value={progress?.blocks_completed?.toString()} />
            <Field label="Déficit no bloco" value={progress?.deficit_block?.toString()} />
            <div>
              <span className="text-xs text-muted-foreground">Badges:</span>{' '}
              {(progress?.badges_earned ?? []).length === 0 ? (
                <span className="text-xs">—</span>
              ) : (
                <div className="flex flex-wrap gap-1 mt-1">
                  {(progress?.badges_earned ?? []).map((b) => (
                    <Badge key={b} variant="secondary" className="text-xs">
                      {b}
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Snapshots últimos 14 dias */}
      <Card>
        <CardHeader>
          <CardTitle>Últimos 14 dias</CardTitle>
        </CardHeader>
        <CardContent>
          {!snapshots || snapshots.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem snapshots ainda.</p>
          ) : (
            <table className="w-full text-sm">
              <thead className="text-xs text-muted-foreground">
                <tr className="border-b">
                  <th className="text-left py-1.5">Data</th>
                  <th className="text-right py-1.5">kcal</th>
                  <th className="text-right py-1.5">prot</th>
                  <th className="text-right py-1.5">treino</th>
                  <th className="text-right py-1.5">balanço</th>
                  <th className="text-right py-1.5">XP</th>
                  <th className="text-center py-1.5">fechado</th>
                </tr>
              </thead>
              <tbody>
                {snapshots.map((s) => (
                  <tr key={s.id} className="border-b last:border-0">
                    <td className="py-1.5">{s.date}</td>
                    <td className="text-right">
                      {s.calories_consumed} / {s.calories_target ?? '—'}
                    </td>
                    <td className="text-right">
                      {s.protein_g} / {s.protein_target ?? '—'}
                    </td>
                    <td className="text-right">{s.training_done ? '✅' : '—'}</td>
                    <td
                      className={`text-right ${(s.daily_balance ?? 0) < 0 ? 'text-red-500' : 'text-green-500'}`}
                    >
                      {s.daily_balance}
                    </td>
                    <td className="text-right">{s.xp_earned}</td>
                    <td className="text-center">{s.day_closed ? '🔒' : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      {/* Conversas recentes */}
      <Card>
        <CardHeader>
          <CardTitle>Conversas recentes</CardTitle>
          <CardDescription>Últimas 50 mensagens (mais recentes primeiro)</CardDescription>
        </CardHeader>
        <CardContent>
          {!messages || messages.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem mensagens.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {messages.map((m) => (
                <li key={m.id} className="border-b pb-2 last:border-0">
                  <div className="flex items-start gap-2">
                    <span
                      className={`shrink-0 mt-1 inline-block h-2 w-2 rounded-full ${m.direction === 'in' ? 'bg-blue-500' : 'bg-green-500'}`}
                    />
                    <div className="flex-1 min-w-0">
                      <div className="text-xs text-muted-foreground mb-0.5">
                        [{m.direction}] {m.agent_stage ?? ''} {m.model_used ?? ''}{' '}
                        {m.cost_usd ? `· $${m.cost_usd}` : ''} ·{' '}
                        {formatDateTime(m.created_at)}
                      </div>
                      <div className="whitespace-pre-wrap">{m.content ?? '(mídia)'}</div>
                    </div>
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

function Field({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div className="flex justify-between gap-2">
      <span className="text-muted-foreground">{label}:</span>
      <span className="font-medium text-right">{value || '—'}</span>
    </div>
  )
}
