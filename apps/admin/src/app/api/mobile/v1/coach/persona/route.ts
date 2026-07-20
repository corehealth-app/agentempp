import { type CoachMessageLocale, coachMessageLocaleSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import {
  type CoachDependencies,
  getCoachPersonaState,
  setCoachPersona,
} from '@/lib/mobile-api/coach-service'
import { personaInputSchema } from '@/lib/mobile-api/contracts'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createSupabaseCoachDependencies } from '@/lib/mobile-api/supabase-coach'

export const runtime = 'nodejs'

export interface CoachPersonaRouteDependencies {
  createCoachDependencies(client: ServiceClient): CoachDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
}

const defaultDependencies: CoachPersonaRouteDependencies = {
  createCoachDependencies: createSupabaseCoachDependencies,
  executeIdempotent: executeSupabaseIdempotent,
}

function resolveLocale(context: MobileRouteContext): CoachMessageLocale {
  const parsed = coachMessageLocaleSchema.safeParse(context.auth.patient.locale ?? 'pt-BR')
  if (!parsed.success) {
    throw new MobileApiError(
      409,
      'coach_locale_unsupported',
      'Select a supported language before configuring the coach',
    )
  }
  return parsed.data
}

export async function handleCoachPersonaGet(
  context: MobileRouteContext,
  dependencies: CoachPersonaRouteDependencies = defaultDependencies,
): Promise<Response> {
  const locale = resolveLocale(context)
  const coach = dependencies.createCoachDependencies(context.supabase)
  return mobileSuccess(
    await getCoachPersonaState(coach, context.auth.userId, locale),
    context.requestId,
  )
}

export async function handleCoachPersonaPatch(
  context: MobileRouteContext,
  dependencies: CoachPersonaRouteDependencies = defaultDependencies,
): Promise<Response> {
  const input = personaInputSchema.parse(await readJsonBody(context.request))
  const locale = resolveLocale(context)
  const coach = dependencies.createCoachDependencies(context.supabase)

  return dependencies.executeIdempotent(context, input, async () =>
    mobileSuccess(
      await setCoachPersona(coach, context.auth.userId, input.persona, locale),
      context.requestId,
    ),
  )
}

export const GET = createMobileRoute((context) => handleCoachPersonaGet(context))

export const PATCH = createMobileRoute((context) => handleCoachPersonaPatch(context))
