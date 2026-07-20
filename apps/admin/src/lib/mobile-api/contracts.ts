import { z } from 'zod'

const localeSchema = z.string().regex(/^[a-z]{2}(?:-[A-Z]{2})?$/)

const timezoneSchema = z
  .string()
  .min(1)
  .max(64)
  .refine((value) => {
    try {
      new Intl.DateTimeFormat('en-US', { timeZone: value }).format()
      return true
    } catch {
      return false
    }
  }, 'Invalid IANA timezone')

export const idempotencyKeySchema = z
  .string()
  .trim()
  .min(8)
  .max(128)
  .regex(/^[A-Za-z0-9._:-]+$/)

export const patchMeInputSchema = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    locale: localeSchema.optional(),
    timezone: timezoneSchema.optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, 'At least one field is required')

const mealItemInputSchema = z
  .object({
    food_name: z.string().trim().min(1).max(160),
    quantity_g: z.number().positive().max(9999),
    user_kcal: z.number().nonnegative().max(20_000).optional(),
  })
  .strict()

const mealProposalInputSchema = z
  .object({
    kind: z.literal('meal'),
    meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
    items: z.array(mealItemInputSchema).min(1).max(30),
    consumed_at: z.string().datetime({ offset: true }).optional(),
  })
  .strict()

const workoutProposalInputSchema = z
  .object({
    kind: z.literal('workout'),
    workout_type: z.string().trim().min(1).max(80),
    duration_min: z.number().int().positive().max(1440),
    intensity: z.enum(['leve', 'moderada', 'alta']).default('moderada'),
    performed_at: z.string().datetime({ offset: true }).optional(),
  })
  .strict()

export const registrationProposalInputSchema = z.discriminatedUnion('kind', [
  mealProposalInputSchema,
  workoutProposalInputSchema,
])

export const historyQuerySchema = z
  .object({
    before: z.string().datetime({ offset: true }).optional(),
    limit: z.coerce.number().int().min(1).max(100).default(30),
  })
  .strict()

export const resourceIdSchema = z.string().uuid()

export type PatchMeInput = z.infer<typeof patchMeInputSchema>
export type RegistrationProposalInput = z.infer<typeof registrationProposalInputSchema>
export type HistoryQuery = z.infer<typeof historyQuerySchema>

export { localeSchema, timezoneSchema }
