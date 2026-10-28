/** Injection-only explicit later phase. Client selects a phase; the server
 * captures facts, calculates, previews and confirms. No default activation. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  evaluateClinicalFirstPhase,
  projectClinicalFirstPhase,
} from './clinical-first-phase-calculation'
import {
  type ClinicalFirstPhasePrepared,
  clinicalFirstPhaseConfirmedSchema,
  clinicalFirstPhaseError,
  clinicalFirstPhaseSelectionSchema,
} from './clinical-first-phase-contracts'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import type { createSupabaseClinicalFirstPhaseRepository } from './supabase-clinical-first-phase'

type Repository = ReturnType<typeof createSupabaseClinicalFirstPhaseRepository>
const requestSchema = z
  .object({ operationKey: uuid, selection: clinicalFirstPhaseSelectionSchema })
  .strict()
const confirmSchema = requestSchema.extend({ previewId: uuid }).strict()
function input<S extends z.ZodTypeAny>(schema: S, raw: unknown): z.infer<S> {
  const p = schema.safeParse(structuredClone(raw))
  if (!p.success) throw clinicalFirstPhaseError('invalid')
  return p.data
}
function original(p: ClinicalFirstPhasePrepared, selection: unknown) {
  if (!isDeepStrictEqual(p.selection, selection)) throw clinicalFirstPhaseError('changed')
}
function evaluate(raw: unknown, user: string, selection: unknown) {
  try {
    return evaluateClinicalFirstPhase(raw, user, selection)
  } catch (e) {
    if (e instanceof MobileApiError) throw e
    throw clinicalFirstPhaseError('changed')
  }
}
export function createClinicalFirstPhaseService(deps: {
  enabled: boolean
  repository: Repository
}) {
  const repository = deps.repository,
    capture = repository.capture.bind(repository),
    findPrepared = repository.findPrepared.bind(repository),
    prepare = repository.prepare.bind(repository),
    findReceipt = repository.findReceipt.bind(repository),
    confirm = repository.confirm.bind(repository)
  const active = deps.enabled === true
  const enabled = () => {
    if (!active) throw clinicalFirstPhaseError('unavailable')
  }
  return Object.freeze({
    async choices(auth: MobileAuthContext) {
      enabled()
      const user = authenticatedReevaluationOwner(auth)
      try {
        return projectClinicalFirstPhase(await capture(user), user)
      } catch (e) {
        if (e instanceof MobileApiError) throw e
        throw clinicalFirstPhaseError('unavailable')
      }
    },
    async prepare(auth: MobileAuthContext, raw: unknown) {
      enabled()
      const user = authenticatedReevaluationOwner(auth),
        r = input(requestSchema, raw)
      const old = await findPrepared(user, { operationKey: r.operationKey })
      if (old) {
        original(old, r.selection)
        return old
      }
      const result = evaluate(await capture(user), user, r.selection)
      return prepare(
        user,
        r.operationKey,
        result.context.context_hash,
        result.selection,
        result.package,
      )
    },
    async confirm(auth: MobileAuthContext, raw: unknown) {
      enabled()
      const user = authenticatedReevaluationOwner(auth),
        r = input(confirmSchema, raw)
      const receipt = await findReceipt(user, r.previewId, r.operationKey)
      if (receipt) {
        original(receipt.prepared, r.selection)
        if (receipt.operation_matched)
          return clinicalFirstPhaseConfirmedSchema.parse({
            user_id: user,
            preview_id: r.previewId,
            operation_key: r.operationKey,
            result: receipt.result,
          })
        return confirm(user, receipt.prepared, r.operationKey)
      }
      const prepared = await findPrepared(user, { previewId: r.previewId })
      if (!prepared) throw clinicalFirstPhaseError('changed')
      original(prepared, r.selection)
      const current = evaluate(await capture(user), user, r.selection)
      if (
        current.context.context_hash !== prepared.context_hash ||
        current.context.observed_at < prepared.created_at ||
        current.context.observed_at >= prepared.valid_until ||
        !isDeepStrictEqual(current.package, prepared.package)
      )
        throw clinicalFirstPhaseError('changed')
      return confirm(user, prepared, r.operationKey)
    },
  })
}
