/** Public DTO and authenticated HTTP composition. Injection only until the
 * complete clinical release (signup, native, Flow and photos) is qualified. */

import {
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  clinicalFirstPhaseError,
  clinicalFirstPhaseSelectionSchema,
} from './clinical-first-phase-contracts'
import type { createClinicalFirstPhaseService } from './clinical-first-phase-service'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteRuntime } from './route'

const phase = clinicalFirstPhaseSelectionSchema.shape.phase
export const clinicalFirstPhaseChoicesDto = z
  .object({
    version: z.literal(1),
    availability: z.enum(['available', 'blocked', 'incomplete']),
    date,
    effective_date: date,
    professional_assessment_recommended: z.boolean(),
    missing: z
      .array(
        z.enum([
          'sex',
          'birth_date',
          'height_cm',
          'weight_kg',
          'activity_level',
          'training_frequency',
          'hunger_level',
        ]),
      )
      .max(7),
    options: z
      .array(
        z
          .object({
            phase,
            status: z.enum(['available', 'blocked', 'not_offered']),
            reasons: z.array(z.enum(['gain_composition', 'gain_training'])).max(2),
          })
          .strict(),
      )
      .max(3),
  })
  .strict()
export const clinicalFirstPhasePreviewDto = z
  .object({
    version: z.literal(1),
    preview_id: uuid,
    phase,
    effective_date: date,
    expires_at: instant,
    targets: z
      .object({
        calories_kcal: z.number().int().positive().max(2147483647),
        protein_g: z.number().finite().min(0).max(9999.99),
      })
      .strict(),
  })
  .strict()
export const clinicalFirstPhaseConfirmationDto = z
  .object({
    version: z.literal(1),
    confirmation_id: uuid,
    phase,
    effective_date: date,
    confirmed_at: instant,
  })
  .strict()
const confirmInput = z.object({ preview_id: uuid, phase }).strict()
type Service = Pick<
  ReturnType<typeof createClinicalFirstPhaseService>,
  'choices' | 'prepare' | 'confirm'
>
function output<S extends z.ZodTypeAny>(schema: S, raw: unknown): z.infer<S> {
  const p = schema.safeParse(raw)
  if (!p.success) throw clinicalFirstPhaseError('unavailable')
  return p.data
}
function frozen<T>(v: T): T {
  if (v && typeof v === 'object') {
    for (const child of Object.values(v)) frozen(child)
    Object.freeze(v)
  }
  return v
}
export function createClinicalFirstPhaseRoutes(
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
  const requireEnabled = () => {
    if (!enabled)
      throw new MobileApiError(
        404,
        'clinical_first_phase_unavailable',
        'Phase selection unavailable',
      )
  }
  const noQuery = (request: Request) => {
    if (new URL(request.url).searchParams.size) throw clinicalFirstPhaseError('invalid')
  }
  return Object.freeze({
    GET: createMobileRoute(async (context) => {
      requireEnabled()
      noQuery(context.request)
      const auth = frozen(structuredClone(context.auth))
      authenticatedReevaluationOwner(auth)
      const service = createService(context.supabase),
        choices = service.choices.bind(service)
      const value = await choices(auth)
      return mobileSuccess(
        output(clinicalFirstPhaseChoicesDto, {
          version: 1,
          availability: value.availability,
          date: value.date,
          effective_date: value.effectiveDate,
          professional_assessment_recommended: value.safety.professionalAssessmentRecommended,
          missing: value.missing,
          options: value.options.map((o) => ({
            phase: o.phase,
            status: o.status,
            reasons: [...o.reasons],
          })),
        }),
        context.requestId,
      )
    }, fixedRuntime),
    PREVIEW: createMobileRoute(async (context) => {
      requireEnabled()
      noQuery(context.request)
      const auth = frozen(structuredClone(context.auth))
      authenticatedReevaluationOwner(auth)
      const key = uuid.parse(requireIdempotencyKey(context.request)).toLowerCase()
      const service = createService(context.supabase),
        prepare = service.prepare.bind(service)
      const selection = clinicalFirstPhaseSelectionSchema.parse(
        await readJsonBody(context.request, 2048),
      )
      // The authoritative service/SQL already owns replay. An outer HTTP claim
      // would obscure its exact original acknowledgement and is not added.
      const value = await prepare(auth, { operationKey: key, selection })
      return mobileSuccess(
        output(clinicalFirstPhasePreviewDto, {
          version: 1,
          preview_id: value.preview_id,
          phase: value.selection.phase,
          effective_date: value.package.effectiveDate,
          expires_at: value.valid_until,
          targets: {
            calories_kcal: value.package.targets.afterKcal,
            protein_g: value.package.targets.afterProtein,
          },
        }),
        context.requestId,
      )
    }, fixedRuntime),
    CONFIRM: createMobileRoute(async (context) => {
      requireEnabled()
      noQuery(context.request)
      const auth = frozen(structuredClone(context.auth))
      authenticatedReevaluationOwner(auth)
      const key = uuid.parse(requireIdempotencyKey(context.request)).toLowerCase()
      const service = createService(context.supabase),
        confirm = service.confirm.bind(service)
      const input = confirmInput.parse(await readJsonBody(context.request, 2048))
      const value = await confirm(auth, {
        operationKey: key,
        previewId: input.preview_id,
        selection: { phase: input.phase },
      })
      // A historical ACK is not a fresh policy/target read. The consumer must
      // refresh the official current readers even after an original replay.
      return mobileSuccess(
        output(clinicalFirstPhaseConfirmationDto, {
          version: 1,
          confirmation_id: value.result.first_phase_id,
          phase: value.result.phase,
          effective_date: value.result.effective_date,
          confirmed_at: value.result.confirmed_at,
        }),
        context.requestId,
      )
    }, fixedRuntime),
  })
}
