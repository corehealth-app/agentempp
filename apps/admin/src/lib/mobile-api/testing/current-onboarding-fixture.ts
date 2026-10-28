import { consentAuth, uid } from './reevaluation-photo-consent-fixture'
export const currentOnboardingIDs = {
  owner: consentAuth.userId,
  epoch: uid(6001),
  generation: uid(6002),
}
export function currentOnboardingWire(kind: 'healthy' | 'hold' | 'no_plan' = 'healthy') {
  const owner = currentOnboardingIDs.owner,
    held = kind !== 'healthy',
    noPlan = kind === 'no_plan',
    at = '2026-10-27T12:00:00.000001Z',
    completed = '2026-10-01T12:00:00.000001Z'
  return {
    version: 1,
    user_id: owner,
    mode: 'profile',
    profile_present: true,
    epoch: currentOnboardingIDs.epoch,
    signup_generation: currentOnboardingIDs.generation,
    generation_token: {
      onboarding_completed: true,
      onboarding_completed_at: completed,
      receipt_count: 1,
    },
    first_completion: false,
    observed_at: at,
    date: '2026-10-27',
    timezone: 'America/Sao_Paulo',
    body: {
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      sex: 'masculino',
      birth_date: '1990-01-01',
      height_cm: 180,
      weight_kg: 80,
      body_fat_percent: 24,
      training_frequency: 4,
    },
    assessment: 'complete',
    missing: [],
    health_state: {
      version: 1,
      user_id: owner,
      safety_revision: held ? '1' : '0',
      hold_active: held,
      declared_no_plan: noPlan,
      hide_protein: false,
      last_declared_at: held ? at : null,
      items: held
        ? [{ code: noPlan ? 'pregnant_or_breastfeeding' : 'reduced_intake', declared_at: at }]
        : [],
    },
    safety: {
      version: 1,
      no_plan: noPlan,
      hold_active: held,
      loss_guard: false,
      hide_protein: noPlan,
      recording_allowed: true,
      date: '2026-10-27',
      timezone: 'America/Sao_Paulo',
      observed_at: at,
    },
    phase_origin: { kind: 'assigned', phase: 'recomposicao' } as Record<string, unknown>,
    calculation_config: [],
    profile_hash: 'a'.repeat(64),
    context_hash: 'b'.repeat(64),
  }
}
