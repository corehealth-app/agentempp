import {
  buildConfirmedMealArgs,
  calcMealMacros,
  createPendingRegistration,
  getLocalDateString,
  isUnresolvedNutritionSource,
  type MealCalcResult,
  type MealItemInput,
  registraRefeicao,
  registraTreino,
  resolveTrustedNutritionLabel,
} from '@mpp/agent'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import type { RegistrationProposalInput } from './contracts'
import { MobileApiError } from './http'
import { DEFAULT_MEAL_CONFIDENCE_THRESHOLD } from './meal-draft-service'
import { createSupabaseMediaDependencies } from './supabase-media'
import { sanitizePendingProposal } from './read-model'

interface ProposalTiming {
  localDate: string
  requestKey: string
  timestamp: string
  timezone: string
}

type MealProposalInput = Extract<RegistrationProposalInput, { kind: 'meal' }>
type WorkoutProposalInput = Extract<RegistrationProposalInput, { kind: 'workout' }>

const pendingMealItemSchema = z.object({
  name: z.string().min(1),
  food_db_id: z.number().int().positive().nullable().optional(),
  nutrition_source: z.string().nullable().optional(),
  quantity_g: z.number().positive(),
  display_qty: z.number().positive().nullable().optional(),
  display_unit: z.string().nullable().optional(),
  user_kcal: z.number().nonnegative().nullable().optional(),
  kcal: z.number().nonnegative(),
  protein_g: z.number().nonnegative(),
  carbs_g: z.number().nonnegative(),
  fat_g: z.number().nonnegative(),
  preparation_options: z.array(z.string()).nullable().optional(),
})

const pendingMealProposalSchema = z.object({
  kind: z.literal('meal'),
  mealType: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
  items: z.array(pendingMealItemSchema).min(1).max(30),
  source_provider_message_id: z.string().min(1),
  source_timestamp: z.string().datetime({ offset: true }),
  source_timezone: z.string().min(1),
  source_local_date: z.string().date(),
})

const pendingWorkoutProposalSchema = z.object({
  kind: z.literal('workout'),
  workoutType: z.string().min(1),
  durationMin: z.number().int().positive(),
  kcalEst: z.number().int().nonnegative(),
  intensity: z.enum(['leve', 'moderada', 'alta']),
  source_provider_message_id: z.string().min(1),
  source_timestamp: z.string().datetime({ offset: true }),
  source_timezone: z.string().min(1),
  source_local_date: z.string().date(),
})

function normalizeFoodName(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
}

export function buildMealPendingProposal(
  input: MealProposalInput,
  calculation: MealCalcResult,
  timing: ProposalTiming,
) {
  const overrides = new Map(
    input.items
      .filter((item) => item.user_kcal !== undefined)
      .map((item) => [normalizeFoodName(item.food_name), item.user_kcal]),
  )
  return {
    kind: 'meal' as const,
    mealType: input.meal_type,
    items: calculation.items.map((item, index) => ({
      name: item.food_name,
      food_db_id: item.matched_taco_id,
      nutrition_source: item.source,
      quantity_g: item.quantity_g,
      display_qty: item.display_qty ?? null,
      display_unit: item.display_unit ?? null,
      user_kcal: overrides.get(normalizeFoodName(item.food_name)) ?? null,
      ...(item.preparation_options ? { preparation_options: item.preparation_options } : {}),
      // Each input item yields exactly one calculated item, in order.
      ...(input.items[index]?.quantity_basis
        ? { quantity_basis: input.items[index]?.quantity_basis }
        : {}),
      ...(input.items[index]?.candidate_id
        ? { candidate_id: input.items[index]?.candidate_id }
        : {}),
      kcal: item.kcal,
      protein_g: item.protein_g,
      carbs_g: item.carbs_g,
      fat_g: item.fat_g,
    })),
    totals: {
      kcal: calculation.totals.kcal,
      protein_g: calculation.totals.protein_g,
      carbs_g: calculation.totals.carbs_g,
      fat_g: calculation.totals.fat_g,
    },
    userWarnings: calculation.user_warnings,
    sourceContentType: input.source?.channel ?? 'mobile',
    ...(input.source?.media_asset_id
      ? { source_media_asset_id: input.source.media_asset_id }
      : {}),
    source_provider_message_id: timing.requestKey,
    source_timestamp: timing.timestamp,
    source_timezone: timing.timezone,
    source_local_date: timing.localDate,
    replace: false,
    express_eligible: false,
  }
}

function buildWorkoutPendingProposal(
  input: WorkoutProposalInput,
  estimatedKcal: number,
  timing: ProposalTiming,
) {
  return {
    kind: 'workout' as const,
    workoutType: input.workout_type,
    durationMin: input.duration_min,
    kcalEst: estimatedKcal,
    intensity: input.intensity,
    sourceContentType: 'mobile',
    source_provider_message_id: timing.requestKey,
    source_timestamp: timing.timestamp,
    source_timezone: timing.timezone,
    source_local_date: timing.localDate,
    raw_args: {
      workout_type: input.workout_type,
      duration_min: input.duration_min,
      intensity: input.intensity,
    },
    express_eligible: false,
  }
}

function proposalTimestamp(input: RegistrationProposalInput, now: Date): Date {
  const supplied = input.kind === 'meal' ? input.consumed_at : input.performed_at
  return supplied ? new Date(supplied) : now
}

function finite(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
}

function labelValues(value: unknown) {
  const source = typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {}
  return {
    kcal: finite(source.kcal),
    protein_g: finite(source.protein_g),
    carbs_g: finite(source.carbs_g),
    fat_g: finite(source.fat_g),
  }
}

async function labelConfidenceThreshold(supabase: ServiceClient): Promise<number> {
  const { data } = await supabase
    .from('global_config')
    .select('value')
    .eq('key', 'vision.meal.confidence_threshold')
    .maybeSingle()
  const value = Number((data as { value?: unknown } | null)?.value)
  return Number.isFinite(value) && value > 0 && value <= 1
    ? value
    : DEFAULT_MEAL_CONFIDENCE_THRESHOLD
}

/**
 * Items as the calculation receives them. The origin media must belong to the
 * patient, match the channel and be processed. A nutrition label is applied
 * only to the one item the patient tied it to, read again from the processed
 * media; a label that cannot be trusted refuses the proposal instead of being
 * ignored in silence.
 */
export async function mealItemsForCalculation(
  supabase: ServiceClient,
  userId: string,
  input: MealProposalInput,
): Promise<MealItemInput[]> {
  const items: MealItemInput[] = input.items.map((item) => ({
    food_name: item.food_name,
    quantity_g: item.quantity_g,
    ...(item.user_kcal !== undefined ? { user_kcal: item.user_kcal } : {}),
  }))
  const mediaId = input.source?.media_asset_id
  if (!mediaId) return items

  const asset = await createSupabaseMediaDependencies(supabase).repository.findOwned(
    userId,
    mediaId,
  )
  if (!asset || asset.status === 'deleted') {
    throw new MobileApiError(404, 'media_asset_not_found', 'Media asset was not found')
  }
  const photoChannel = input.source?.channel === 'camera' || input.source?.channel === 'gallery'
  if (asset.kind !== (photoChannel ? 'meal_photo' : 'audio_note')) {
    throw new MobileApiError(422, 'media_kind_not_supported', 'Media does not match the channel')
  }
  if (asset.status !== 'processed') {
    throw new MobileApiError(409, 'media_not_processed', 'Media asset is not processed yet')
  }

  const labelledIndex = input.items.findIndex((item) => item.use_nutrition_label)
  if (labelledIndex < 0) return items
  const labelled = items[labelledIndex]
  const result =
    typeof asset.processing_result === 'object' && asset.processing_result !== null
      ? (asset.processing_result as Record<string, unknown>)
      : {}
  const label =
    typeof result.nutrition_label === 'object' && result.nutrition_label !== null
      ? (result.nutrition_label as Record<string, unknown>)
      : null
  const resolved = label
    ? resolveTrustedNutritionLabel(
        {
          productName: typeof label.product_name === 'string' ? label.product_name : null,
          confidence: finite(label.confidence) ?? 0,
          servingSizeG: finite(label.serving_size_g),
          perServing: labelValues(label.per_serving),
          per100g: labelValues(label.per_100g),
        },
        await labelConfidenceThreshold(supabase),
      )
    : null
  if (!labelled || !resolved?.trusted || labelled.user_kcal != null) {
    throw new MobileApiError(
      422,
      'nutrition_label_not_applicable',
      'The nutrition label cannot be used for this item',
    )
  }
  const factor = labelled.quantity_g / 100
  const scale = (value: number) => Math.round(value * factor * 100) / 100
  items[labelledIndex] = {
    ...labelled,
    approved_nutrition: {
      source: 'product_label',
      kcal: scale(resolved.trusted.per100g.kcal),
      protein_g: scale(resolved.trusted.per100g.protein_g),
      carbs_g: scale(resolved.trusted.per100g.carbs_g),
      fat_g: scale(resolved.trusted.per100g.fat_g),
    },
  }
  return items
}

async function buildProposal(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  input: RegistrationProposalInput,
  requestKey: string,
  now = new Date(),
): Promise<Json> {
  const timezone = auth.patient.timezone ?? 'UTC'
  const timestamp = proposalTimestamp(input, now)
  const timing: ProposalTiming = {
    requestKey,
    timestamp: timestamp.toISOString(),
    timezone,
    localDate: getLocalDateString(timezone, timestamp),
  }

  if (input.kind === 'meal') {
    if (!auth.patient.countryConfirmed || !auth.patient.country) {
      throw new MobileApiError(
        409,
        'country_confirmation_required',
        'Confirm your country before calculating nutrition',
      )
    }
    const calculation = await calcMealMacros(
      supabase,
      await mealItemsForCalculation(supabase, auth.userId, input),
      auth.patient.country,
      auth.userId,
    )
    return buildMealPendingProposal(input, calculation, timing) as unknown as Json
  }

  const { data: profile, error: profileError } = await supabase
    .from('user_profiles')
    .select('weight_kg')
    .eq('user_id', auth.userId)
    .maybeSingle()
  if (profileError) {
    throw new MobileApiError(500, 'workout_calculation_failed', 'Workout calculation failed')
  }
  const { data: estimatedKcal, error: workoutError } = await supabase.rpc('calc_workout_kcal', {
    p_slug: input.workout_type,
    p_duration_min: input.duration_min,
    p_intensity: input.intensity,
    p_weight_kg: profile?.weight_kg ?? 70,
  })
  if (workoutError || estimatedKcal === null || !Number.isFinite(Number(estimatedKcal))) {
    throw new MobileApiError(500, 'workout_calculation_failed', 'Workout calculation failed')
  }
  return buildWorkoutPendingProposal(input, Number(estimatedKcal), timing) as unknown as Json
}

async function loadOwnedRegistration(
  supabase: ServiceClient,
  userId: string,
  registrationId: string,
) {
  const { data, error } = await supabase
    .from('pending_registrations')
    .select('id, proposal, status, created_at, expires_at, resolved_at')
    .eq('id', registrationId)
    .eq('user_id', userId)
    .maybeSingle()
  if (error) {
    throw new MobileApiError(500, 'registration_lookup_failed', 'Registration lookup failed')
  }
  if (!data) throw new MobileApiError(404, 'registration_not_found', 'Registration not found')
  return data
}

function pendingDto(row: {
  id: string
  proposal: Json
  status: string
  created_at: string
  expires_at: string
  resolved_at?: string | null
}) {
  return {
    id: row.id,
    status: row.status,
    created_at: row.created_at,
    expires_at: row.expires_at,
    resolved_at: row.resolved_at ?? null,
    proposal: sanitizePendingProposal(row.proposal),
  }
}

export async function proposeRegistration(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  input: RegistrationProposalInput,
  requestKey: string,
) {
  const proposal = await buildProposal(supabase, auth, input, requestKey)
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
  const id = await createPendingRegistration(supabase, {
    userId: auth.userId,
    proposal,
    expiresAt,
    requestKey,
  })
  const row = await loadOwnedRegistration(supabase, auth.userId, id)
  return pendingDto(row)
}

export async function editRegistration(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  registrationId: string,
  input: RegistrationProposalInput,
  requestKey: string,
) {
  const current = await loadOwnedRegistration(supabase, auth.userId, registrationId)
  if (current.status !== 'pending') {
    throw new MobileApiError(409, 'registration_not_pending', 'Registration is not pending')
  }
  if (new Date(current.expires_at).getTime() <= Date.now()) {
    throw new MobileApiError(410, 'registration_expired', 'Registration has expired')
  }

  const proposal = await buildProposal(supabase, auth, input, requestKey)
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('pending_registrations')
    .update({ proposal, expires_at: expiresAt })
    .eq('id', registrationId)
    .eq('user_id', auth.userId)
    .eq('status', 'pending')
    .select('id, proposal, status, created_at, expires_at, resolved_at')
    .maybeSingle()
  if (error)
    throw new MobileApiError(500, 'registration_update_failed', 'Registration update failed')
  if (!data) {
    throw new MobileApiError(
      409,
      'registration_update_conflict',
      'Registration changed concurrently',
    )
  }
  return pendingDto(data)
}

async function transitionToConfirmed(
  supabase: ServiceClient,
  userId: string,
  registrationId: string,
): Promise<void> {
  const { data, error } = await supabase
    .from('pending_registrations')
    .update({ status: 'confirmed', resolved_at: new Date().toISOString() })
    .eq('id', registrationId)
    .eq('user_id', userId)
    .eq('status', 'pending')
    .select('id')
    .maybeSingle()
  if (error) {
    throw new MobileApiError(500, 'registration_confirmation_failed', 'Confirmation failed')
  }
  if (!data) {
    const current = await loadOwnedRegistration(supabase, userId, registrationId)
    if (current.status !== 'confirmed') {
      throw new MobileApiError(
        409,
        'registration_confirmation_conflict',
        'Registration changed concurrently',
      )
    }
  }
}

export async function confirmRegistration(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  registrationId: string,
) {
  const row = await loadOwnedRegistration(supabase, auth.userId, registrationId)
  if (row.status === 'confirmed') return { ...pendingDto(row), already_confirmed: true }
  if (row.status !== 'pending') {
    throw new MobileApiError(409, 'registration_not_pending', 'Registration is not pending')
  }
  if (new Date(row.expires_at).getTime() <= Date.now()) {
    await supabase
      .from('pending_registrations')
      .update({ status: 'expired', resolved_at: new Date().toISOString() })
      .eq('id', registrationId)
      .eq('user_id', auth.userId)
      .eq('status', 'pending')
    throw new MobileApiError(410, 'registration_expired', 'Registration has expired')
  }

  const commonContext = {
    supabase,
    userId: auth.userId,
    userWpp: '',
    userCountry: auth.patient.country ?? 'BR',
    userTimezone: auth.patient.timezone ?? 'UTC',
    trustMealType: true,
  }
  const kind = typeof row.proposal === 'object' && row.proposal ? row.proposal : null
  let deduped = false

  if (kind && !Array.isArray(kind) && kind.kind === 'meal') {
    const parsedProposal = pendingMealProposalSchema.safeParse(row.proposal)
    if (!parsedProposal.success) {
      throw new MobileApiError(
        409,
        'registration_proposal_invalid',
        'Registration proposal is invalid',
      )
    }
    const proposal = parsedProposal.data
    // An item the server has not calculated (it asked the patient for the
    // preparation, the composition, ...) is not a meal to persist. This holds
    // for any client: the confirm is refused and the pending stays editable.
    if (proposal.items.some((item) => isUnresolvedNutritionSource(item.nutrition_source))) {
      throw new MobileApiError(
        422,
        'registration_unresolved_items',
        'Registration has items that need clarification',
      )
    }
    const result = await registraRefeicao.execute(
      buildConfirmedMealArgs(
        { mealType: proposal.mealType, items: proposal.items },
        false,
        proposal.source_local_date,
      ) as never,
      {
        ...commonContext,
        providerMessageId: proposal.source_provider_message_id,
        referenceTimestamp: new Date(proposal.source_timestamp),
      } as never,
    )
    if (result.success !== true) {
      throw new MobileApiError(422, 'registration_rejected', 'Meal registration was rejected')
    }
    deduped = result.deduped === true || result.already_logged === true
  } else if (kind && !Array.isArray(kind) && kind.kind === 'workout') {
    const parsedProposal = pendingWorkoutProposalSchema.safeParse(row.proposal)
    if (!parsedProposal.success) {
      throw new MobileApiError(
        409,
        'registration_proposal_invalid',
        'Registration proposal is invalid',
      )
    }
    const proposal = parsedProposal.data
    const result = await registraTreino.execute(
      {
        workout_type: proposal.workoutType,
        duration_min: proposal.durationMin,
        intensity: proposal.intensity,
      } as never,
      {
        ...commonContext,
        providerMessageId: proposal.source_provider_message_id,
        referenceTimestamp: new Date(proposal.source_timestamp),
      } as never,
    )
    if (result.success !== true) {
      throw new MobileApiError(422, 'registration_rejected', 'Workout registration was rejected')
    }
    deduped = result.deduped === true
  } else {
    throw new MobileApiError(
      409,
      'registration_proposal_invalid',
      'Registration proposal is invalid',
    )
  }

  await transitionToConfirmed(supabase, auth.userId, registrationId)
  const confirmed = await loadOwnedRegistration(supabase, auth.userId, registrationId)
  return { ...pendingDto(confirmed), already_confirmed: false, deduped }
}

export async function cancelRegistration(
  supabase: ServiceClient,
  userId: string,
  registrationId: string,
) {
  const current = await loadOwnedRegistration(supabase, userId, registrationId)
  if (current.status === 'cancelled') return pendingDto(current)
  if (current.status !== 'pending') {
    throw new MobileApiError(409, 'registration_not_pending', 'Registration is not pending')
  }

  const { data, error } = await supabase
    .from('pending_registrations')
    .update({ status: 'cancelled', resolved_at: new Date().toISOString() })
    .eq('id', registrationId)
    .eq('user_id', userId)
    .eq('status', 'pending')
    .select('id, proposal, status, created_at, expires_at, resolved_at')
    .maybeSingle()
  if (error) {
    throw new MobileApiError(500, 'registration_cancel_failed', 'Registration cancellation failed')
  }
  if (!data) {
    throw new MobileApiError(
      409,
      'registration_cancel_conflict',
      'Registration changed concurrently',
    )
  }
  return pendingDto(data)
}
