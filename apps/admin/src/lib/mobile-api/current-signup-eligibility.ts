/** Public presentation of the current rule. No token here authorizes a write;
 * completion captures and checks its own current state again. */
import type { SignupEligibilityConfig } from '@mpp/core'
import {
  type CurrentClinicalSnapshot,
  currentClinicalError,
  currentSignupChoices,
  projectCurrentClinicalState,
} from './current-clinical-state'
import { resolveOnboardingEligibility } from './protocol-eligibility-service'

export function presentCurrentSignupEligibility(state: CurrentClinicalSnapshot) {
  const choices = currentSignupChoices(state)
  const policy = projectCurrentClinicalState(state)
  const en = state.body.locale === 'en-US'
  const professional = en
    ? 'Consult a healthcare professional to assess your situation.'
    : 'Procure um profissional de saúde para avaliar sua situação.'
  const pause = en
    ? 'Weight loss guidance is paused. A new reduction will not be assigned automatically.'
    : 'As orientações de emagrecimento estão pausadas. Não será atribuída uma nova redução automaticamente.'
  const guidance = {
    professional_assessment_recommended: policy.professionalAssessmentRecommended,
    pause_weight_loss_guidance: policy.pauseWeightLossGuidance,
  }
  if (choices.decision === 'no_plan')
    return {
      ...choices,
      notice: [
        en
          ? 'You can finish signing up and keep recording your routine. The app will not assign a plan or calorie and protein targets at this time.'
          : 'Você pode concluir o cadastro e continuar registrando sua rotina. Neste momento, o app não definirá um plano ou metas de calorias e proteína.',
        professional,
      ],
      ...guidance,
    }
  const b = state.body
  if (!b.sex || b.height_cm === null || b.weight_kg === null || b.training_frequency === null)
    throw currentClinicalError('invalid_response')
  const config: SignupEligibilityConfig = {}
  for (const row of state.calculation_config) {
    if (row.key === 'calc.bf_limits') config.bf_limits = row.value
    if (row.key === 'calc.training_min') config.training_min = row.value
    if (row.key === 'calc.imc_limit_recomp') config.imc_limit_recomp = row.value
  }
  const ordinary = resolveOnboardingEligibility(
    {
      locale: en ? 'en-US' : 'pt-BR',
      sex: b.sex,
      height_cm: b.height_cm,
      weight_kg: b.weight_kg,
      training_frequency: b.training_frequency,
      ...(b.body_fat_percent === null ? {} : { body_fat_percent: b.body_fat_percent }),
    },
    config,
  )
  // A guard can turn an automatically assigned rule into an explicit choice.
  // Legacy copy may invite a now-blocked phase; never carry that invitation
  // into the guarded result. The original helper/default DTO is untouched.
  const guarded = policy.pauseWeightLossGuidance
  return {
    ...choices,
    notice: guarded ? [pause, professional] : ordinary.notice,
    options: choices.options.map((option) => {
      const original = ordinary.options.find((item) => item.objective === option.objective)
      if (!original) throw currentClinicalError('invalid_response')
      return {
        ...option,
        message:
          option.status !== 'blocked'
            ? []
            : !guarded
              ? original.message
              : option.reasons.map((reason) => {
                  if (reason === 'health_review' || reason === 'loss_guard') return pause
                  if (reason === 'gain_composition')
                    return en
                      ? 'Muscle gain is unavailable for the current body composition data.'
                      : 'O ganho de massa está indisponível para os dados atuais de composição corporal.'
                  return en
                    ? 'Muscle gain is unavailable for the strength training frequency you reported.'
                    : 'O ganho de massa está indisponível para a frequência de musculação informada.'
                }),
      }
    }),
    ...guidance,
  }
}
