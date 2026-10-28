import {
  clinicalCivilDateSchema,
  clinicalTimestampSchema,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'

/** Observation at conclusion/reaccept, not a live clinical authorization.
 * Keyed replay may return this original observation; readers must refresh
 * current server health/civil time before displaying or applying targets. */
export const onboardingClinicalSafetySchema = z
  .object({
    version: z.literal(1),
    no_plan: z.boolean(),
    hold_active: z.boolean(),
    loss_guard: z.boolean(),
    hide_protein: z.boolean(),
    recording_allowed: z.literal(true),
    date: clinicalCivilDateSchema,
    timezone: z.string().min(1).max(64),
    observed_at: clinicalTimestampSchema,
  })
  .strict()
  .refine((value) => !value.no_plan || value.hide_protein)
  .refine((value) => !value.hide_protein || value.no_plan || value.hold_active)

export type OnboardingClinicalSafetyRecord = z.infer<typeof onboardingClinicalSafetySchema>
