/** Pure phase-entry policy shared by two independently proven sources.
 * No source admission, snapshot alteration, automatic assignment or I/O. */
import { DEFAULT_CALC_CONFIG, type SignupEligibilityConfig } from '@mpp/core'
import type { HealthRiskCode } from '@mpp/core/health-check'
import {
  clinicalCivilDateSchema,
  evaluateReevaluationSafety,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import { decideOnboardingEligibility } from './protocol-eligibility-service'

const phase = z.enum(['recomposicao', 'ganho_massa', 'manutencao'])
type Phase = z.infer<typeof phase>
interface Option {
  phase: Phase
  status: 'available' | 'blocked' | 'not_offered'
  reasons: string[]
}
export interface ClinicalPhaseEntryInput {
  date: string
  effectiveDate: string
  profile: {
    sex: 'masculino' | 'feminino' | null
    birth_date: string | null
    height_cm: number | null
    weight_kg: number | null
    body_fat_percent: number | null
    activity_level: 'sedentario' | 'leve' | 'moderado' | 'alto' | 'atleta' | null
    training_frequency: number | null
    hunger_level: 'pouca' | 'moderada' | 'muita' | null
  }
  hold: { active: boolean; items: HealthRiskCode[] }
  calculationConfig: readonly { key: string; value?: unknown }[]
}
export function projectClinicalPhaseEntry(input: ClinicalPhaseEntryInput) {
  const { profile } = input
  const safety = evaluateReevaluationSafety({
    date: input.date,
    birthDate: profile.birth_date,
    heightCm: profile.height_cm,
    weightKg: profile.weight_kg,
    bodyFatPercent: profile.body_fat_percent,
    hold: { active: input.hold.active, items: input.hold.items },
  })
  const common = {
    date: input.date,
    effectiveDate: input.effectiveDate,
    safety,
  }
  if (!safety.automaticTargetChangeAllowed)
    return {
      ...common,
      availability: 'blocked' as const,
      missing: safety.missing.map(
        (key) =>
          (({ birthDate: 'birth_date', heightCm: 'height_cm', weightKg: 'weight_kg' }) as const)[
            key
          ],
      ),
      options: [] as Option[],
    }
  const missing = (
    [
      'sex',
      'birth_date',
      'height_cm',
      'weight_kg',
      'activity_level',
      'training_frequency',
      'hunger_level',
    ] as const
  ).filter((key) => profile[key] === null)
  if (
    missing.length ||
    profile.sex === null ||
    profile.height_cm === null ||
    profile.weight_kg === null ||
    profile.training_frequency === null
  )
    return { ...common, availability: 'incomplete' as const, missing, options: [] as Option[] }
  const config: SignupEligibilityConfig = {}
  for (const row of input.calculationConfig) {
    if (row.key === 'calc.bf_limits') config.bf_limits = row.value
    if (row.key === 'calc.imc_limit_recomp') config.imc_limit_recomp = row.value
    if (row.key === 'calc.training_min') config.training_min = row.value
  }
  // Share composition criteria only. An 'assigned' signup outcome is merely
  // a candidate here; every later entry still requires an explicit acceptance.
  const decided = decideOnboardingEligibility(
    {
      sex: profile.sex,
      height_cm: profile.height_cm,
      weight_kg: profile.weight_kg,
      body_fat_percent: profile.body_fat_percent ?? undefined,
      training_frequency: profile.training_frequency,
    },
    config,
  )
  return {
    ...common,
    availability: 'available' as const,
    missing: [],
    options: phase.options.map((p) => ({
      phase: p,
      status: decided.objectives[p].status,
      reasons: decided.objectives[p].reasons.map((r) =>
        r === 'composition' ? 'gain_composition' : 'gain_training',
      ),
    })),
  }
}

const deficitTable = z
  .object({ muita: z.literal(400), moderada: z.literal(500), pouca: z.literal(600) })
  .strict()
export function clinicalPhaseEntryDeficit(
  selected: Phase,
  hunger: 'pouca' | 'moderada' | 'muita' | null,
  rows: readonly { key: string; value?: unknown }[],
) {
  const configured = rows.find((row) => row.key === 'calc.deficit_by_hunger')
  const table = deficitTable.parse(configured?.value ?? DEFAULT_CALC_CONFIG.deficit_by_hunger)
  if (hunger === null) throw new Error('Phase entry calculation unavailable')
  return selected === 'recomposicao' ? table[hunger] : null
}
export function clinicalPhaseEntryEpisode(selected: Phase, date: string, dayClosed: boolean) {
  clinicalCivilDateSchema.parse(date)
  return {
    difficultyCount: selected === 'recomposicao' ? 0 : null,
    ledgerSteps: selected === 'recomposicao' ? null : [],
    schedule: null,
    maintenanceSince: selected === 'manutencao' && !dayClosed ? date : null,
  }
}
