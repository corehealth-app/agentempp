import {
  type CoachMessageLocale,
  coachPersonalitySchema,
  selectableCoachPersonalitySchema,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type {
  ClaimedCoachMessageRecord,
  CoachDependencies,
  CoachPersonaState,
  MascotState,
} from './coach-service'
import { MobileApiError } from './http'

const personalityRowSchema = z.object({
  code: selectableCoachPersonalitySchema,
  name_pt_br: z.string().min(1),
  description_pt_br: z.string().min(1),
  name_en_us: z.string().min(1),
  description_en_us: z.string().min(1),
})

const preferenceRowSchema = z.object({ personality_code: selectableCoachPersonalitySchema })

const mascotRowSchema = z.object({
  state: z.enum(['inactive', 'reactivating', 'active', 'evolving', 'neglected']),
  changed_at: z.string().datetime({ offset: true }),
})

const selectedClaimSchema = z.object({
  usage_id: z.string().uuid(),
  pack_id: z.string().uuid(),
  template_version_id: z.string().uuid(),
  requested_personality: coachPersonalitySchema,
  effective_personality: coachPersonalitySchema,
  outcome: z.literal('selected'),
  reason: z.enum(['exact', 'balanced_fallback']),
  title: z.string().nullable(),
  subject: z.string().nullable(),
  body: z.string().min(1),
  allowed_variables: z.array(z.string()),
  required_variables: z.array(z.string()),
})

const claimOutcomeSchema = z.object({
  outcome: z.enum(['selected', 'suppressed', 'failed']),
})

function databaseFailure(action: string, error?: { code?: string } | null): never {
  console.error('[mobile-coach] database_failure', {
    action,
    error_code: error?.code ?? 'invalid_response',
  })
  throw new MobileApiError(500, 'coach_storage_failed', 'Coach operation failed')
}

function mapPersonaState(
  locale: CoachMessageLocale,
  preferenceValue: unknown,
  personalitiesValue: unknown,
  mascotValue: unknown,
): CoachPersonaState {
  const preference =
    preferenceValue === null ? null : preferenceRowSchema.safeParse(preferenceValue)
  if (preference !== null && !preference.success) databaseFailure('parse_preference')

  const personalities = z.array(personalityRowSchema).safeParse(personalitiesValue)
  if (!personalities.success || personalities.data.length !== 3) {
    databaseFailure('parse_personalities')
  }

  const mascot = mascotValue === null ? null : mascotRowSchema.safeParse(mascotValue)
  if (mascot !== null && !mascot.success) databaseFailure('parse_mascot')

  const selected = preference?.data.personality_code ?? null
  const mascotState: MascotState = mascot?.data.state ?? 'inactive'
  return {
    selected,
    effective: selected ?? 'balanced',
    options: personalities.data.map((personality) => ({
      code: personality.code,
      name: locale === 'pt-BR' ? personality.name_pt_br : personality.name_en_us,
      description:
        locale === 'pt-BR' ? personality.description_pt_br : personality.description_en_us,
    })),
    mascot: {
      state: mascotState,
      changed_at: mascot?.data.changed_at ?? null,
    },
    contract_version: 'bodyflow.coach-persona.v1',
  }
}

function parseSelectedClaim(value: unknown): ClaimedCoachMessageRecord | null {
  const outcome = claimOutcomeSchema.safeParse(value)
  if (!outcome.success) databaseFailure('parse_claim_outcome')
  if (outcome.data.outcome !== 'selected') return null

  const parsed = selectedClaimSchema.safeParse(value)
  if (!parsed.success) databaseFailure('parse_selected_claim')
  return {
    usageId: parsed.data.usage_id,
    templateVersionId: parsed.data.template_version_id,
    packId: parsed.data.pack_id,
    requestedPersonality: parsed.data.requested_personality,
    effectivePersonality: parsed.data.effective_personality,
    reason: parsed.data.reason,
    title: parsed.data.title,
    subject: parsed.data.subject,
    body: parsed.data.body,
    allowedVariables: parsed.data.allowed_variables,
    requiredVariables: parsed.data.required_variables,
  }
}

export function createSupabaseCoachDependencies(supabase: ServiceClient): CoachDependencies {
  return {
    repository: {
      async getPersonaState(userId, locale) {
        const [preferenceResult, personalitiesResult, mascotResult] = await Promise.all([
          supabase
            .from('user_coach_preferences')
            .select('personality_code')
            .eq('user_id', userId)
            .maybeSingle(),
          supabase
            .from('coach_personalities')
            .select('code, name_pt_br, description_pt_br, name_en_us, description_en_us')
            .eq('selectable', true)
            .eq('active', true)
            .order('code', { ascending: true }),
          supabase
            .from('user_mascot_state')
            .select('state, changed_at')
            .eq('user_id', userId)
            .maybeSingle(),
        ])

        if (preferenceResult.error) databaseFailure('get_preference', preferenceResult.error)
        if (personalitiesResult.error) {
          databaseFailure('get_personalities', personalitiesResult.error)
        }
        if (mascotResult.error) databaseFailure('get_mascot', mascotResult.error)

        return mapPersonaState(
          locale,
          preferenceResult.data,
          personalitiesResult.data,
          mascotResult.data,
        )
      },

      async setPersona(userId, persona) {
        const { data, error } = await supabase.rpc('set_user_coach_personality', {
          p_user_id: userId,
          p_personality: persona,
        })
        if (error || !data) databaseFailure('set_persona', error)
      },

      async claimMessage(input) {
        const { data, error } = await supabase.rpc('claim_coach_message', {
          p_user_id: input.userId,
          p_context: input.context,
          p_channel: input.channel,
          p_locale: input.locale,
          p_event_key: input.eventKey,
          p_available_variables: input.availableVariables,
          ...(input.now === undefined ? {} : { p_now: input.now }),
        })
        if (error || !data) databaseFailure('claim_message', error)
        return parseSelectedClaim(data)
      },

      async markUsageFailed(usageId, reason) {
        const { error } = await supabase.from('product_events').insert({
          user_id: null,
          event: 'coach.render_failed',
          properties: { usage_id: usageId, reason },
        })
        if (error) databaseFailure('record_render_failure', error)
      },
    },
  }
}
