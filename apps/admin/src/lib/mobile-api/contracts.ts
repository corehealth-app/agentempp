import { routinePreviewModeSchema, selectableCoachPersonalitySchema } from '@mpp/core'
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

export const flowChatInputSchema = z.object({ text: z.string().trim().min(1).max(4000) }).strict()

export const flowChatLimitSchema = z.coerce.number().int().min(1).max(50)

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
const onboardingLocaleSchema = z.enum(['pt-BR', 'en-US'])

const onboardingDocumentKeySchema = z
  .string()
  .min(1)
  .max(100)
  .regex(/^[a-z][a-z0-9_]*$/)
  .refine((value) => !value.startsWith('dev_'), 'Development documents are not accepted')

const onboardingDocumentActionSchema = z.enum(['acceptance', 'acknowledgement', 'consent'])

// The body values the objective is decided on. One definition for the sign-up
// and for its eligibility check, so the two can never accept different ranges.
const signupSexSchema = z.enum(['masculino', 'feminino'])
const signupHeightCmSchema = z.number().min(100).max(250)
const signupWeightKgSchema = z.number().min(30).max(300)
const signupBodyFatPercentSchema = z.number().min(3).max(60)
const signupTrainingFrequencySchema = z.number().int().min(0).max(7)

export const onboardingDocumentActionInputSchema = z
  .object({
    document_key: onboardingDocumentKeySchema,
    version: z
      .string()
      .min(1)
      .max(64)
      .regex(/^[A-Za-z0-9._-]+$/),
    locale: onboardingLocaleSchema,
    content_hash: z.string().regex(/^[0-9a-f]{64}$/),
    action: onboardingDocumentActionSchema,
  })
  .strict()

/** Explicit intent only: the server derives the value from these official sources. */
export const signupBodyPhotoConfirmationInputSchema = z.discriminatedUnion('decision', [
  z
    .object({
      decision: z.literal('accept'),
      source_ids: z
        .object({ front: z.string().uuid(), side: z.string().uuid(), back: z.string().uuid() })
        .strict()
        .refine(
          (ids) => new Set(Object.values(ids).map((id) => id.toLowerCase())).size === 3,
          'Photo source IDs must be distinct',
        ),
      fingerprint: z.string().regex(/^[0-9a-f]{64}$/),
    })
    .strict(),
  z.object({ decision: z.literal('decline') }).strict(),
])

export const onboardingCompletionInputSchema = z
  .object({
    name: z.string().trim().min(1).max(100),
    locale: onboardingLocaleSchema,
    country: z.string().regex(/^[A-Z]{2}$/),
    timezone: timezoneSchema,
    sex: signupSexSchema,
    birth_date: z.string().date(),
    height_cm: signupHeightCmSchema,
    weight_kg: signupWeightKgSchema,
    body_fat_percent: signupBodyFatPercentSchema.optional(),
    body_photo_confirmation: signupBodyPhotoConfirmationInputSchema.optional(),
    // Required explicit JSON null is a server-checked no-plan request, never
    // permission supplied by the client. Missing key remains invalid.
    objective: z.enum(['recomposicao', 'ganho_massa', 'manutencao']).nullable(),
    activity_level: z.enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta']),
    training_frequency: signupTrainingFrequencySchema,
    // Unknown is real absence, never an invented hydration habit.
    water_intake: z.enum(['pouco', 'moderado', 'bastante']).nullable().optional().default(null),
    hunger_level: z.enum(['pouca', 'moderada', 'muita']),
    wake_time: timeSchema,
    bedtime: timeSchema,
    food_organization: z.enum(['sim', 'nao']),
    persona: selectableCoachPersonalitySchema,
    document_actions: z.array(onboardingDocumentActionInputSchema).min(1).max(16),
  })
  .strict()
  .superRefine((value, context) => {
    const identities = new Set<string>()
    for (const [index, document] of value.document_actions.entries()) {
      const identity = `${document.document_key}:${document.version}:${document.locale}`
      if (identities.has(identity)) {
        context.addIssue({
          code: 'custom',
          path: ['document_actions', index],
          message: 'Document actions must be unique',
        })
      }
      identities.add(identity)
    }
  })

// Sign-up eligibility check (POST /onboarding/eligibility): only what the
// rule reads, plus the language of the texts. No name, no birth date, no
// objective: the answer says which objectives may be recorded.
export const onboardingEligibilityInputSchema = z
  .object({
    locale: onboardingLocaleSchema,
    sex: signupSexSchema,
    height_cm: signupHeightCmSchema,
    weight_kg: signupWeightKgSchema,
    body_fat_percent: signupBodyFatPercentSchema.optional(),
    training_frequency: signupTrainingFrequencySchema,
  })
  .strict()

/** Current clinical representation. Health is admitted separately; no client
 * safety flags, civil clock or clinical authority are accepted here. */
export const onboardingCurrentEligibilityInputSchema = onboardingEligibilityInputSchema
  .extend({
    version: z.literal(2),
    timezone: timezoneSchema,
    birth_date: z.string().date(),
    body_fat_percent: signupBodyFatPercentSchema.nullable().optional(),
  })
  .strict()

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
    onboarding_completed: z.literal(false).optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, 'At least one field is required')

const mealItemInputSchema = z
  .object({
    food_name: z.string().trim().min(1).max(160),
    quantity_g: z.number().positive().max(9999),
    user_kcal: z.number().nonnegative().max(20_000).optional(),
    // Where the quantity came from, as the patient reviewed it.
    quantity_basis: z.enum(['stated', 'visual_estimate', 'portion_reference']).optional(),
    candidate_id: z
      .string()
      .regex(/^c\d{1,2}-[0-9a-f]{8}$/)
      .optional(),
    // The patient tied the photographed nutrition label to this item. The
    // server reads the label again from the processed media; the client never
    // sends macros.
    use_nutrition_label: z.literal(true).optional(),
  })
  .strict()

const mealSourceSchema = z
  .object({
    channel: z.enum(['text', 'camera', 'gallery', 'audio_recording', 'audio_import']),
    media_asset_id: z.string().uuid().optional(),
  })
  .strict()

const mealProposalInputSchema = z
  .object({
    kind: z.literal('meal'),
    meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
    items: z.array(mealItemInputSchema).min(1).max(30),
    consumed_at: z.string().datetime({ offset: true }).optional(),
    source: mealSourceSchema.optional(),
  })
  .strict()

export const workoutProposalInputSchema = z
  .object({
    kind: z.literal('workout'),
    workout_type: z.string().trim().min(1).max(80),
    duration_min: z.number().int().positive().max(1440),
    intensity: z.enum(['leve', 'moderada', 'alta']).default('moderada'),
    performed_at: z.string().datetime({ offset: true }).optional(),
  })
  .strict()

export const registrationProposalInputSchema = z
  .discriminatedUnion('kind', [mealProposalInputSchema, workoutProposalInputSchema])
  .superRefine((value, context) => {
    if (value.kind !== 'meal') return
    const hasMedia = value.source?.media_asset_id != null
    if (value.source && (value.source.channel === 'text') === hasMedia) {
      context.addIssue({
        code: 'custom',
        path: ['source', 'media_asset_id'],
        message: 'media_asset_id is required for media channels and not allowed for text',
      })
    }
    const labelled = value.items.filter((item) => item.use_nutrition_label)
    if (labelled.length > 1) {
      context.addIssue({
        code: 'custom',
        path: ['items'],
        message: 'Only one item may use the nutrition label',
      })
    }
    if (
      labelled.length === 1 &&
      !(hasMedia && (value.source?.channel === 'camera' || value.source?.channel === 'gallery'))
    ) {
      context.addIssue({
        code: 'custom',
        path: ['source'],
        message: 'A nutrition label needs the photo it came from',
      })
    }
  })

export const historyQuerySchema = z
  .object({
    before: z.string().datetime({ offset: true }).optional(),
    limit: z.coerce.number().int().min(1).max(100).default(30),
  })
  .strict()

/// Trends window for the charts: a fixed, bounded number of past days.
export const trendsQuerySchema = z
  .object({
    days: z.coerce.number().int().min(7).max(90).default(14),
  })
  .strict()

export const resourceIdSchema = z.string().uuid()

export const mealDraftInputSchema = z.discriminatedUnion('source', [
  z.object({ source: z.literal('text'), text: z.string().trim().min(1).max(2000) }).strict(),
  z.object({ source: z.literal('media'), media_asset_id: resourceIdSchema }).strict(),
])

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
    // Declared by the app before the upload; only a pre-filter. The worker
    // measures the real length from the file before any transcription.
    duration_ms: z.number().int().positive().max(86_400_000).optional(),
    kind: z.literal('audio_note'),
    mime_type: patientAudioMimeSchema,
    size_bytes: z
      .number()
      .int()
      .positive()
      .max(25 * 1024 * 1024),
  })
  .strict()

// The photo or PDF of a plan the patient already has. It becomes a draft for
// review, never a plan by itself.
const mediaPlanDocumentUploadSchema = mediaUploadBaseSchema
  .extend({
    kind: z.literal('plan_document'),
    // Only what the document reader handles: the text layer of a PDF, or a
    // photo in a format the transcription model accepts. The app sends PDF
    // or JPEG; a HEIC photo is converted on the phone before it leaves.
    mime_type: z.enum(['application/pdf', 'image/jpeg', 'image/png', 'image/webp']),
    size_bytes: z
      .number()
      .int()
      .positive()
      .max(20 * 1024 * 1024),
  })
  .strict()

export const mediaUploadInputSchema = z.discriminatedUnion('kind', [
  mediaPhotoUploadSchema,
  mediaAudioUploadSchema,
  mediaPlanDocumentUploadSchema,
])

export const planDraftListQuerySchema = z
  .object({
    status: z.enum(['open', 'ready_for_review', 'needs_completion']).default('open'),
  })
  .strict()

// The content is assessed by the domain rules, not here: an incomplete edit
// is accepted and kept as incomplete. Only its size and shape are bounded.
export const planDraftPatchSchema = z
  .object({
    payload_version: z.number().int().min(1),
    payload: z.record(z.unknown()),
  })
  .strict()

export const planDraftConfirmSchema = z
  .object({ payload_version: z.number().int().min(1) })
  .strict()

export const planImportInputSchema = z
  .object({
    media_asset_id: resourceIdSchema,
    domain: z.enum(['training', 'nutrition']),
  })
  .strict()

// Body photos of the sign-up: the acceptance of their own consent. The version
// and the mark are the ones of the text the person read; the birth date is
// only checked against the minimum age and is never recorded.
export const signupBodyPhotoConsentInputSchema = z
  .object({
    version: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),
    body_hash: z.string().regex(/^[0-9a-f]{64}$/),
    birth_date: z.string().date(),
  })
  .strict()

// Body photos of the sign-up: one photo of one pose. Only JPEG (the app
// rebuilds the image without metadata before it leaves the phone) and nothing
// else of the generic upload: no kind and no caption come from the client.
export const signupBodyPhotoUploadInputSchema = z
  .object({
    pose: z.enum(['front', 'side', 'back']),
    mime_type: z.literal('image/jpeg'),
    size_bytes: z
      .number()
      .int()
      .positive()
      .max(15 * 1024 * 1024),
  })
  .strict()

// A retry of a finished signup may not delete photos of a reopened signup.
// Keep the official instant literal, including its microseconds, in the hash.
export const signupBodyPhotoRepairInputSchema = z
  .object({
    mode: z.literal('repair_completed'),
    generation: z
      .string()
      .max(64)
      .datetime({ offset: true })
      .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/)
      .refine((value) => Number.isFinite(Date.parse(value))),
  })
  .strict()

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
    routine_preview_mode: routinePreviewModeSchema.optional(),
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

export const weightInputSchema = z
  .object({
    value: z.number().finite().positive().max(700),
    unit: z.enum(['kg', 'lb']),
    measured_at: z.string().datetime({ offset: true }),
  })
  .strict()

export const markRoutineTakenInputSchema = z
  .object({ occurred_at: z.string().datetime({ offset: true }) })
  .strict()

export type PatchMeInput = z.infer<typeof patchMeInputSchema>
export type OnboardingInput = z.infer<typeof onboardingInputSchema>
export type OnboardingCompletionInput = z.infer<typeof onboardingCompletionInputSchema>
export type SignupBodyPhotoConfirmationInput = z.infer<
  typeof signupBodyPhotoConfirmationInputSchema
>
export type OnboardingEligibilityInput = z.infer<typeof onboardingEligibilityInputSchema>
export type OnboardingDocumentActionInput = z.infer<typeof onboardingDocumentActionInputSchema>
export type RegistrationProposalInput = z.infer<typeof registrationProposalInputSchema>
export type HistoryQuery = z.infer<typeof historyQuerySchema>
export type TrendsQuery = z.infer<typeof trendsQuerySchema>
export type MediaUploadInput = z.infer<typeof mediaUploadInputSchema>
export type SignupBodyPhotoConsentInput = z.infer<typeof signupBodyPhotoConsentInputSchema>
export type SignupBodyPhotoUploadInput = z.infer<typeof signupBodyPhotoUploadInputSchema>
export type MobileDeviceInput = z.infer<typeof mobileDeviceInputSchema>
export type NotificationPreferencesPatch = z.infer<typeof notificationPreferencesPatchSchema>
export type CreateReminderInput = z.infer<typeof createReminderInputSchema>
export type PatchReminderInput = z.infer<typeof patchReminderInputSchema>
export type HydrationInput = z.infer<typeof hydrationInputSchema>
export type MealDraftInput = z.infer<typeof mealDraftInputSchema>
export type PlanDraftPatchInput = z.infer<typeof planDraftPatchSchema>
export type PlanDraftConfirmInput = z.infer<typeof planDraftConfirmSchema>
export type PlanImportInput = z.infer<typeof planImportInputSchema>
export type PlanDraftListQuery = z.infer<typeof planDraftListQuerySchema>
export type WeightInput = z.infer<typeof weightInputSchema>
export type MarkRoutineTakenInput = z.infer<typeof markRoutineTakenInputSchema>

const confirmedMealSelectionSchema = z
  .array(resourceIdSchema.transform((id) => id.toLowerCase()))
  .min(1)
  .max(30)
  .superRefine((ids, context) => {
    if (new Set(ids).size !== ids.length) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'Meal item ids must be unique' })
    }
  })

export const confirmedMealPatchInputSchema = z
  .object({
    expected_version: z.string().regex(/^v1:[0-9a-f]{64}$/),
    item_ids: confirmedMealSelectionSchema,
    items: z.array(mealItemInputSchema).min(1).max(30),
  })
  .strict()
  .superRefine((input, context) => {
    if (input.item_ids.length !== 1) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['item_ids'],
        message: 'Edit one confirmed food item per operation',
      })
    }
    if (input.items.some((item) => item.use_nutrition_label === true)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['items'],
        message: 'This operation does not accept a new nutrition-label source',
      })
    }
  })

export const confirmedMealDeleteInputSchema = z
  .object({
    expected_version: z.string().regex(/^v1:[0-9a-f]{64}$/),
    item_ids: confirmedMealSelectionSchema,
  })
  .strict()

export type ConfirmedMealPatchInput = z.infer<typeof confirmedMealPatchInputSchema>
export type ConfirmedMealDeleteInput = z.infer<typeof confirmedMealDeleteInputSchema>

export { localeSchema, timezoneSchema }
