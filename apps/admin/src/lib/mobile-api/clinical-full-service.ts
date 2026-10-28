/** Authenticated, injection-only FULL orchestration. Returned packets are
 * private authority, not public DTOs. No default route/flag enables this. */
import { isDeepStrictEqual } from 'node:util'
import { isFullReevaluationKind } from '@mpp/core/reevaluation-form'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { readClinicalFullContext } from './clinical-full-authority'
import { normalizeClinicalFullCommand } from './clinical-full-command'
import {
  type ClinicalFullCommandPrepared,
  type ClinicalFullScope,
  clinicalFullError,
  fullConfirmedSchema,
  fullKind,
} from './clinical-full-contracts'
import { evaluateClinicalFull } from './clinical-full-evaluation'
import {
  bindClinicalFullPublicCommand,
  clinicalFullPublicInputSchema,
} from './clinical-full-public-command'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import type { createSupabaseClinicalFullRepository } from './supabase-clinical-full'

type Repository = Pick<
  ReturnType<typeof createSupabaseClinicalFullRepository>,
  'capture' | 'findPrepared' | 'prepareCommand' | 'findCommandReceipt' | 'confirmCommand'
>
interface Dependencies {
  readonly enabled: boolean
  readonly repository: Repository
}
const requestShape = {
  kind: fullKind,
  cycleId: uuid.nullable(),
  operationKey: uuid,
  input: z.unknown(),
}
const prepareSchema = z.object(requestShape).strict()
const confirmSchema = z.object({ ...requestShape, previewId: uuid }).strict()
const publicPrepareSchema = prepareSchema.extend({ input: clinicalFullPublicInputSchema })
const publicConfirmSchema = confirmSchema.extend({ input: clinicalFullPublicInputSchema })
function invalid(): never {
  throw new MobileApiError(422, 'mobile_clinical_full_invalid', 'Invalid clinical review request')
}
function request<S extends z.ZodTypeAny>(schema: S, value: unknown): z.infer<S> {
  try {
    return schema.parse(structuredClone(value))
  } catch {
    return invalid()
  }
}
function scopeFor(
  user: string,
  kind: ClinicalFullScope['kind'],
  cycle: string | null,
): ClinicalFullScope {
  if (isFullReevaluationKind(kind) !== (cycle !== null)) return invalid()
  return { userId: user.toLowerCase(), kind, cycleId: cycle?.toLowerCase() ?? null }
}
function sameScope(prepared: ClinicalFullCommandPrepared, scope: ClinicalFullScope) {
  const p = prepared.preview
  if (
    p.user_id.toLowerCase() !== scope.userId ||
    p.review_kind !== scope.kind ||
    p.cycle_id?.toLowerCase() !== scope.cycleId?.toLowerCase()
  )
    throw clinicalFullError('changed')
}
function assertOriginal(
  prepared: ClinicalFullCommandPrepared,
  scope: ClinicalFullScope,
  raw: unknown,
) {
  sameScope(prepared, scope)
  let command: ReturnType<typeof normalizeClinicalFullCommand>['command']
  try {
    command = normalizeClinicalFullCommand(
      raw,
      prepared.normalization_context,
      prepared.command.form,
    ).command
  } catch {
    return invalid()
  }
  if (!isDeepStrictEqual(command, prepared.command)) throw clinicalFullError('changed')
}
function newEvaluation(raw: unknown, scope: ClinicalFullScope, input: unknown) {
  try {
    const context = readClinicalFullContext(raw, scope)
    const origin = context.facts.protocol_authority.phase_origin
    let bound = input
    if (
      (origin.kind === 'confirmed_no_plan' || origin.kind === 'legacy_transition_unassigned') &&
      input &&
      typeof input === 'object' &&
      !Array.isArray(input)
    ) {
      const original = (input as { form?: unknown }).form
      if (original && typeof original === 'object' && !Array.isArray(original)) {
        const key = origin.kind === 'legacy_transition_unassigned' ? 'legacyOrigin' : 'noPlanOrigin'
        if (Object.hasOwn(original, key) && !isDeepStrictEqual(Reflect.get(original, key), origin))
          return invalid()
        bound = { ...input, form: { ...original, [key]: origin } }
      }
    }
    return evaluateClinicalFull(raw, scope, bound)
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    throw clinicalFullError('changed')
  }
}
function displayPolicy(evaluated: ReturnType<typeof evaluateClinicalFull>) {
  const { hide, professionalAssessmentRecommended, pauseWeightLossGuidance } = evaluated.safety
  return {
    version: 1 as const,
    hide: { objective: hide.objective, calories: hide.calories, protein: hide.protein },
    professionalAssessmentRecommended,
    pauseWeightLossGuidance,
  }
}

export function createClinicalFullService(dependencies: Dependencies) {
  if (dependencies.enabled !== true) {
    const disabled = async (_auth: MobileAuthContext, _request: unknown): Promise<never> => {
      throw clinicalFullError('unavailable')
    }
    return Object.freeze({
      prepare: disabled,
      confirm: disabled,
      preparePublic: disabled,
      confirmPublic: disabled,
    })
  }
  const repository = dependencies.repository
  // Fix functions and receiver before any asynchronous work. Callers cannot
  // substitute the owner, request or a dependency while lookup is awaiting.
  const capture = repository.capture.bind(repository)
  const findPrepared = repository.findPrepared.bind(repository)
  const prepareCommand = repository.prepareCommand.bind(repository)
  const findReceipt = repository.findCommandReceipt.bind(repository)
  const confirmCommand = repository.confirmCommand.bind(repository)
  const prepare = async (auth: MobileAuthContext, rawRequest: unknown, publicInput: boolean) => {
    const user = authenticatedReevaluationOwner(auth)
    const input = request(publicInput ? publicPrepareSchema : prepareSchema, rawRequest)
    const scope = scopeFor(user, input.kind, input.cycleId),
      key = input.operationKey.toLowerCase()
    const existing = await findPrepared(scope.userId, { prepareOperationKey: key })
    if (existing !== null) {
      sameScope(existing, scope)
      assertOriginal(
        existing,
        scope,
        publicInput
          ? bindClinicalFullPublicCommand(input.input, scope, { prepared: existing })
          : input.input,
      )
      return existing
    }
    const raw = await capture(scope)
    const boundInput = publicInput
      ? bindClinicalFullPublicCommand(input.input, scope, {
          context: readClinicalFullContext(raw, scope),
        })
      : input.input
    const evaluated = newEvaluation(raw, scope, boundInput)
    const args = [
      scope,
      key,
      evaluated.context.context_hash,
      evaluated.command,
      evaluated.package,
    ] as const
    return publicInput ? prepareCommand(...args, displayPolicy(evaluated)) : prepareCommand(...args)
  }
  const confirm = async (auth: MobileAuthContext, rawRequest: unknown, publicInput: boolean) => {
    const user = authenticatedReevaluationOwner(auth)
    const input = request(publicInput ? publicConfirmSchema : confirmSchema, rawRequest)
    const scope = scopeFor(user, input.kind, input.cycleId)
    const preview = input.previewId.toLowerCase(),
      key = input.operationKey.toLowerCase()
    // Receipt is first. Neither a reset, current guard nor an expired preview
    // may turn an already completed command into a new clinical application.
    const receipt = await findReceipt(scope.userId, preview, key)
    if (receipt !== null) {
      sameScope(receipt.prepared, scope)
      assertOriginal(
        receipt.prepared,
        scope,
        publicInput
          ? bindClinicalFullPublicCommand(input.input, scope, { prepared: receipt.prepared })
          : input.input,
      )
      if (receipt.operation_matched)
        return fullConfirmedSchema.parse({
          user_id: scope.userId,
          preview_id: preview,
          operation_key: key,
          result: receipt.result,
        })
      return confirmCommand(scope, preview, key, receipt.prepared.command, receipt.prepared.package)
    }
    const prepared = await findPrepared(scope.userId, { previewId: preview })
    if (prepared === null) throw clinicalFullError('changed')
    if (publicInput && prepared.presentation === undefined) throw clinicalFullError('changed')
    sameScope(prepared, scope)
    assertOriginal(
      prepared,
      scope,
      publicInput ? bindClinicalFullPublicCommand(input.input, scope, { prepared }) : input.input,
    )
    const raw = await capture(scope)
    const context = readClinicalFullContext(raw, scope)
    if (
      context.context_hash !== prepared.preview.context_hash ||
      context.observed_at < prepared.preview.created_at ||
      context.observed_at >= prepared.preview.valid_until
    )
      throw clinicalFullError('changed')
    const evaluated = newEvaluation(raw, scope, prepared.command)
    if (
      !isDeepStrictEqual(evaluated.command, prepared.command) ||
      !isDeepStrictEqual(evaluated.package, prepared.package) ||
      (publicInput && !isDeepStrictEqual(displayPolicy(evaluated), prepared.presentation))
    )
      throw clinicalFullError('changed')
    return confirmCommand(scope, preview, key, prepared.command, prepared.package)
  }
  return Object.freeze({
    prepare: (auth: MobileAuthContext, raw: unknown) => prepare(auth, raw, false),
    confirm: (auth: MobileAuthContext, raw: unknown) => confirm(auth, raw, false),
    preparePublic: (auth: MobileAuthContext, raw: unknown) => prepare(auth, raw, true),
    confirmPublic: (auth: MobileAuthContext, raw: unknown) => confirm(auth, raw, true),
  })
}
