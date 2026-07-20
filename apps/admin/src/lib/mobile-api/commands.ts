import { cadastraDadosIniciais } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import type { OnboardingInput, PatchMeInput } from './contracts'
import { MobileApiError } from './http'
import { loadProfile, meDto } from './read-model'

export async function updateMe(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  input: PatchMeInput,
) {
  const updates = {
    ...input,
    ...(input.country ? { country_confirmed: true } : {}),
    updated_at: new Date().toISOString(),
  }
  const { data, error } = await supabase
    .from('users')
    .update(updates)
    .eq('id', auth.userId)
    .eq('auth_user_id', auth.authUserId)
    .select('id, auth_user_id, email, name, locale, timezone, country, status')
    .maybeSingle()
  if (error) throw new MobileApiError(500, 'profile_update_failed', 'Profile update failed')
  if (!data?.auth_user_id) {
    throw new MobileApiError(404, 'patient_not_found', 'Patient profile not found')
  }

  return meDto({
    ...auth,
    patient: {
      id: data.id,
      authUserId: data.auth_user_id,
      email: data.email,
      name: data.name,
      locale: data.locale,
      timezone: data.timezone,
      country: data.country,
      status: data.status,
    },
  })
}

export async function saveOnboarding(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  input: OnboardingInput,
  requestKey: string,
) {
  const result = await cadastraDadosIniciais.execute(input, {
    supabase,
    userId: auth.userId,
    userWpp: '',
    userCountry: auth.patient.country ?? undefined,
    userTimezone: auth.patient.timezone ?? 'UTC',
    providerMessageId: requestKey,
    referenceTimestamp: new Date(),
  })

  if (result.success !== true) {
    throw new MobileApiError(422, 'onboarding_rejected', 'Onboarding data was rejected', {
      issues: Array.isArray(result.issues) ? result.issues : [],
    })
  }

  return {
    profile: await loadProfile(supabase, auth.userId),
    targets: {
      calories:
        typeof result.calories_target_today === 'number' ? result.calories_target_today : null,
      protein_g:
        typeof result.protein_target_today_g === 'number' ? result.protein_target_today_g : null,
    },
  }
}
