/** Injection-only public write boundary. Private prepared/result packets never
 * leave these handlers. No default route/flag mounts this partial composition. */

import { healthRiskSetSchema } from '@mpp/core/health-check'
import {
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  clinicalFullError,
  fullChoiceSchema,
  fullCommandPreparedSchema,
  fullConfirmedSchema,
  fullKind,
  fullPhase,
} from './clinical-full-contracts'
import { clinicalFullPublicInputSchema } from './clinical-full-public-command'
import type { createClinicalFullService } from './clinical-full-service'
import { declareHealthRisk, type HealthHoldDependencies } from './health-hold-service'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteRuntime } from './route'

const previewBase = {
  version: z.literal(1),
  preview_id: uuid,
  kind: fullKind,
  cycle_id: uuid.nullable(),
  expires_at: instant,
}
export const clinicalFullPreviewDto = z.discriminatedUnion('status', [
  z
    .object({
      ...previewBase,
      status: z.literal('ready'),
      choice: fullChoiceSchema,
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
  z.object({ ...previewBase, status: z.literal('historical_display_unavailable') }).strict(),
])
export const clinicalFullConfirmationDto = z
  .object({
    version: z.literal(1),
    review_id: uuid,
    kind: fullKind,
    cycle_id: uuid.nullable(),
    completed_at: instant,
    next_due_date: date,
  })
  .strict()
export const clinicalFullHealthDeclarationDto = z
  .object({ version: z.literal(1), receipt_id: uuid, declared_at: instant })
  .strict()
const prepareInput = z
  .object({ kind: fullKind, cycleId: uuid.nullable(), input: clinicalFullPublicInputSchema })
  .strict()
const confirmInput = prepareInput.extend({ previewId: uuid }).strict()
const healthInput = z.object({ items: healthRiskSetSchema }).strict()
function output<S extends z.ZodTypeAny>(schema: S, raw: unknown): z.infer<S> {
  const p = schema.safeParse(raw)
  if (!p.success) throw clinicalFullError('unavailable')
  return p.data
}
export function projectClinicalFullPreview(raw: unknown) {
  const packet = output(fullCommandPreparedSchema, raw),
    policy = packet.presentation
  const base = {
    version: 1 as const,
    preview_id: packet.preview.preview_id,
    kind: packet.preview.review_kind,
    cycle_id: packet.preview.cycle_id,
    expires_at: packet.preview.valid_until,
  }
  if (!policy)
    return output(clinicalFullPreviewDto, { ...base, status: 'historical_display_unavailable' })
  const proposal = packet.package.proposal
  return output(clinicalFullPreviewDto, {
    ...base,
    status: 'ready',
    choice: packet.command.choice,
    phase: policy.hide.objective ? null : proposal.profile.current_protocol,
    targets: {
      calories_kcal: policy.hide.calories ? null : proposal.targets.afterKcal,
      protein_g: policy.hide.protein ? null : proposal.targets.afterProtein,
    },
    professional_assessment_recommended: policy.professionalAssessmentRecommended,
    pause_weight_loss_guidance: policy.pauseWeightLossGuidance,
  })
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
type Service = Pick<ReturnType<typeof createClinicalFullService>, 'preparePublic' | 'confirmPublic'>
export function createClinicalFullRoutes(
  dependencies: {
    readonly enabled: boolean
    createService(client: ServiceClient): Service
    createHealthDependencies(client: ServiceClient): HealthHoldDependencies
  },
  runtime?: MobileRouteRuntime,
) {
  const enabled = dependencies.enabled === true,
    createService = dependencies.createService.bind(dependencies),
    healthDependencies = dependencies.createHealthDependencies.bind(dependencies)
  const fixedRuntime =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  const route = (method: 'preparePublic' | 'confirmPublic' | 'health') =>
    createMobileRoute(async (context) => {
      if (!enabled) throw new MobileApiError(404, 'clinical_full_unavailable', 'Review unavailable')
      if (new URL(context.request.url).searchParams.size) throw clinicalFullError('invalid')
      const auth = freeze(structuredClone(context.auth))
      authenticatedReevaluationOwner(auth)
      const key = uuid.parse(requireIdempotencyKey(context.request)).toLowerCase()
      const raw = await readJsonBody(context.request, 16384)
      if (method === 'health') {
        const input = healthInput.parse(raw)
        const result = await declareHealthRisk(
          auth,
          key,
          input.items,
          healthDependencies(context.supabase),
        )
        if (result.availability !== 'available') throw clinicalFullError('unavailable')
        return mobileSuccess(
          output(clinicalFullHealthDeclarationDto, {
            version: 1,
            receipt_id: result.receipt.id,
            declared_at: result.receipt.declared_at,
          }),
          context.requestId,
        )
      }
      const input = (method === 'preparePublic' ? prepareInput : confirmInput).parse(raw)
      const service = createService(context.supabase),
        call = service[method].bind(service)
      const packet = await call(auth, { ...input, operationKey: key })
      if (method === 'preparePublic')
        return mobileSuccess(projectClinicalFullPreview(packet), context.requestId)
      const ack = output(fullConfirmedSchema, packet)
      return mobileSuccess(
        output(clinicalFullConfirmationDto, {
          version: 1,
          review_id: ack.result.review_id,
          kind: ack.result.kind,
          cycle_id: ack.result.cycle_id,
          completed_at: ack.result.completed_at,
          next_due_date: ack.result.next_due_date,
        }),
        context.requestId,
      )
    }, fixedRuntime)
  return Object.freeze({
    PREVIEW: route('preparePublic'),
    CONFIRM: route('confirmPublic'),
    DECLARE_HEALTH: route('health'),
  })
}
