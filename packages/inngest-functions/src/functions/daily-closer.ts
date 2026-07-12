import { calcDailyXP, computeProgress, creditDayToBloco } from '@mpp/core'
import type { DailySnapshot, UserProgress } from '@mpp/core'
import {
  getGapForDate,
  getLocalDateMinusDays,
  getLocalDayUtcBounds,
  getLocalHour,
  loadCalcConfig,
  loadDailyTargets,
} from '@mpp/agent'
import { inngest } from '../client.js'
import { finalizeDailyClose } from '../lib/daily-close-finalizer.js'
import { resolveClosedDayStatus } from '../lib/day-status-policy.js'
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
      const { data, error } = await supabase
        .from('users')
        .select('id, timezone')
        .eq('status', 'active')
      if (error) throw new Error(error.message ?? 'active users lookup failed')
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
  const { data: existing, error: existingError } = await (supabase as any)
    .from('daily_snapshots')
    .select('id, day_closed, day_status, gap_reminder_sent_at')
    .eq('user_id', userId)
    .eq('date', yesterday)
    .maybeSingle()
  if (existingError) throw new Error(existingError.message ?? 'snapshot close lookup failed')
  const existingTyped = existing as {
    id: string
    day_closed: boolean | null
    day_status: string | null
    gap_reminder_sent_at: string | null
  } | null

  if (existingTyped?.day_closed) return { skipped: true, reason: 'já fechado' }

  // Lê histórico do dia
  const { startIso: startOfDay, endExclusiveIso: endOfDay } = getLocalDayUtcBounds(
    userTimezone,
    yesterday,
  )

  const [mealsResult, workoutsResult, messagesResult] = await Promise.all([
    supabase
      .from('meal_logs')
      .select('food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at')
      .eq('user_id', userId)
      .gte('consumed_at', startOfDay)
      .lt('consumed_at', endOfDay),
    supabase
      .from('workout_logs')
      .select('workout_type, duration_min, estimated_kcal, performed_at')
      .eq('user_id', userId)
      .gte('performed_at', startOfDay)
      .lt('performed_at', endOfDay),
    supabase
      .from('messages')
      .select('direction, content')
      .eq('user_id', userId)
      .gte('created_at', startOfDay)
      .lt('created_at', endOfDay)
      .limit(50),
  ])
  const historyError = mealsResult.error ?? workoutsResult.error ?? messagesResult.error
  if (historyError) throw new Error(historyError.message ?? 'daily close history lookup failed')
  const meals = mealsResult.data
  const workouts = workoutsResult.data
  const messages = messagesResult.data

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
    // BUG corrigido (Gleidson 2026-05-18): paciente sumiu por 3 dias mas
    // current_streak ficou congelado em 2 (LLM continuou dizendo "2 dias firmes"
    // nas msgs automáticas). Causa: daily-closer skipava dia inativo sem tocar
    // user_progress.current_streak → ficava no valor anterior.
    //
    // Fix: ZERA current_streak quando há gap >= 2 dias desde last_active_date.
    // (1 dia de gap é tolerado — paciente pode pular um dia esporadicamente.)
    const { data: prog, error: progressLookupError } = await supabase
      .from('user_progress')
      .select('current_streak, last_active_date')
      .eq('user_id', userId)
      .maybeSingle()
    if (progressLookupError) {
      throw new Error(progressLookupError.message ?? 'inactive progress lookup failed')
    }
    const progTyped = prog as {
      current_streak: number | null
      last_active_date: string | null
    } | null
    if (progTyped?.current_streak && progTyped.current_streak > 0 && progTyped.last_active_date) {
      // Calcula gap em dias entre yesterday e last_active_date
      const lastActive = new Date(progTyped.last_active_date)
      const yesterdayDate = new Date(yesterday)
      const gapDays = Math.floor(
        (yesterdayDate.getTime() - lastActive.getTime()) / (1000 * 60 * 60 * 24),
      )
      if (gapDays >= 2) {
        const { error: streakResetError } = await supabase
          .from('user_progress')
          .update({ current_streak: 0, updated_at: new Date().toISOString() })
          .eq('user_id', userId)
        if (streakResetError) {
          throw new Error(streakResetError.message ?? 'inactive streak reset failed')
        }
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'streak.reset_inactive',
          properties: {
            previous_streak: progTyped.current_streak,
            last_active_date: progTyped.last_active_date,
            gap_days: gapDays,
            yesterday,
          },
        })
      }
    }
    // Telemetria: paciente totalmente inativo no dia (sem refeição, treino
    // nem mensagem). Emite skipped pra dashboard distinguir "fechou" de
    // "inativo" — sinal útil pra Eduardo ver quem sumiu.
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'daily_closer.skipped',
      properties: { reason: 'inactive_day', snapshot_date: yesterday },
    })
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
  const { data: profile, error: profileError } = await supabase
    .from('user_profiles')
    .select('current_protocol, deficit_level')
    .eq('user_id', userId)
    .maybeSingle()
  if (profileError) throw new Error(profileError.message ?? 'daily close profile lookup failed')

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

  // Mantém o snapshot aberto enquanto calcula status e progresso. A RPC final
  // fecha snapshot + user_progress em uma única transação.
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
  }

  const { data: snap, error: snapshotUpsertError } = await supabase
    .from('daily_snapshots')
    .upsert(snapshotData, { onConflict: 'user_id,date' })
    .select('*')
    .single()

  if (snapshotUpsertError) {
    throw new Error(snapshotUpsertError.message ?? 'failed to upsert snapshot')
  }
  if (!snap) throw new Error('failed to upsert snapshot')

  // computeProgress
  const { data: prevProgress, error: prevProgressError } = await supabase
    .from('user_progress')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle()
  if (prevProgressError) {
    throw new Error(prevProgressError.message ?? 'previous progress lookup failed')
  }

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
  const gapInfo = hasActivity
    ? await getGapForDate(supabase, userId, userTimezone, yesterday)
    : null
  const finalDayStatus = resolveClosedDayStatus({
    existingDayStatus: existingTyped?.day_status ?? null,
    reminderSent: Boolean(existingTyped?.gap_reminder_sent_at),
    hasActivity,
    gapCount: gapInfo?.gap.size ?? 0,
    skippedCount: gapInfo?.skipped.size ?? 0,
    fallbackPattern: gapInfo?.pattern.fallbackUsed ?? false,
  })
  if (finalDayStatus === 'incomplete_no_response') {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('product_events').insert({
      user_id: userId,
      event: 'bloco7700.skipped_incomplete_day',
      properties: {
        date: yesterday,
        gap: Array.from(gapInfo?.gap ?? []),
        reason: 'lembrete enviado, paciente não respondeu',
      },
    })
  }

  // O CRÉDITO do bloco vem do engine (creditDayToBloco — fonte única da regra,
  // ver @mpp/core/engine/bloco + docs/CALCULO-MPP.md §3). As condições abaixo
  // só EMITEM os eventos de log (skipped_*); a decisão de quanto creditar é do
  // engine, não daqui (não duplicar a regra).
  if (!hasActivity) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'bloco7700.skipped_inactive_day',
      properties: { date: yesterday, calories_target: targets.calories_target },
    })
  } else if (
    finalDayStatus !== 'user_skipped' &&
    targets.calories_target != null &&
    targets.calories_target > 0 &&
    kcalConsumed < 0.5 * targets.calories_target
  ) {
    // SUB-REGISTRO (Luciana 2026-05-20): consumo < 50% da meta = déficit
    // observado FAKE. O engine zera esse crédito (complete credita só o
    // designDeficit; incomplete credita 0; user_skipped não entra aqui). Aqui
    // só logamos o evento pra auditoria.
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'bloco7700.skipped_subregistro',
      properties: {
        date: yesterday,
        day_status: finalDayStatus,
        calories_consumed: Math.round(kcalConsumed),
        calories_target: targets.calories_target,
        pct: Math.round((kcalConsumed / targets.calories_target) * 100),
      },
    })
  }

  const dayCredit = creditDayToBloco({
    hasActivity,
    dayStatus: finalDayStatus,
    caloriesConsumed: kcalConsumed,
    caloriesTarget: targets.calories_target,
    dailyBalance: snap.daily_balance ?? 0,
    designDeficit,
  })

  const next = computeProgress(dailySnap, prev, calcConfig, dayCredit)

  const finalized = await finalizeDailyClose(supabase, {
    userId,
    snapshotId: snap.id,
    dayStatus: finalDayStatus,
    xpTotal: next.xpTotal,
    level: next.level,
    currentStreak: next.currentStreak,
    longestStreak: next.longestStreak,
    blocksCompleted: next.blocksCompleted,
    deficitBlock: next.deficitBlock,
    badgesEarned: next.badgesEarned,
    lastActiveDate: yesterday,
    closedAt: new Date().toISOString(),
  })
  if (!finalized.applied) {
    return { skipped: true, reason: 'fechado concorrentemente' }
  }

  // Bonus: se chegou em badge nova, registra evento de produto
  const newBadges = next.badgesEarned.filter((b) => !prev.badgesEarned.includes(b))
  if (newBadges.length > 0) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'badge.earned',
      properties: { badges: newBadges, snapshot_date: yesterday },
    })
  }

  // Eduardo 2026-06-03: destacar quando paciente FECHA um novo bloco 7700
  // (marco grande do método — ~1kg de gordura perdido por bloco no modelo).
  // O engagement matinal do próximo dia detecta esse evento e injeta no
  // contexto pro LLM mencionar de forma destacada (sem inventar números).
  if (next.blocksCompleted > prev.blocksCompleted) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'bloco7700.block_completed',
      properties: {
        snapshot_date: yesterday,
        previous_count: prev.blocksCompleted,
        new_count: next.blocksCompleted,
        kg_estimate: next.blocksCompleted, // 1kg = 7700 kcal no modelo MPP
      },
    })
  }

  // Telemetria P0 (audit 2026-06-13): antes o único sinal de fechamento era
  // o upsert em daily_snapshots. Agora também grava product_events pra
  // dashboard distinguir "fechou+ativo" de "skipped". Outros skipped (fora
  // janela / já fechado) NÃO emitem — rodam 24x11 vezes/dia e inflariam
  // product_events sem ganho de sinal.
  //
  // ORDEM IMPORTANTE (review adversarial HIGH): emite ANTES de
  // checkReevaluation. Se a reavaliação falhar (5xx Supabase ao ler/escrever
  // user_progress.next_reevaluation), o snapshot já foi gravado com
  // day_closed=true, user_progress já foi upsertado, badges/bloco já emitidos.
  // Logar o completed por último escondia fechamentos parciais — agora o
  // dashboard conta corretamente.
  await supabase.from('product_events').insert({
    user_id: userId,
    event: 'daily_closer.completed',
    properties: {
      snapshot_date: yesterday,
      calories_consumed: Math.round(kcalConsumed),
      calories_target: targets.calories_target,
      exercise_calories: Math.round(exerciseKcal),
      training_done: trainingDone,
      day_status: finalDayStatus,
      xp_earned: xpEarned,
      blocks_completed: next.blocksCompleted,
      blocks_completed_delta: next.blocksCompleted - prev.blocksCompleted,
    },
  })

  // REAVALIAÇÃO 14 DIAS (Roberto 2026-05-20): MPP prevê reavaliação periódica
  // (peso/BF%/meta) a cada 14 dias. A coluna user_progress.next_reevaluation
  // existia mas nunca era populada nem checada. Agora:
  //  - bootstrap: se NULL, seta = primeiro_snapshot + 14 dias
  //  - due: se yesterday >= next_reevaluation, loga evento + avança +14d.
  //    A MENSAGEM ao paciente sai pelo engagement matinal (cafe_da_manha) que
  //    detecta o evento `reevaluation.due` — evita mandar 3h da manhã.
  //
  // Try/catch isolado: falha aqui não afeta o fechamento já registrado.
  try {
    await checkReevaluation(supabase, userId, yesterday)
  } catch (err) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'reevaluation.check_failed',
      properties: {
        snapshot_date: yesterday,
        error: String(err instanceof Error ? err.message : err).slice(0, 300),
      },
    })
  }

  return { skipped: false }
}

/**
 * Detecta e marca reavaliação de 14 dias. Loga `reevaluation.due` quando
 * vence — engagement matinal pega e pede o peso atualizado ao paciente.
 */
async function checkReevaluation(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  userId: string,
  closingDate: string,
): Promise<void> {
  const { data: prog } = await supabase
    .from('user_progress')
    .select('next_reevaluation')
    .eq('user_id', userId)
    .maybeSingle()
  const nextReval = (prog as { next_reevaluation: string | null } | null)?.next_reevaluation

  if (!nextReval) {
    // Bootstrap: primeiro snapshot do paciente + 14 dias
    const { data: firstSnap } = await supabase
      .from('daily_snapshots')
      .select('date')
      .eq('user_id', userId)
      .order('date', { ascending: true })
      .limit(1)
      .maybeSingle()
    const firstDate = (firstSnap as { date: string } | null)?.date
    if (firstDate) {
      const d = new Date(firstDate)
      d.setDate(d.getDate() + 14)
      await supabase
        .from('user_progress')
        .update({ next_reevaluation: d.toISOString().slice(0, 10) })
        .eq('user_id', userId)
    }
    return
  }

  // Due? closingDate (data fechada) >= next_reevaluation
  if (closingDate >= nextReval) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: 'reevaluation.due',
      properties: { due_date: nextReval, closing_date: closingDate },
    })
    // Avança +14 dias a partir da data devida (não da data fechada — mantém
    // cadência fixa de 14 em 14 mesmo se houve atraso no fechamento).
    const d = new Date(nextReval)
    d.setDate(d.getDate() + 14)
    await supabase
      .from('user_progress')
      .update({ next_reevaluation: d.toISOString().slice(0, 10) })
      .eq('user_id', userId)
  }
}

// Helpers de timezone agora vêm de @mpp/agent (timezone-utils.ts).
