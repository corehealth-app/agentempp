import { computeProgress } from '@mpp/core'
import type { DailySnapshot, UserProgress } from '@mpp/core'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Worker: fechamento diário.
 *
 * Disparado 4×/dia (00:30, 01:30, 02:30, 03:30) — cobre múltiplos timezones.
 * Para cada usuário ativo cuja "meia-noite local" passou:
 *   1. Lê histórico do dia (mensagens, meal_logs, workout_logs)
 *   2. LLM batch (DeepSeek V3) extrai snapshot estruturado
 *   3. Insere/atualiza daily_snapshots (idempotente por user+date)
 *   4. Chama computeProgress (XP, streak, blocks, badges)
 *   5. Atualiza user_progress
 */
export const dailyCloserFn = inngest.createFunction(
  { id: 'daily-closer', retries: 2, concurrency: { limit: 5 } },
  { event: 'day.close.tick' },
  async ({ event, step, logger }) => {
    const { hour } = event.data
    logger.info('Daily closer tick', { hour })

    // Lista usuários cujo timezone bate com a hora atual UTC
    const users = await step.run('list-users', async () => {
      const { supabase } = createWorkerDeps()
      // Pega users cujo timezone tem offset que faz "agora" ser ~00h local
      // Simplificação MVP: pega todos active e a função verifica internamente
      const { data } = await supabase
        .from('users')
        .select('id, timezone')
        .eq('status', 'active')
      return data ?? []
    })

    let processed = 0
    let skipped = 0
    let failed = 0

    for (const user of users) {
      try {
        const result = await step.run(`close-${user.id}`, async () =>
          closeUserDay(user.id, user.timezone ?? 'America/Sao_Paulo', hour),
        )
        if (result.skipped) skipped++
        else processed++
      } catch (e) {
        logger.error('Failed to close user day', { userId: user.id, error: String(e) })
        failed++
      }
    }

    return { processed, skipped, failed, total: users.length }
  },
)

async function closeUserDay(
  userId: string,
  userTimezone: string,
  hourUtc: number,
): Promise<{ skipped: boolean; reason?: string }> {
  const { supabase, llm } = createWorkerDeps()

  // Verifica se "agora" no fuso do user é entre 00h e 04h
  const localHour = getLocalHour(userTimezone)
  if (localHour > 4) return { skipped: true, reason: `local hour ${localHour} fora janela` }

  // Data local de "ontem" (que vamos fechar)
  const yesterday = getLocalDateMinusDays(userTimezone, 1)

  // Já fechado?
  const { data: existing } = await supabase
    .from('daily_snapshots')
    .select('id, day_closed')
    .eq('user_id', userId)
    .eq('date', yesterday)
    .maybeSingle()

  if (existing?.day_closed) return { skipped: true, reason: 'já fechado' }

  // Lê histórico do dia
  const startOfDay = `${yesterday}T00:00:00${tzOffset(userTimezone)}`
  const endOfDay = `${yesterday}T23:59:59${tzOffset(userTimezone)}`

  const [{ data: meals }, { data: workouts }, { data: messages }] = await Promise.all([
    supabase
      .from('meal_logs')
      .select('food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at')
      .eq('user_id', userId)
      .gte('consumed_at', startOfDay)
      .lte('consumed_at', endOfDay),
    supabase
      .from('workout_logs')
      .select('workout_type, duration_min, estimated_kcal, performed_at')
      .eq('user_id', userId)
      .gte('performed_at', startOfDay)
      .lte('performed_at', endOfDay),
    supabase
      .from('messages')
      .select('direction, content')
      .eq('user_id', userId)
      .gte('created_at', startOfDay)
      .lte('created_at', endOfDay)
      .limit(50),
  ])

  if ((!meals || meals.length === 0) && (!workouts || workouts.length === 0)) {
    return { skipped: true, reason: 'sem atividade' }
  }

  // Calcula totais determinísticos via meal_logs/workout_logs
  const kcalConsumed = (meals ?? []).reduce((s, m) => s + (Number(m.kcal) || 0), 0)
  const proteinG = (meals ?? []).reduce((s, m) => s + (Number(m.protein_g) || 0), 0)
  const carbsG = (meals ?? []).reduce((s, m) => s + (Number(m.carbs_g) || 0), 0)
  const fatG = (meals ?? []).reduce((s, m) => s + (Number(m.fat_g) || 0), 0)
  const exerciseKcal = (workouts ?? []).reduce(
    (s, w) => s + (Number(w.estimated_kcal) || 0),
    0,
  )
  const trainingDone = (workouts ?? []).length > 0

  // Pega target do profile
  const { data: profile } = await supabase
    .from('user_profiles')
    .select('current_protocol')
    .eq('user_id', userId)
    .maybeSingle()

  // XP base por dia: 10 + 5 se treinou + bônus por proteína atingida
  const xpEarned = 10 + (trainingDone ? 5 : 0) + (proteinG >= 100 ? 5 : 0)

  // Upsert daily_snapshot
  const snapshotData = {
    user_id: userId,
    date: yesterday,
    calories_consumed: Math.round(kcalConsumed),
    protein_g: Math.round(proteinG * 10) / 10,
    carbs_g: Math.round(carbsG * 10) / 10,
    fat_g: Math.round(fatG * 10) / 10,
    exercise_calories: Math.round(exerciseKcal),
    training_done: trainingDone,
    xp_earned: xpEarned,
    current_protocol: profile?.current_protocol ?? null,
    day_closed: true,
    closed_at: new Date().toISOString(),
  }

  const { data: snap } = await supabase
    .from('daily_snapshots')
    .upsert(snapshotData, { onConflict: 'user_id,date' })
    .select('*')
    .single()

  if (!snap) throw new Error('failed to upsert snapshot')

  // computeProgress
  const { data: prevProgress } = await supabase
    .from('user_progress')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle()

  const prev: UserProgress = {
    xpTotal: prevProgress?.xp_total ?? 0,
    level: prevProgress?.level ?? 1,
    currentStreak: prevProgress?.current_streak ?? 0,
    longestStreak: prevProgress?.longest_streak ?? 0,
    blocksCompleted: prevProgress?.blocks_completed ?? 0,
    deficitBlock: prevProgress?.deficit_block ?? 0,
    badgesEarned: prevProgress?.badges_earned ?? [],
    lastActiveDate: prevProgress?.last_active_date
      ? new Date(prevProgress.last_active_date)
      : null,
  }

  const dailySnap: DailySnapshot = {
    date: new Date(yesterday),
    caloriesConsumed: snap.calories_consumed,
    caloriesTarget: snap.calories_target,
    proteinG: Number(snap.protein_g),
    proteinTarget: snap.protein_target ? Number(snap.protein_target) : null,
    exerciseCalories: snap.exercise_calories,
    trainingDone: snap.training_done,
    xpEarned: snap.xp_earned,
    dailyBalance: snap.daily_balance ?? 0,
  }

  const next = computeProgress(dailySnap, prev)

  await supabase
    .from('user_progress')
    .upsert(
      {
        user_id: userId,
        xp_total: next.xpTotal,
        level: next.level,
        current_streak: next.currentStreak,
        longest_streak: next.longestStreak,
        blocks_completed: next.blocksCompleted,
        deficit_block: next.deficitBlock,
        badges_earned: next.badgesEarned,
        last_active_date: yesterday,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'user_id' },
    )

  // Bonus: se chegou em badge nova, registra evento de produto
  const newBadges = next.badgesEarned.filter((b) => !prev.badgesEarned.includes(b))
  if (newBadges.length > 0) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'badge.earned',
      properties: { badges: newBadges, snapshot_date: yesterday },
    })
  }

  return { skipped: false }
}

// ----------------------------------------------------------------------------
// Helpers de timezone
// ----------------------------------------------------------------------------
function getLocalHour(tz: string): number {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour: '2-digit',
    hour12: false,
  })
  const parts = fmt.formatToParts(new Date())
  const h = parts.find((p) => p.type === 'hour')?.value ?? '0'
  return Number.parseInt(h, 10)
}

function getLocalDateMinusDays(tz: string, days: number): string {
  const now = new Date()
  const offset = days * 24 * 60 * 60 * 1000
  const past = new Date(now.getTime() - offset)
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
  return fmt.format(past)
}

function tzOffset(tz: string): string {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    timeZoneName: 'longOffset',
  })
  const parts = fmt.formatToParts(new Date())
  const offset = parts.find((p) => p.type === 'timeZoneName')?.value ?? 'GMT-03:00'
  return offset.replace('GMT', '').replace('GMT', '') || '-03:00'
}
