import { calcDailyXP, computeProgress } from '@mpp/core'
import type { DailySnapshot, UserProgress } from '@mpp/core'
import {
  getGapForDate,
  getLocalDateMinusDays,
  getLocalHour,
  getTzOffset,
  loadCalcConfig,
  loadDailyTargets,
} from '@mpp/agent'
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
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: existing } = await (supabase as any)
    .from('daily_snapshots')
    .select('id, day_closed, day_status, gap_reminder_sent_at')
    .eq('user_id', userId)
    .eq('date', yesterday)
    .maybeSingle()
  const existingTyped = existing as {
    id: string
    day_closed: boolean | null
    day_status: string | null
    gap_reminder_sent_at: string | null
  } | null

  if (existingTyped?.day_closed) return { skipped: true, reason: 'já fechado' }

  // Lê histórico do dia
  const startOfDay = `${yesterday}T00:00:00${getTzOffset(userTimezone)}`
  const endOfDay = `${yesterday}T23:59:59${getTzOffset(userTimezone)}`

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

  // Verifica se houve QUALQUER atividade no dia (meal, workout ou msg IN).
  // Antes: skipava se sem meal/workout → quebrava streak de quem só conversou.
  // Agora: msg IN também conta como "dia ativo" — cria snapshot vazio com
  // training_done=false mas atualiza last_active_date pra preservar streak.
  const hadIncomingMsgs =
    (messages ?? []).some((m) => (m as { direction: string }).direction === 'in')
  if (
    (!meals || meals.length === 0) &&
    (!workouts || workouts.length === 0) &&
    !hadIncomingMsgs
  ) {
    return { skipped: true, reason: 'sem atividade nem conversa' }
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

  // Pega target do profile + deficit_level (pra bloco 7700 incluir design_deficit
  // estrutural da recomp). Sem isso, paciente on-plan (consumed=target) tinha
  // dailyBalance=0 e bloco nunca crescia. Roberto reportou em 2026-05-09 e
  // 2026-05-12. A migration SQL daily_close_user já corrige; replicamos aqui.
  const { data: profile } = await supabase
    .from('user_profiles')
    .select('current_protocol, deficit_level')
    .eq('user_id', userId)
    .maybeSingle()

  // Carrega config editável (cache 60s). Constantes vêm de global_config calc.*
  const calcConfig = await loadCalcConfig(supabase)

  // Targets calóricos/proteína computados via TDEE - deficit_level (recomp)
  // ou TDEE + deficit (ganho_massa). Sem isso daily_balance fica positivo
  // sempre e bloco 7700 nunca incrementa.
  const targets = await loadDailyTargets(supabase, userId, calcConfig)

  // XP por dia: tabela MPP completa (doc Notion) — peso, refeições, foto,
  // proteína, calorias dentro da janela, treino, dia perfeito.
  // Campos não-tracked ainda (água, sono, passos, persistência) ficam zerados.
  const mealsLogged = meals?.length ?? 0
  const xpEarned = calcDailyXP(
    {
      trainingDone,
      proteinG,
      caloriesConsumed: kcalConsumed,
      caloriesTarget: targets.calories_target ?? undefined,
      proteinTarget: targets.protein_target ?? undefined,
      mealsLogged,
      // photo/weight tracking ainda não implementados — quando houver, passar aqui
      photoLogged: false,
      weightLogged: false,
    },
    calcConfig,
  )

  // Upsert daily_snapshot. day_status é atualizado em UPDATE separado abaixo
  // (depois de computar gap-check), pra evitar reordenação grande dessa função.
  const snapshotData = {
    user_id: userId,
    date: yesterday,
    calories_consumed: Math.round(kcalConsumed),
    calories_target: targets.calories_target,
    protein_g: Math.round(proteinG * 10) / 10,
    protein_target: targets.protein_target,
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

  // Design deficit estrutural: só recomp usa (400/500/600 conforme fome).
  // Outros protocolos (ganho_massa, manutenção) = 0 — bloco só conta extras.
  const profileTyped = profile as { current_protocol?: string | null; deficit_level?: number | null } | null
  const designDeficit =
    profileTyped?.current_protocol === 'recomposicao'
      ? (profileTyped?.deficit_level ?? 500)
      : 0

  // BUG (Erika 2026-05-14): paciente fez onboarding ontem, não registrou
  // nenhuma refeição, dia fechou e somou 1.969 kcal no bloco 7700 — porque
  // o close usou consumed=0 vs target=1969 = "deficit" de 1969. Isso é
  // alucinação: o paciente provavelmente comeu, só não registrou. Mensagem
  // recebida ≠ evidência de consumo.
  //
  // Regra: se NÃO há refeição NEM treino registrados, o bloco NÃO ganha
  // crédito desse dia (passa designDeficit=0 ao computeProgress; o snapshot
  // permanece salvo pra histórico/streak). Conversa avulsa não conta.
  const hasActivity = (meals?.length ?? 0) > 0 || (workouts?.length ?? 0) > 0

  // GAP CHECK FINAL (Roberto 2026-05-16): se o gap-checker mandou lembrete às
  // 21h-23h local e paciente NÃO RESPONDEU registrando nem dizendo "pulei",
  // o gap continua. Fecha como incomplete_no_response → NÃO credita bloco 7700.
  // Sem isso, paciente que esquece de registrar jantar ganha bloco fake.
  //
  // BUG corrigido (Roberto+Paulo+Luciana 2026-05-17): chamada anterior usava
  // getTodayGap() que retorna gap de "hoje" (dia em curso). Como daily-closer
  // roda 00h-04h local fechando "ontem", o gap retornado era do dia recém-
  // iniciado (com tudo zerado) → snapshots de ontem marcados incomplete
  // injustamente. Fix: getGapForDate(yesterday) — checa o dia certo.
  //
  // Só aplica se:
  //  - há padrão de refeição estabelecido (≥5 dias ativos no histórico 14d)
  //  - lembrete FOI enviado (gap_reminder_sent_at IS NOT NULL)
  //  - gap continua na DATA FECHANDO (paciente não registrou nem disse "pulei")
  let dayStatus: 'complete' | 'incomplete_no_response' = 'complete'
  if (existingTyped?.gap_reminder_sent_at && hasActivity) {
    const gapInfo = await getGapForDate(supabase, userId, userTimezone, yesterday)
    if (gapInfo.gap.size > 0 && !gapInfo.pattern.fallbackUsed) {
      dayStatus = 'incomplete_no_response'
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('product_events').insert({
        user_id: userId,
        event: 'bloco7700.skipped_incomplete_day',
        properties: {
          date: yesterday,
          gap: Array.from(gapInfo.gap),
          reason: 'lembrete enviado, paciente não respondeu',
        },
      })
    }
  }

  // Persiste day_status no snapshot (UPDATE separado — coluna ainda não está
  // nos types gerados do supabase, regerar com `pnpm db:types` depois).
  // Preserva user_skipped se já estava setado (paciente confirmou explicitamente).
  const finalDayStatus =
    existingTyped?.day_status === 'user_skipped' ? 'user_skipped' : dayStatus
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any)
    .from('daily_snapshots')
    .update({ day_status: finalDayStatus })
    .eq('id', snap.id)

  const blocoCreditaThisDay =
    hasActivity && (finalDayStatus === 'complete' || finalDayStatus === 'user_skipped')
  const effectiveDesignDeficit = blocoCreditaThisDay ? designDeficit : 0
  if (!hasActivity) {
    // Zera o dailyBalance pra computeProgress não creditar nada via -balance.
    // Snapshot permanece com o balance real pra fins de display/log.
    dailySnap.dailyBalance = 0
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'bloco7700.skipped_inactive_day',
      properties: { date: yesterday, calories_target: targets.calories_target },
    })
  }

  const next = computeProgress(dailySnap, prev, calcConfig, effectiveDesignDeficit)

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

// Helpers de timezone agora vêm de @mpp/agent (timezone-utils.ts).
