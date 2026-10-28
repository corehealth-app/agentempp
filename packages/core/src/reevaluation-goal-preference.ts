import { z } from 'zod'
import { clinicalBmiBelow } from './clinical-bmi-comparison.js'
import { reevaluationGoalPreferenceSchema } from './reevaluation-form-contracts.js'

const inputSchema = z
  .object({
    preference: reevaluationGoalPreferenceSchema,
    sex: z.enum(['masculino', 'feminino']).nullable(),
    heightCm: z.number().finite().positive().nullable(),
  })
  .strict()
interface PreferenceEvaluation {
  status: 'unchanged' | 'removed' | 'accepted' | 'refused' | 'missing'
  reason: 'body_fat_floor' | 'weight_bmi_floor' | 'dependent_context' | null
  missing: ('sex' | 'heightCm')[]
  normalizedPreference: z.infer<typeof reevaluationGoalPreferenceSchema>
}

/** n21. Separate personal preference, never an active goal or formula input.
 * The prepare orchestrator must hash/persist normalizedPreference ONLY: a
 * refused value must not survive in a FULL form or replay payload either. */
export function evaluateReevaluationGoalPreference(input: unknown): PreferenceEvaluation {
  const { preference, sex, heightCm } = inputSchema.parse(input)
  const result: PreferenceEvaluation = {
    status: 'unchanged',
    reason: null,
    missing: [],
    normalizedPreference: preference,
  }
  if (preference === null || preference.action === 'keep' || preference.action === 'skip')
    return result
  if (preference.action === 'remove') return { ...result, status: 'removed' }
  const value = preference.value
  if (value.kind === 'body_fat') {
    if (value.percent < 10 || (sex === 'feminino' && value.percent < 12))
      return {
        status: 'refused',
        reason: 'body_fat_floor',
        missing: [],
        normalizedPreference: null,
      }
    if (value.percent < 12 && sex === null)
      return {
        status: 'missing',
        reason: 'dependent_context',
        missing: ['sex'],
        normalizedPreference: null,
      }
  } else if (value.kind === 'weight') {
    if (heightCm === null)
      return {
        status: 'missing',
        reason: 'dependent_context',
        missing: ['heightCm'],
        normalizedPreference: null,
      }
    if (clinicalBmiBelow(value.kg, heightCm, 18.5))
      return {
        status: 'refused',
        reason: 'weight_bmi_floor',
        missing: [],
        normalizedPreference: null,
      }
  }
  return { ...result, status: 'accepted' }
}
