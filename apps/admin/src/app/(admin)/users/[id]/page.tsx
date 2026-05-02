import { ContentCard, PageHeader } from '@/components/page-header'
import { CountryBadge } from '@/components/country-badge'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime } from '@/lib/utils'
import { notFound } from 'next/navigation'
import { Bot, User as UserIcon } from 'lucide-react'
import { CheckoutButton } from './checkout-button'
import { DangerButtons } from './danger-buttons'

const PROTOCOL_LABELS: Record<string, string> = {
  recomposicao: 'Recomposição',
  ganho_massa: 'Ganho de Massa',
  manutencao: 'Manutenção',
}

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const svc = createServiceClient()

  const { data: user } = await svc.from('users').select('*').eq('id', id).maybeSingle()
  if (!user) notFound()

  const [
    { data: profile },
    { data: progress },
    { data: messages },
    { data: snapshots },
    { data: subscription },
  ] = await Promise.all([
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
    svc
      .from('subscriptions')
      .select('id, plan, status, current_period_end, trial_ends_at, cancel_at_period_end')
      .eq('user_id', id)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
  ])
  const sub = subscription as
    | {
        id: string
        plan: string
        status: string
        current_period_end: string | null
        trial_ends_at: string | null
        cancel_at_period_end: boolean
      }
    | null

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[
          { label: 'Operação' },
          { label: 'Usuários', href: '/users' },
          { label: user.name ?? user.wpp },
        ]}
        title={user.name ?? user.wpp}
        description={
          <span className="font-mono text-xs inline-flex items-center gap-2">
            {user.wpp} · {user.id.slice(0, 8)}…
            <CountryBadge
              country={(user as { country?: string | null }).country ?? null}
              confirmed={!!(user as { country_confirmed?: boolean }).country_confirmed}
            />
          </span>
        }
      />

      <div className="grid gap-4 md:grid-cols-3">
        <ContentCard title="Perfil">
          <div className="space-y-2 text-sm">
            <Field label="Sexo" value={profile?.sex} />
            <Field label="Nascimento" value={profile?.birth_date} />
            <Field label="Altura" value={profile?.height_cm ? `${profile.height_cm} cm` : null} />
            <Field label="Peso" value={profile?.weight_kg ? `${profile.weight_kg} kg` : null} />
            <Field label="BF%" value={profile?.body_fat_percent?.toString()} />
            <Field label="Treino/sem" value={profile?.training_frequency?.toString()} />
            <Field label="Atividade" value={profile?.activity_level} />
            <Field
              label="Onboarding"
              value={profile?.onboarding_completed ? 'Concluído' : 'Em andamento'}
            />
          </div>
        </ContentCard>

        <ContentCard title="Protocolo">
          <div className="space-y-2 text-sm">
            <Field
              label="Atual"
              value={
                profile?.current_protocol
                  ? PROTOCOL_LABELS[profile.current_protocol] ?? profile.current_protocol
                  : null
              }
            />
            <Field label="Goal Type" value={profile?.goal_type} />
            <Field label="Goal Value" value={profile?.goal_value?.toString()} />
            <Field
              label="Déficit"
              value={profile?.deficit_level ? `${profile.deficit_level} kcal` : null}
            />
          </div>
        </ContentCard>

        <ContentCard title="Progresso">
          <div className="space-y-2 text-sm">
            <Field label="XP Total" value={progress?.xp_total?.toString()} mono />
            <Field label="Level" value={progress?.level?.toString()} mono />
            <Field label="Streak atual" value={progress?.current_streak?.toString() ? `${progress.current_streak}d` : null} mono />
            <Field label="Maior streak" value={progress?.longest_streak?.toString() ? `${progress.longest_streak}d` : null} mono />
            <Field label="Blocos 7700" value={progress?.blocks_completed?.toString()} mono />
            <Field label="Déficit bloco" value={progress?.deficit_block?.toString()} mono />
            {(progress?.badges_earned ?? []).length > 0 && (
              <div className="pt-2 border-t border-border">
                <div className="text-xs text-muted-foreground mb-1.5">Badges:</div>
                <div className="flex flex-wrap gap-1">
                  {(progress?.badges_earned ?? []).map((b) => (
                    <span
                      key={b}
                      className="text-[10px] uppercase tracking-widest font-mono bg-bronze/10 text-bronze px-2 py-0.5 rounded-full"
                    >
                      {b}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        </ContentCard>
      </div>

      <ContentCard
        title="Assinatura"
        description={
          sub
            ? `${sub.plan} · ${sub.status}${sub.cancel_at_period_end ? ' · cancelando no fim do período' : ''}`
            : 'Sem assinatura ativa — gere um link de checkout abaixo'
        }
      >
        {sub ? (
          <div className="space-y-3">
            <div className="grid gap-3 md:grid-cols-3 text-sm">
              <Field label="Plano" value={sub.plan} mono />
              <Field label="Status" value={sub.status} mono />
              <Field
                label="Próx. cobrança"
                value={
                  sub.current_period_end
                    ? new Date(sub.current_period_end).toLocaleDateString('pt-BR')
                    : null
                }
                mono
              />
              <Field
                label="Trial até"
                value={
                  sub.trial_ends_at
                    ? new Date(sub.trial_ends_at).toLocaleDateString('pt-BR')
                    : null
                }
                mono
              />
            </div>
            <div className="pt-3 border-t border-border">
              <CheckoutButton userId={id} />
            </div>
          </div>
        ) : (
          <CheckoutButton userId={id} />
        )}
      </ContentCard>

      <ContentCard
        title="Últimos 14 dias"
        description="Snapshots diários de calorias, proteína, treino e balanço"
      >
        {!snapshots || snapshots.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sem snapshots ainda.</p>
        ) : (
          <div className="overflow-x-auto -mx-5 -my-5">
            <table className="w-full text-sm">
              <thead className="text-[10px] uppercase tracking-widest text-muted-foreground bg-muted/40 border-b border-border">
                <tr>
                  <th className="text-left px-5 py-2.5 font-mono">Data</th>
                  <th className="text-right px-3 py-2.5 font-mono">kcal</th>
                  <th className="text-right px-3 py-2.5 font-mono">proteína</th>
                  <th className="text-right px-3 py-2.5 font-mono">treino</th>
                  <th className="text-right px-3 py-2.5 font-mono">balanço</th>
                  <th className="text-right px-3 py-2.5 font-mono">XP</th>
                  <th className="text-center px-5 py-2.5 font-mono">fechado</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {snapshots.map((s) => (
                  <tr key={s.id} className="hover:bg-muted/30 transition-colors">
                    <td className="px-5 py-2.5 font-mono text-xs">{s.date}</td>
                    <td className="text-right px-3 py-2.5 font-mono text-xs tabular-nums">
                      {s.calories_consumed}
                      {s.calories_target && (
                        <span className="text-muted-foreground"> / {s.calories_target}</span>
                      )}
                    </td>
                    <td className="text-right px-3 py-2.5 font-mono text-xs tabular-nums">
                      {Number(s.protein_g)}g
                      {s.protein_target && (
                        <span className="text-muted-foreground"> / {s.protein_target}g</span>
                      )}
                    </td>
                    <td className="text-right px-3 py-2.5 text-xs">
                      {s.training_done ? '✓' : '—'}
                    </td>
                    <td
                      className={`text-right px-3 py-2.5 font-mono text-xs tabular-nums ${
                        (s.daily_balance ?? 0) < 0 ? 'text-moss-700' : 'text-bronze'
                      }`}
                    >
                      {s.daily_balance}
                    </td>
                    <td className="text-right px-3 py-2.5 font-mono text-xs tabular-nums">
                      {s.xp_earned}
                    </td>
                    <td className="text-center px-5 py-2.5 text-xs">
                      {s.day_closed ? '🔒' : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </ContentCard>

      <ContentCard
        title="Conversas recentes"
        description="Últimas 50 mensagens (mais recentes primeiro)"
      >
        {!messages || messages.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sem mensagens.</p>
        ) : (
          <ul className="space-y-3">
            {messages.map((m) => (
              <li
                key={m.id}
                className="flex gap-3 pb-3 border-b border-border last:border-0 last:pb-0"
              >
                <div
                  className={`shrink-0 h-7 w-7 rounded-md flex items-center justify-center ${
                    m.direction === 'in'
                      ? 'bg-ink-900 text-cream-100'
                      : 'bg-moss-700 text-cream-100'
                  }`}
                >
                  {m.direction === 'in' ? (
                    <UserIcon className="h-3.5 w-3.5" />
                  ) : (
                    <Bot className="h-3.5 w-3.5" />
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 text-[10px] uppercase tracking-widest font-mono text-muted-foreground mb-1">
                    <span>{m.direction === 'in' ? 'usuário' : 'agente'}</span>
                    {m.agent_stage && (
                      <>
                        <span>·</span>
                        <span>{m.agent_stage.replace('_', ' ')}</span>
                      </>
                    )}
                    {m.cost_usd && (
                      <>
                        <span>·</span>
                        <span>${Number(m.cost_usd).toFixed(5)}</span>
                      </>
                    )}
                    <span>·</span>
                    <span>{formatDateTime(m.created_at)}</span>
                  </div>
                  <div className="text-sm text-foreground whitespace-pre-wrap">
                    {m.content ?? <span className="italic text-muted-foreground">(mídia)</span>}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </ContentCard>

      <ContentCard
        title="Zona de perigo"
        description="Resetar mantém o paciente e zera onboarding (testar fluxo do zero). Excluir apaga tudo permanentemente (cascade)."
      >
        <DangerButtons
          userId={user.id}
          userName={user.name}
          userWpp={user.wpp}
        />
      </ContentCard>
    </div>
  )
}

function Field({
  label,
  value,
  mono,
}: {
  label: string
  value: string | null | undefined
  mono?: boolean
}) {
  return (
    <div className="flex justify-between items-baseline gap-2">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span
        className={`text-right text-foreground ${mono ? 'font-mono tabular-nums text-sm' : 'font-medium text-sm'}`}
      >
        {value || <span className="text-muted-foreground">—</span>}
      </span>
    </div>
  )
}
