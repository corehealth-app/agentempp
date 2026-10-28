/** Historical command normalization only. No current read, clock or effect. */
import { isDeepStrictEqual } from 'node:util'
import { parseReevaluationFormDraft } from '@mpp/core/reevaluation-form'
import { evaluateReevaluationGoalPreference } from '@mpp/core/reevaluation-goal-preference'
import { z } from 'zod'
import {
  fullChoiceSchema,
  fullIntentSchema,
  fullNormalizationSchema,
} from './clinical-full-contracts'

const inputSchema = z
  .object({
    form: z.unknown(),
    choice: fullChoiceSchema,
    measureConfirmed: z.boolean().default(false),
    bodyFat: fullIntentSchema.shape.bodyFat.default(null),
  })
  .strict()

export function normalizeClinicalFullCommand(
  raw: unknown,
  normalization: unknown,
  originalForm?: unknown,
) {
  const context = fullNormalizationSchema.parse(structuredClone(normalization))
  const input = inputSchema.parse(structuredClone(raw))
  let rawForm = input.form
  if (originalForm !== undefined) {
    const original = parseReevaluationFormDraft(structuredClone(originalForm))
    if (
      original.phase === null &&
      rawForm &&
      typeof rawForm === 'object' &&
      !Array.isArray(rawForm)
    ) {
      const key = 'legacyOrigin' in original ? 'legacyOrigin' : 'noPlanOrigin'
      const origin = 'legacyOrigin' in original ? original.legacyOrigin : original.noPlanOrigin
      if (Object.hasOwn(rawForm, key) && !isDeepStrictEqual(Reflect.get(rawForm, key), origin))
        throw new Error('Invalid original unassigned identity')
      rawForm = { ...rawForm, [key]: origin }
    }
  }
  let form = parseReevaluationFormDraft(rawForm)
  const preference = evaluateReevaluationGoalPreference({ preference: form.preference, ...context })
  form = form.phase === null ? form : { ...form, preference: preference.normalizedPreference }
  return {
    command: {
      form,
      choice: input.choice,
      measureConfirmed: input.measureConfirmed,
      bodyFat: input.bodyFat,
    },
    preference,
  }
}
