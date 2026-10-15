import { loadCalcConfig } from './calc-config-loader.js'
import { loadDailyTargets } from './calc-targets.js'
import { detectCorrectionIntent } from './correction-detector.js'
import type { ToolContext } from './tools/types.js'

export interface WorkoutRegistrationArguments {
  workout_type: string
  duration_min: number
  intensity?: 'leve' | 'moderada' | 'alta'
  notes?: string
  estimated_kcal_from_image?: number
}

export interface WorkoutRegistrationPreparation {
  legacyArguments: {
    p_user_id: string
    p_date: string
    p_workout_type: string
    p_duration_min: number
    p_estimated_kcal: number
    p_intensity: 'leve' | 'moderada' | 'alta' | null
    p_notes: string
    p_performed_at: string
    p_provider_message_id: string | null
    p_calories_target: number | null
    p_protein_target: number | null
    p_replace_recent: boolean
    p_replace_since: string | null
  }
  replacementAudit: {
    correctionWord: string
    oldRows: Array<{
      id: string
      estimated_kcal: number | null
      duration_min: number | null
    }>
  } | null
  finalKcal: number
  kcalSource: 'image' | 'formula'
  formulaKcal: number
  imageDiscarded: boolean
}

export async function prepareWorkoutRegistration(
  args: WorkoutRegistrationArguments,
  ctx: ToolContext,
  referenceTimestamp: Date,
  today: string,
): Promise<WorkoutRegistrationPreparation> {
  // 3ª camada: CORREÇÃO de treino (Roberto 2026-05-27). A intenção e os
  // registros antigos são coletados aqui, mas a substituição só acontece mais
  // abaixo, dentro da mesma transação que insere o treino novo e recalcula os
  // snapshots afetados.
  let replaceRecent = false
  let replaceSince: string | null = null
  let replacementAudit: {
    correctionWord: string
    oldRows: Array<{
      id: string
      estimated_kcal: number | null
      duration_min: number | null
    }>
  } | null = null
  if (args.duration_min != null) {
    const correctionWord = detectCorrectionIntent(ctx.recentUserMessages ?? [])
    if (correctionWord) {
      const twoHoursAgo = new Date(Date.now() - 2 * 3600 * 1000).toISOString()
      const { data: oldOnes, error: oldOnesError } = await ctx.supabase
        .from('workout_logs')
        .select('id, estimated_kcal, duration_min')
        .eq('user_id', ctx.userId)
        .eq('workout_type', args.workout_type)
        .gte('created_at', twoHoursAgo)
      if (oldOnesError) {
        throw new Error(oldOnesError.message ?? 'recent workout lookup failed')
      }
      const oldRows = (oldOnes ?? []) as Array<{
        id: string
        estimated_kcal: number | null
        duration_min: number | null
      }>
      if (oldRows.length > 0) {
        replaceRecent = true
        replaceSince = twoHoursAgo
        replacementAudit = { correctionWord, oldRows }
      }
    }
  }

  // Targets calóricos
  const cfg = await loadCalcConfig(ctx.supabase)
  const tgt = await loadDailyTargets(ctx.supabase, ctx.userId, cfg)

  // Pega peso atual pra calcular kcal (escala linear ref 70kg)
  const { data: prof, error: profileError } = await ctx.supabase
    .from('user_profiles')
    .select('weight_kg')
    .eq('user_id', ctx.userId)
    .maybeSingle()
  if (profileError) throw new Error(profileError.message ?? 'workout profile lookup failed')
  const weightKg = (prof as { weight_kg: number | null } | null)?.weight_kg ?? 70

  // Cálculo determinístico via SQL function (ADR-007). Sempre roda — mesmo
  // quando vamos usar valor da foto, a fórmula serve de baseline pra sanity check.
  const { data: kcalResult, error: kcalErr } = await (
    ctx.supabase as unknown as {
      rpc: (
        n: string,
        p: Record<string, unknown>,
      ) => Promise<{ data: number | null; error: { message?: string } | null }>
    }
  ).rpc('calc_workout_kcal', {
    // App confirm only (see `workoutKcalLookupSlug`): the slug the proposal
    // was calculated with. WhatsApp never sets it and sends the type as is.
    p_slug: ctx.workoutKcalLookupSlug ?? args.workout_type,
    p_duration_min: args.duration_min,
    p_intensity: args.intensity ?? 'moderada',
    p_weight_kg: weightKg,
  })
  if (kcalErr) throw new Error(kcalErr.message ?? 'calc_workout_kcal failed')
  const formulaKcal = Number(kcalResult ?? 0)

  // HÍBRIDO: usa kcal da foto se foi passado E está dentro de range razoável
  // (10%-300% da fórmula). Senão, usa a fórmula. Loga decisão pra auditoria.
  let finalKcal = formulaKcal
  let kcalSource: 'image' | 'formula' = 'formula'
  let imageDiscarded = false
  if (args.estimated_kcal_from_image && args.estimated_kcal_from_image > 0) {
    const ratio = args.estimated_kcal_from_image / Math.max(formulaKcal, 1)
    const inRange = ratio >= 0.1 && ratio <= 3.0
    if (inRange) {
      finalKcal = Math.round(args.estimated_kcal_from_image)
      kcalSource = 'image'
    } else {
      imageDiscarded = true
    }
    // Audit: registra a decisão pra debug + ajuste futuro de threshold
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: imageDiscarded ? 'workout.kcal_image_discarded' : 'workout.kcal_image_used',
      properties: {
        workout_type: args.workout_type,
        duration_min: args.duration_min,
        intensity: args.intensity ?? 'moderada',
        weight_kg: weightKg,
        formula_kcal: formulaKcal,
        image_kcal: args.estimated_kcal_from_image,
        ratio: +ratio.toFixed(2),
        chosen: kcalSource,
      },
    })
  }

  const workoutNotes = args.notes
    ? `${args.notes} [src=${kcalSource}]`
    : `[kcal_source=${kcalSource}, formula=${formulaKcal}, image=${args.estimated_kcal_from_image ?? 'n/a'}]`

  return {
    legacyArguments: {
      p_user_id: ctx.userId,
      p_date: today,
      p_workout_type: args.workout_type,
      p_duration_min: args.duration_min,
      p_estimated_kcal: finalKcal,
      p_intensity: args.intensity ?? null,
      p_notes: workoutNotes,
      p_performed_at: referenceTimestamp.toISOString(),
      p_provider_message_id: ctx.providerMessageId ?? null,
      p_calories_target: tgt.calories_target,
      p_protein_target: tgt.protein_target,
      p_replace_recent: replaceRecent,
      p_replace_since: replaceSince,
    },
    replacementAudit,
    finalKcal,
    kcalSource,
    formulaKcal,
    imageDiscarded,
  }
}
