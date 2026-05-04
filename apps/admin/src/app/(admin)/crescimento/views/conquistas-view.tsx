import Link from 'next/link'
import { Award, Flame, Target, TrendingUp, Trophy } from 'lucide-react'
import { ContentCard } from '@/components/page-header'
import { KpiCard } from '@/components/kpi-card'
import { createServiceClient } from '@/lib/supabase/server'
import { formatNumber } from '@/lib/utils'

interface Progress {
  user_id: string
  xp_total: number
  level: number
  current_streak: number
  longest_streak: number
  blocks_completed: number
  deficit_block: number
  badges_earned: string[]
  last_active_date: string | null
  updated_at: string
}

interface User {
  id: string
  name: string | null
  wpp: string
}

export async function ConquistasView() {
  const svc = createServiceClient()

  const [{ data: progress }, { data: users }, { data: kcalBlockRow }] = await Promise.all([
    svc.from('user_progress').select('*').order('updated_at', { ascending: false }).limit(500),
    svc.from('users').select('id, name, wpp').eq('status', 'active').limit(500),
    (svc as unknown as {
      from: (t: string) => {
        select: (s: string) => {
          eq: (col: string, val: string) => {
            maybeSingle: () => Promise<{ data: { value: unknown } | null }>
          }
        }
      }
    })
      .from('global_config')
      .select('value')
      .eq('key', 'calc.kcal_block')
      .maybeSingle(),
  ])

  // Lê do global_config (editável em /settings/calc) com fallback fisiológico
  const BLOCK_KCAL_TARGET = Number(kcalBlockRow?.value ?? 7700)

  const userMap = new Map<string, User>(
    ((users ?? []) as User[]).map((u) => [u.id, u]),
  )
  const rows = ((progress ?? []) as Progress[]).filter((p) => userMap.has(p.user_id))

  // Distribuição por nível
  const levelDist = new Map<number, number>()
  for (const r of rows) {
    levelDist.set(r.level, (levelDist.get(r.level) ?? 0) + 1)
  }
  const levels = [...levelDist.entries()].sort(([a], [b]) => a - b)
  const maxLevelCount = Math.max(...[...levelDist.values()], 1)

  // Top streaks
  const topStreaks = [...rows]
    .filter((r) => r.current_streak > 0)
    .sort((a, b) => b.current_streak - a.current_streak)
    .slice(0, 10)

  // Próximos a fechar bloco (deficit_block próximo de 7700)
  const closeToBlock = [...rows]
    .filter((r) => r.deficit_block > 0 && r.deficit_block < BLOCK_KCAL_TARGET)
    .sort((a, b) => b.deficit_block - a.deficit_block)
    .slice(0, 10)

  // Top XP
  const topXp = [...rows].sort((a, b) => b.xp_total - a.xp_total).slice(0, 10)

  // Total badges
  const totalBadges = rows.reduce((s, r) => s + (r.badges_earned?.length ?? 0), 0)
  const blocksTotal = rows.reduce((s, r) => s + r.blocks_completed, 0)
  const xpTotal = rows.reduce((s, r) => s + r.xp_total, 0)
  const longestStreak = Math.max(...rows.map((r) => r.longest_streak), 0)

  return (
    <div className="space-y-4">

      {/* === KPIs de gamificação === */}
      <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Pacientes engajados"
          value={formatNumber(rows.length)}
          subtitle="com progresso"
          icon={Trophy}
        />
        <KpiCard
          label="Blocos fechados"
          value={formatNumber(blocksTotal)}
          subtitle={`${((blocksTotal * BLOCK_KCAL_TARGET) / 1000).toFixed(1)} kg de gordura`}
          icon={Target}
        />
        <KpiCard
          label="XP total acumulado"
          value={formatNumber(xpTotal)}
          subtitle={`${formatNumber(totalBadges)} badges`}
          icon={Award}
        />
        <KpiCard
          label="Maior streak"
          value={`${longestStreak} dias`}
          subtitle="recorde geral"
          icon={Flame}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        {/* === Distribuição por nível === */}
        <ContentCard title="Distribuição por nível" description="Quantos pacientes em cada nível">
          {levels.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nenhum paciente com progresso ainda.</p>
          ) : (
            <div className="space-y-2">
              {levels.map(([lvl, count]) => {
                const pct = (count / maxLevelCount) * 100
                return (
                  <div key={lvl} className="flex items-center gap-3 text-xs">
                    <span className="w-16 font-mono text-muted-foreground shrink-0">
                      Nível {lvl}
                    </span>
                    <div className="flex-1 h-3 bg-muted/40 rounded-sm relative overflow-hidden">
                      <div
                        className="absolute inset-y-0 left-0 bg-moss-500 rounded-sm transition-all"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                    <span className="w-10 text-right font-mono tabular-nums">
                      {formatNumber(count)}
                    </span>
                  </div>
                )
              })}
            </div>
          )}
        </ContentCard>

        {/* === Próximos a fechar bloco === */}
        <ContentCard
          title="Próximos a fechar bloco"
          description="Pacientes >50% do caminho — momento de empurrar"
        >
          {closeToBlock.length === 0 ? (
            <p className="text-sm text-muted-foreground">Ninguém com bloco em progresso.</p>
          ) : (
            <ul className="space-y-2">
              {closeToBlock.map((p) => {
                const u = userMap.get(p.user_id)
                const pct = (p.deficit_block / BLOCK_KCAL_TARGET) * 100
                return (
                  <li key={p.user_id}>
                    <Link
                      href={`/users/${p.user_id}`}
                      className="glass-subtle flex items-center gap-3 p-2.5 hover:bg-muted/40 transition-colors group"
                    >
                      <div className="flex-1 min-w-0">
                        <div className="flex items-baseline justify-between mb-1">
                          <span className="font-medium text-foreground truncate">
                            {u?.name ?? '(sem nome)'}
                          </span>
                          <span className="font-mono text-[11px] text-muted-foreground tabular-nums">
                            {formatNumber(p.deficit_block)}/{formatNumber(BLOCK_KCAL_TARGET)} kcal
                          </span>
                        </div>
                        <div className="h-1.5 bg-muted/40 rounded-sm relative overflow-hidden">
                          <div
                            className="absolute inset-y-0 left-0 bg-gradient-to-r from-moss-400 to-moss-600 rounded-sm transition-all"
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                      </div>
                      <span className="font-mono text-xs tabular-nums text-foreground/80 shrink-0 w-10 text-right">
                        {pct.toFixed(0)}%
                      </span>
                    </Link>
                  </li>
                )
              })}
            </ul>
          )}
        </ContentCard>

        {/* === Top streaks === */}
        <ContentCard title="Top streaks ativos" description="Quem não pode quebrar hoje">
          {topStreaks.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem streaks ativos no momento.</p>
          ) : (
            <ol className="space-y-2">
              {topStreaks.map((p, i) => {
                const u = userMap.get(p.user_id)
                return (
                  <li key={p.user_id}>
                    <Link
                      href={`/users/${p.user_id}`}
                      className="glass-subtle flex items-center gap-3 p-2.5 hover:bg-muted/40 transition-colors"
                    >
                      <span className="font-mono text-muted-foreground text-xs w-5 text-right">
                        {i + 1}
                      </span>
                      <span className="text-base">
                        {p.current_streak >= 30 ? '🔥' : p.current_streak >= 14 ? '⚡' : '✨'}
                      </span>
                      <span className="flex-1 truncate text-sm">{u?.name ?? '(sem nome)'}</span>
                      <span className="font-mono tabular-nums text-sm text-foreground">
                        {p.current_streak}
                        <span className="text-muted-foreground text-[11px] ml-1">dias</span>
                      </span>
                    </Link>
                  </li>
                )
              })}
            </ol>
          )}
        </ContentCard>

        {/* === Top XP === */}
        <ContentCard title="Top XP" description="Ranking de pontuação geral">
          {topXp.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sem XP ainda.</p>
          ) : (
            <ol className="space-y-2">
              {topXp.map((p, i) => {
                const u = userMap.get(p.user_id)
                const medal = i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : null
                return (
                  <li key={p.user_id}>
                    <Link
                      href={`/users/${p.user_id}`}
                      className="glass-subtle flex items-center gap-3 p-2.5 hover:bg-muted/40 transition-colors"
                    >
                      <span className="font-mono text-muted-foreground text-xs w-5 text-right">
                        {medal ? <span className="text-base">{medal}</span> : i + 1}
                      </span>
                      <span className="flex-1 truncate text-sm">{u?.name ?? '(sem nome)'}</span>
                      <span className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground shrink-0">
                        Nv. {p.level}
                      </span>
                      <span className="font-mono tabular-nums text-sm text-foreground w-16 text-right">
                        {formatNumber(p.xp_total)}{' '}
                        <span className="text-muted-foreground text-[10px]">xp</span>
                      </span>
                    </Link>
                  </li>
                )
              })}
            </ol>
          )}
        </ContentCard>
      </div>

      {/* === Badges concedidos === */}
      <ContentCard
        title="Badges concedidos recentemente"
        description="Últimos pacientes a conquistar"
      >
        {(() => {
          const recent = [...rows]
            .filter((r) => r.badges_earned && r.badges_earned.length > 0)
            .sort(
              (a, b) =>
                new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime(),
            )
            .slice(0, 8)

          if (recent.length === 0) {
            return (
              <p className="text-sm text-muted-foreground py-2">
                Ninguém conquistou badge ainda. Quando um paciente fechar o 1º bloco ou
                bater 1000 XP, aparece aqui.
              </p>
            )
          }
          return (
            <ul className="space-y-2">
              {recent.map((p) => {
                const u = userMap.get(p.user_id)
                return (
                  <li
                    key={p.user_id}
                    className="glass-subtle flex items-center gap-3 p-3"
                  >
                    <TrendingUp className="h-4 w-4 text-moss-600 shrink-0" />
                    <Link
                      href={`/users/${p.user_id}`}
                      className="font-medium text-foreground hover:underline"
                    >
                      {u?.name ?? '(sem nome)'}
                    </Link>
                    <div className="flex flex-wrap gap-1.5">
                      {p.badges_earned.map((b) => (
                        <span
                          key={b}
                          className="px-2 py-0.5 text-[10px] font-mono uppercase tracking-widest rounded-full bg-moss-700 text-cream-100"
                        >
                          {b}
                        </span>
                      ))}
                    </div>
                  </li>
                )
              })}
            </ul>
          )
        })()}
      </ContentCard>
    </div>
  )
}
