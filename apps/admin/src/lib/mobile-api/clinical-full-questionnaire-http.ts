import { requiresReevaluationPhotos } from '@mpp/core/reevaluation-form'
/** Prepared public handlers only. No route.ts, flag or default consumer mounts
 * this capability until the complete clinical release is qualified. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  clinicalFullError,
  fullChoiceSchema,
  fullKind,
  fullPhase,
  fullPrincipal,
} from './clinical-full-contracts'
import type { createClinicalFullQuestionnaire } from './clinical-full-questionnaire'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteRuntime } from './route'

const option = z
  .object({ value: z.union([z.string(), z.boolean()]), label: z.string().min(1) })
  .strict()
const questionKey = z.enum([
  'weightKg',
  'strengthSessions',
  'adherence',
  'hunger',
  'energy',
  'strengthProgression',
  'fatPerception',
  'difficultToMaintain',
  'healthCheck',
  'professionalConversationConfirmed',
  'activity.otherExerciseType',
  'activity.otherExerciseDays',
  'activity.sessionMinutes',
  'activity.sessionIntensity',
  'activity.mostlySitting',
  'activity.activityLevel',
])
export const clinicalFullQuestionnaireDto = z
  .object({
    version: z.literal(1),
    locale: z.enum(['pt-BR', 'en-US']),
    kind: fullKind,
    cycle_id: uuid.nullable(),
    activity_purpose: z.enum(['normal', 'consider_maintenance', 'end_deficit']),
    activity_purpose_options: z
      .array(z.enum(['normal', 'consider_maintenance', 'end_deficit']))
      .min(1)
      .max(3),
    questions: z
      .array(
        z
          .object({
            key: questionKey,
            label: z.string().min(1),
            input_kind: z.enum([
              'decimal',
              'integer',
              'text',
              'boolean',
              'single_choice',
              'health_selection',
            ]),
            unit: z.enum(['kg', 'per_week', 'minutes']).nullable(),
            opt_out_label: z.string().min(1),
            options: z.array(option).max(9).nullable(),
            min: z.number().finite().nullable(),
            max: z.number().finite().nullable(),
            preselected: z.enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta']).nullable(),
            initially_confirmed: z.literal(false).nullable(),
            hint: z.string().min(1).nullable(),
          })
          .strict(),
      )
      .max(16),
    preference_question: z
      .object({
        label: z.string().min(1),
        optional: z.literal(true),
        options: z.array(option).max(6),
        routine_options: z.array(option).max(4),
        existing_actions: z.array(z.enum(['keep', 'change', 'remove'])).max(3),
      })
      .strict()
      .nullable(),
    support_text: z.null(),
    photo_requirement: z
      .object({
        required: z.boolean(),
        new_only: z.literal(true),
        poses: z.tuple([z.literal('front'), z.literal('side'), z.literal('back')]),
      })
      .strict(),
    body_fat: z.discriminatedUnion('status', [
      z
        .object({
          status: z.literal('ready'),
          percent: z.number().finite().min(3).max(60),
          candidate_id: z.string().regex(/^[0-9a-f]{64}$/),
        })
        .strict(),
      z.object({ status: z.literal('photos_required') }).strict(),
      z.object({ status: z.literal('not_required') }).strict(),
    ]),
  })
  .strict()
  .refine((v) => requiresReevaluationPhotos(v.kind) === v.photo_requirement.required)
export const clinicalFullAssessmentDto = z
  .object({
    version: z.literal(1),
    status: z.enum([
      'available',
      'no_change_available',
      'health_declaration_required',
      'photos_required',
      'body_fat_confirmation_required',
    ]),
    actions: z
      .array(
        z
          .object({
            choice: fullChoiceSchema,
            principal: fullPrincipal,
            phase: fullPhase.nullable(),
            targets: z
              .object({
                calories_kcal: z.number().int().positive().max(2147483647).nullable(),
                protein_g: z.number().finite().min(0).max(9999.99).nullable(),
              })
              .strict(),
            professional_assessment_recommended: z.boolean(),
            pause_weight_loss_guidance: z.boolean(),
          })
          .strict(),
      )
      .max(8),
    preference: z
      .object({
        status: z.enum(['unchanged', 'removed', 'accepted', 'refused', 'missing']),
        reason: z.enum(['body_fat_floor', 'weight_bmi_floor', 'dependent_context']).nullable(),
        missing: z.array(z.enum(['sex', 'heightCm'])).max(2),
      })
      .strict()
      .nullable(),
  })
  .strict()
  .refine((v) => (v.status === 'available' ? v.actions.length > 0 : v.actions.length === 0))
type Service = Pick<ReturnType<typeof createClinicalFullQuestionnaire>, 'describe' | 'assess'>
function output<S extends z.ZodTypeAny>(schema: S, value: unknown): z.infer<S> {
  const result = schema.safeParse(value)
  if (!result.success) throw clinicalFullError('unavailable')
  return result.data
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
export function createClinicalFullQuestionnaireRoutes(
  dependencies: { readonly enabled: boolean; createService(client: ServiceClient): Service },
  runtime?: MobileRouteRuntime,
) {
  const enabled = dependencies.enabled === true,
    createService = dependencies.createService.bind(dependencies)
  const fixedRuntime =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  const handler = (method: 'describe' | 'assess') =>
    createMobileRoute(async (context) => {
      if (!enabled)
        throw new MobileApiError(
          404,
          'clinical_full_questionnaire_unavailable',
          'Review unavailable',
        )
      if (new URL(context.request.url).searchParams.size) throw clinicalFullError('invalid')
      const auth = freeze(structuredClone(context.auth))
      authenticatedReevaluationOwner(auth)
      const body = await readJsonBody(context.request, 16384)
      const service = createService(context.supabase),
        call = service[method].bind(service)
      const value = await call(auth, body)
      return mobileSuccess(
        method === 'describe'
          ? output(clinicalFullQuestionnaireDto, value)
          : output(clinicalFullAssessmentDto, value),
        context.requestId,
      )
    }, fixedRuntime)
  return Object.freeze({ DESCRIBE: handler('describe'), ASSESS: handler('assess') })
}
