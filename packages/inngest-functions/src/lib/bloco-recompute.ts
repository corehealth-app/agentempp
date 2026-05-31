import type { ServiceClient } from '@mpp/db'
import { creditDayToBloco, accumulateBloco } from '@mpp/core'

export interface BlocoRecompute {
  userId: string
  daysClosed: number
  correctDeficitBlock: number
  correctBlocksCompleted: number
}

interface SnapRow {
  id: string
  calories_consumed: number | null
  calories_target: number | null
  exercise_calories: number | null
  daily_balance: number | null
  day_status: string | null
  training_done: boolean | null
  gap_reminder_sent_at: string | null
}

/**
 * Recalcula o bloco 7700 de um usuário do ZERO, fiel ao daily-closer:
 * replay de TODOS os dias FECHADOS (`day_closed=true`) aplicando a mesma regra
 * de crédito de `computeProgress` (`newDeficit = max(0, designDeficit − balance)`)
 * + os ajustes do daily-closer:
 *   - sem atividade (0 refeição/treino)           → crédito 0
 *   - user_skipped                                → credita normal (déficit real)
 *   - sub-registro (<50% da meta, não user_skipped) → zera balance; complete
 *       credita só designDeficit, incomplete credita 0
 *   - incomplete_no_response                      → credita só déficit observado
 *   - complete ≥50%                               → designDeficit + déficit observado
 *   designDeficit = recomp ? deficit_level(400/500/600) : 0
 *
 * Validado 2026-05-20: bate EXATO com Gleidson (1967) e Raphaela (0); o crédito
 * do dia 19/05 do Roberto = 832 (confirmado por ele).
 *
 * ⚠️ MANTER EM SINCRONIA com daily-closer.ts (regra de crédito) e
 * progress-calc.ts `computeProgress` (fórmula newDeficit). Se mudar lá, mude aqui.
 */
export async function recomputeUserBloco(
  supabase: ServiceClient,
  userId: string,
): Promise<BlocoRecompute> {
  const { data: prof } = await supabase
    .from('user_profiles')
    .select('current_protocol, deficit_level')
    .eq('user_id', userId)
    .maybeSingle()
  const profTyped = prof as { current_protocol?: string | null; deficit_level?: number | null } | null
  const designDeficit =
    profTyped?.current_protocol === 'recomposicao' ? (profTyped?.deficit_level ?? 500) : 0

  const { data: snaps } = await supabase
    .from('daily_snapshots')
    .select(
      'id, calories_consumed, calories_target, exercise_calories, daily_balance, day_status, training_done, gap_reminder_sent_at',
    )
    .eq('user_id', userId)
    .eq('day_closed', true)
    .order('date', { ascending: true })
  const rows = (snaps ?? []) as unknown as SnapRow[]

  // Contagem de meal_logs por snapshot (proxy de atividade — validado).
  const ids = rows.map((r) => r.id)
  const mealCounts: Record<string, number> = {}
  if (ids.length > 0) {
    const { data: logs } = await supabase
      .from('meal_logs')
      .select('snapshot_id')
      .in('snapshot_id', ids)
    for (const l of (logs ?? []) as Array<{ snapshot_id: string | null }>) {
      if (l.snapshot_id) mealCounts[l.snapshot_id] = (mealCounts[l.snapshot_id] ?? 0) + 1
    }
  }

  // Opção C (Roberto 2026-05-31): pra dias incomplete_no_response, computa se o
  // paciente interagiu após o gap reminder. Faz uma query única dos timestamps
  // de criação dos meal/workout logs do usuário e checa por snapshot.
  const reminderDates = rows
    .filter((r) => r.day_status === 'incomplete_no_response' && r.gap_reminder_sent_at)
    .map((r) => r.gap_reminder_sent_at as string)
  const minReminder = reminderDates.length > 0 ? reminderDates.reduce((a, b) => (a < b ? a : b)) : null
  let allLogTimestamps: string[] = []
  if (minReminder) {
    const [{ data: m }, { data: w }] = await Promise.all([
      supabase
        .from('meal_logs')
        .select('created_at')
        .eq('user_id', userId)
        .gt('created_at', minReminder),
      supabase
        .from('workout_logs')
        .select('created_at')
        .eq('user_id', userId)
        .gt('created_at', minReminder),
    ])
    allLogTimestamps = [
      ...((m ?? []) as Array<{ created_at: string }>).map((r) => r.created_at),
      ...((w ?? []) as Array<{ created_at: string }>).map((r) => r.created_at),
    ]
  }

  const credits = rows.map((s) => {
    const hasAct =
      (mealCounts[s.id] ?? 0) > 0 || (s.exercise_calories ?? 0) > 0 || !!s.training_done
    const interactedAfterReminder =
      s.day_status === 'incomplete_no_response' && s.gap_reminder_sent_at
        ? allLogTimestamps.some((t) => t > (s.gap_reminder_sent_at as string))
        : false
    return creditDayToBloco({
      hasActivity: hasAct,
      dayStatus: (s.day_status ?? null) as
        | 'complete'
        | 'incomplete_no_response'
        | 'user_skipped'
        | null,
      caloriesConsumed: s.calories_consumed ?? 0,
      caloriesTarget: s.calories_target,
      dailyBalance: s.daily_balance ?? 0,
      designDeficit,
      interactedAfterReminder,
    })
  })
  const { deficitBlock, blocksCompleted } = accumulateBloco(credits)
  return {
    userId,
    daysClosed: rows.length,
    correctDeficitBlock: deficitBlock,
    correctBlocksCompleted: blocksCompleted,
  }
}
