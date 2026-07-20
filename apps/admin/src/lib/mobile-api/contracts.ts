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
    country: z
      .string()
      .regex(/^[A-Z]{2}$/)
      .optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, 'At least one field is required')

const timeSchema = z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/)

export const onboardingInputSchema = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    sex: z.enum(['masculino', 'feminino']).optional(),
    birth_date: z.string().date().optional(),
    height_cm: z.number().min(100).max(250).optional(),
    weight_kg: z.number().min(30).max(300).optional(),
    body_fat_percent: z.number().min(3).max(60).optional(),
    activity_level: z.enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta']).optional(),
    training_frequency: z.number().int().min(0).max(7).optional(),
    water_intake: z.enum(['pouco', 'moderado', 'bastante']).optional(),
    hunger_level: z.enum(['pouca', 'moderada', 'muita']).optional(),
    wake_time: timeSchema.optional(),
    bedtime: timeSchema.optional(),
    food_organization: z.enum(['sim', 'nao']).optional(),
    onboarding_step: z.number().int().min(0).max(11).optional(),
    onboarding_completed: z.boolean().optional(),
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

export const personaInputSchema = z
  .object({ persona: z.enum(['focus', 'impulse', 'zen']) })
  .strict()

export type PatchMeInput = z.infer<typeof patchMeInputSchema>
export type OnboardingInput = z.infer<typeof onboardingInputSchema>
export type RegistrationProposalInput = z.infer<typeof registrationProposalInputSchema>
export type HistoryQuery = z.infer<typeof historyQuerySchema>

export { localeSchema, timezoneSchema }
