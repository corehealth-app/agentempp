import { selectableCoachPersonalitySchema } from '@mpp/core'
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
const minuteTimeSchema = z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/)

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

export const personaInputSchema = z.object({ persona: selectableCoachPersonalitySchema }).strict()

const patientImageMimeSchema = z.enum([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
])

const patientAudioMimeSchema = z.enum([
  'audio/mpeg',
  'audio/mp4',
  'audio/x-m4a',
  'audio/aac',
  'audio/wav',
  'audio/x-wav',
  'audio/ogg',
])

const mediaUploadBaseSchema = z.object({
  size_bytes: z.number().int().positive(),
  context_text: z.string().trim().min(1).max(1000).optional(),
})

const mediaPhotoUploadSchema = mediaUploadBaseSchema
  .extend({
    kind: z.enum(['meal_photo', 'body_checkin_photo', 'gym_photo']),
    mime_type: patientImageMimeSchema,
    size_bytes: z
      .number()
      .int()
      .positive()
      .max(15 * 1024 * 1024),
  })
  .strict()

const mediaAudioUploadSchema = mediaUploadBaseSchema
  .extend({
    kind: z.literal('audio_note'),
    mime_type: patientAudioMimeSchema,
    size_bytes: z
      .number()
      .int()
      .positive()
      .max(25 * 1024 * 1024),
  })
  .strict()

export const mediaUploadInputSchema = z.discriminatedUnion('kind', [
  mediaPhotoUploadSchema,
  mediaAudioUploadSchema,
])

export const mobileDeviceInputSchema = z
  .object({
    installation_id: z.string().uuid(),
    apns_environment: z.enum(['sandbox', 'production']),
    apns_token: z
      .string()
      .min(64)
      .max(512)
      .regex(/^[0-9A-Fa-f]+$/)
      .refine((value) => value.length % 2 === 0, 'APNs token must have an even length')
      .transform((value) => value.toLowerCase()),
  })
  .strict()

const quietHoursSchema = z
  .object({ start: minuteTimeSchema, end: minuteTimeSchema })
  .strict()
  .refine((value) => value.start !== value.end, 'Quiet hours must have distinct boundaries')

export const notificationPreferencesPatchSchema = z
  .object({
    push_enabled: z.boolean().optional(),
    quiet_hours: quietHoursSchema.nullable().optional(),
    daily_push_limit: z.number().int().min(0).max(20).optional(),
    hydration_target_ml: z.number().int().min(250).max(10_000).nullable().optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, 'At least one field is required')

const reminderCategorySchema = z.enum([
  'meal',
  'hydration',
  'supplement',
  'medication',
  'workout',
  'reevaluation',
  'content',
  'reengagement',
])

const reminderWeekdaysSchema = z
  .array(z.number().int().min(0).max(6))
  .min(1)
  .max(7)
  .refine((values) => new Set(values).size === values.length, 'Weekdays must be unique')
  .transform((values) => [...values].sort((left, right) => left - right))

export const createReminderInputSchema = z
  .object({
    category: reminderCategorySchema,
    meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia']).optional(),
    routine_item_id: z.string().uuid().optional(),
    local_time: minuteTimeSchema,
    weekdays: reminderWeekdaysSchema,
  })
  .strict()
  .superRefine((value, context) => {
    if (value.category === 'meal' && !value.meal_type) {
      context.addIssue({ code: 'custom', path: ['meal_type'], message: 'Meal type is required' })
    }
    if (value.category !== 'meal' && value.meal_type) {
      context.addIssue({ code: 'custom', path: ['meal_type'], message: 'Meal type is not allowed' })
    }

    const routineCategory = value.category === 'supplement' || value.category === 'medication'
    if (routineCategory && !value.routine_item_id) {
      context.addIssue({
        code: 'custom',
        path: ['routine_item_id'],
        message: 'Routine item is required',
      })
    }
    if (!routineCategory && value.routine_item_id) {
      context.addIssue({
        code: 'custom',
        path: ['routine_item_id'],
        message: 'Routine item is not allowed',
      })
    }
  })

export const patchReminderInputSchema = z
  .object({
    local_time: minuteTimeSchema.optional(),
    weekdays: reminderWeekdaysSchema.optional(),
    active: z.boolean().optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, 'At least one field is required')

export const hydrationInputSchema = z
  .object({
    amount_ml: z.number().int().min(1).max(5000),
    occurred_at: z.string().datetime({ offset: true }),
  })
  .strict()

export const markRoutineTakenInputSchema = z
  .object({ occurred_at: z.string().datetime({ offset: true }) })
  .strict()

export type PatchMeInput = z.infer<typeof patchMeInputSchema>
export type OnboardingInput = z.infer<typeof onboardingInputSchema>
export type RegistrationProposalInput = z.infer<typeof registrationProposalInputSchema>
export type HistoryQuery = z.infer<typeof historyQuerySchema>
export type MediaUploadInput = z.infer<typeof mediaUploadInputSchema>
export type MobileDeviceInput = z.infer<typeof mobileDeviceInputSchema>
export type NotificationPreferencesPatch = z.infer<typeof notificationPreferencesPatchSchema>
export type CreateReminderInput = z.infer<typeof createReminderInputSchema>
export type PatchReminderInput = z.infer<typeof patchReminderInputSchema>
export type HydrationInput = z.infer<typeof hydrationInputSchema>
export type MarkRoutineTakenInput = z.infer<typeof markRoutineTakenInputSchema>

export { localeSchema, timezoneSchema }
