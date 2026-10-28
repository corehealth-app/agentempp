/** Backend-only dedicated first-phase RPCs. No raw client effects, retries,
 * arbitrary RPC/table interface, current lookup before replay or activation. */

import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ClinicalFirstPhasePrepared,
  clinicalFirstPhaseConfirmedSchema,
  clinicalFirstPhaseError,
  clinicalFirstPhasePackageSchema,
  clinicalFirstPhasePreparedSchema,
  clinicalFirstPhaseReceiptSchema,
  clinicalFirstPhaseSelectionSchema,
} from './clinical-first-phase-contracts'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

type Name =
  | 'get_mobile_clinical_first_phase_context'
  | 'get_mobile_clinical_first_phase_prepared'
  | 'get_mobile_clinical_first_phase_receipt'
  | 'prepare_mobile_clinical_first_phase'
  | 'confirm_mobile_clinical_first_phase'
type Rpc = (name: Name, args: Record<string, unknown>) => PromiseLike<unknown>
function parse<S extends z.ZodTypeAny>(schema: S, raw: unknown): z.infer<S> {
  const p = schema.safeParse(structuredClone(raw))
  if (!p.success) throw clinicalFirstPhaseError('unavailable')
  return p.data
}
function immutable<T>(v: T): T {
  if (v && typeof v === 'object') {
    for (const child of Object.values(v)) immutable(child)
    Object.freeze(v)
  }
  return v
}
function bindPrepared(p: ClinicalFirstPhasePrepared, user: string) {
  if (p.user_id !== user) throw clinicalFirstPhaseError('unavailable')
  return immutable(p)
}
function bindResult(
  result: z.infer<typeof clinicalFirstPhaseConfirmedSchema>['result'],
  prepared: ClinicalFirstPhasePrepared,
) {
  if (
    result.first_phase_id !== prepared.preview_id ||
    result.signup_generation !== prepared.signup_generation ||
    result.signup_epoch !== prepared.signup_epoch ||
    result.phase !== prepared.selection.phase ||
    result.deficit_level !== prepared.package.deficitLevel ||
    result.effective_date !== prepared.package.effectiveDate ||
    result.targets.calories_target !== prepared.package.targets.afterKcal ||
    result.targets.protein_target !== prepared.package.targets.afterProtein ||
    result.targets.formula_target !== prepared.package.targets.formulaAfterKcal ||
    result.maintenance_since !== prepared.package.episode.maintenanceSince ||
    result.confirmed_at < prepared.created_at ||
    result.confirmed_at >= prepared.valid_until
  )
    throw clinicalFirstPhaseError('unavailable')
}
export function createSupabaseClinicalFirstPhaseRepository(client: ServiceClient) {
  const rpc = client.rpc.bind(client) as unknown as Rpc
  async function call(name: Name, args: Record<string, unknown>) {
    let raw: unknown
    try {
      raw = await rpc(name, structuredClone(args))
    } catch {
      throw clinicalFirstPhaseError('unavailable')
    }
    const packet = parse(z.object({ data: z.unknown(), error: z.unknown() }), raw)
    if (packet.error != null) {
      const code =
        packet.error && typeof packet.error === 'object' && 'code' in packet.error
          ? packet.error.code
          : null
      throw clinicalFirstPhaseError(
        code === '40001' ? 'changed' : code === '55P03' ? 'busy' : 'unavailable',
      )
    }
    return packet.data
  }
  return Object.freeze({
    async capture(user: string) {
      return call('get_mobile_clinical_first_phase_context', { p_user_id: uuid.parse(user) })
    },
    async findPrepared(user: string, lookup: { previewId: string } | { operationKey: string }) {
      const preview = 'previewId' in lookup ? uuid.parse(lookup.previewId) : null,
        key = 'operationKey' in lookup ? uuid.parse(lookup.operationKey) : null
      const raw = await call('get_mobile_clinical_first_phase_prepared', {
        p_user_id: uuid.parse(user),
        p_preview_id: preview,
        p_prepare_operation_key: key,
      })
      if (raw === null) return null
      const value = bindPrepared(parse(clinicalFirstPhasePreparedSchema, raw), user)
      if (
        (preview !== null && value.preview_id !== preview) ||
        (key !== null && value.prepare_operation_key !== key)
      )
        throw clinicalFirstPhaseError('unavailable')
      return value
    },
    async prepare(user: string, key: string, hash: string, selection: unknown, proposal: unknown) {
      const s = parse(clinicalFirstPhaseSelectionSchema, selection),
        p = parse(clinicalFirstPhasePackageSchema, proposal)
      const raw = await call('prepare_mobile_clinical_first_phase', {
        p_user_id: uuid.parse(user),
        p_operation_key: uuid.parse(key),
        p_context_hash: hash,
        p_selection: s,
        p_proposal: p,
      })
      const prepared = bindPrepared(parse(clinicalFirstPhasePreparedSchema, raw), user)
      if (
        prepared.prepare_operation_key !== key ||
        prepared.context_hash !== hash ||
        prepared.selection.phase !== s.phase ||
        !isDeepStrictEqual(prepared.package, p)
      )
        throw clinicalFirstPhaseError('unavailable')
      return prepared
    },
    async findReceipt(user: string, preview: string, key: string) {
      const raw = await call('get_mobile_clinical_first_phase_receipt', {
        p_user_id: uuid.parse(user),
        p_preview_id: uuid.parse(preview),
        p_operation_key: uuid.parse(key),
      })
      if (raw === null) return null
      const value = parse(clinicalFirstPhaseReceiptSchema, raw),
        p = bindPrepared(value.prepared, user)
      if (
        value.user_id !== user ||
        value.preview_id !== preview ||
        value.operation_key !== key ||
        p.preview_id !== preview
      )
        throw clinicalFirstPhaseError('unavailable')
      bindResult(value.result, p)
      return immutable(value)
    },
    async confirm(user: string, prepared: ClinicalFirstPhasePrepared, key: string) {
      bindPrepared(prepared, user)
      const raw = await call('confirm_mobile_clinical_first_phase', {
        p_user_id: uuid.parse(user),
        p_preview_id: prepared.preview_id,
        p_operation_key: uuid.parse(key),
        p_selection: prepared.selection,
        p_proposal: prepared.package,
      })
      const value = parse(clinicalFirstPhaseConfirmedSchema, raw)
      if (
        value.user_id !== user ||
        value.preview_id !== prepared.preview_id ||
        value.operation_key !== key
      )
        throw clinicalFirstPhaseError('unavailable')
      bindResult(value.result, prepared)
      return immutable(value)
    },
  })
}
