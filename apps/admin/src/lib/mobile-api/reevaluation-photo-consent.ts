import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  reevaluationPhotoRevisionSchema as revision,
  reevaluationPhotoTimestampSchema as timestamp,
} from './reevaluation-photo-upload'

const hash = z.string().regex(/^[0-9a-f]{64}$/)
const key = z.literal('body_photo_reevaluation_consent')
const version = z.string().regex(/^[A-Za-z0-9._-]{1,64}$/)
const locale = z.enum(['pt-BR', 'en-US'])
export const reevaluationPhotoConsentAcceptInput = z
  .object({
    expectedRevision: revision,
    document: z.object({ id: uuid, documentKey: key, version, locale, bodyHash: hash }).strict(),
  })
  .strict()
const document = z
  .object({
    id: uuid,
    document_key: key,
    version,
    locale,
    body: z.string().min(1).max(16384),
    body_hash: hash,
    required_from: timestamp,
    idle_timeout_seconds: z.literal(86400),
  })
  .strict()
  .refine(
    (value) => createHash('sha256').update(value.body, 'utf8').digest('hex') === value.body_hash,
  )
const acceptance = z
  .object({
    acceptance_id: uuid,
    document_id: uuid,
    document_key: key,
    version,
    locale,
    body_hash: hash,
    accepted_at: timestamp,
    idle_expires_at: timestamp,
  })
  .strict()
  .refine((value) => value.idle_expires_at > value.accepted_at)
const wire = z
  .object({
    version: z.literal(1),
    cycle_revision: revision,
    availability: z.enum(['available', 'unavailable']),
    unavailable_reason: z
      .enum(['policy_unavailable', 'consent_required', 'consent_changed', 'consent_expired'])
      .nullable(),
    document: document.nullable(),
    acceptance: acceptance.nullable(),
  })
  .strict()
  .superRefine((value, context) => {
    const available = value.availability === 'available'
    if (
      available !== (value.unavailable_reason === null) ||
      available !== (value.acceptance !== null) ||
      (value.document === null) !== (value.unavailable_reason === 'policy_unavailable')
    ) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'Inconsistent consent state' })
      return
    }
    if (value.acceptance && value.document) {
      const a = value.acceptance,
        d = value.document
      if (
        a.document_id !== d.id ||
        a.document_key !== d.document_key ||
        a.version !== d.version ||
        a.locale !== d.locale ||
        a.body_hash !== d.body_hash
      )
        context.addIssue({ code: z.ZodIssueCode.custom, message: 'Inconsistent consent identity' })
    }
  })
export type ReevaluationPhotoConsentState = z.infer<typeof wire> & { cycle_id: string }
export function photoConsentError(
  kind: 'input' | 'changed' | 'busy' | 'unavailable' = 'unavailable',
) {
  return new MobileApiError(
    kind === 'input' ? 422 : kind === 'changed' || kind === 'busy' ? 409 : 503,
    `mobile_reevaluation_photo_consent_${kind}`,
    'Reassessment photo consent is unavailable',
  )
}
export function parseReevaluationPhotoConsentState(
  value: unknown,
  cycleId: string,
): ReevaluationPhotoConsentState {
  const parsed = wire.safeParse(value)
  if (!uuid.safeParse(cycleId).success || !parsed.success) throw photoConsentError()
  return { ...parsed.data, cycle_id: cycleId.toLowerCase() }
}
/** Original current-document checks remain in SQL BEFORE key replay. No outer
 * response cache, client clock, signup authority or acceptance inferred by GET. */
export function createReevaluationPhotoConsentService(client: ServiceClient) {
  const rpc = client.rpc.bind(client) as unknown as (
    name: string,
    args: Record<string, unknown>,
  ) => PromiseLike<unknown>
  function scope(auth: MobileAuthContext, input: unknown) {
    const owner = authenticatedReevaluationOwner(structuredClone(auth)).toLowerCase(),
      cycle = uuid.safeParse(input)
    if (!cycle.success) throw photoConsentError('input')
    return { owner, cycle: cycle.data.toLowerCase() }
  }
  async function invoke(name: string, args: Record<string, unknown>, cycle: string) {
    let raw: unknown
    try {
      raw = await rpc(name, args)
    } catch {
      throw photoConsentError()
    }
    if (
      !raw ||
      typeof raw !== 'object' ||
      Array.isArray(raw) ||
      !Object.hasOwn(raw, 'data') ||
      !Object.hasOwn(raw, 'error')
    )
      throw photoConsentError()
    const envelope = raw as { data: unknown; error: unknown }
    if (envelope.error !== null) {
      const code =
        envelope.error && typeof envelope.error === 'object' && 'code' in envelope.error
          ? envelope.error.code
          : null
      throw photoConsentError(
        code === '40001'
          ? 'changed'
          : code === '55P03'
            ? 'busy'
            : code === '22023'
              ? 'input'
              : 'unavailable',
      )
    }
    return parseReevaluationPhotoConsentState(envelope.data, cycle)
  }
  return Object.freeze({
    async read(auth: MobileAuthContext, cycleId: unknown) {
      const s = scope(auth, cycleId)
      return invoke(
        'get_mobile_reevaluation_photo_consent',
        { p_user_id: s.owner, p_cycle_id: s.cycle },
        s.cycle,
      )
    },
    async accept(auth: MobileAuthContext, cycleId: unknown, operationKey: unknown, raw: unknown) {
      const s = scope(auth, cycleId),
        parsed = reevaluationPhotoConsentAcceptInput.safeParse(raw),
        operation = uuid.safeParse(operationKey)
      if (!parsed.success || !operation.success) throw photoConsentError('input')
      const input = parsed.data,
        d = input.document
      const state = await invoke(
        'accept_mobile_reevaluation_photo_consent',
        {
          p_user_id: s.owner,
          p_cycle_id: s.cycle,
          p_expected_revision: input.expectedRevision,
          p_document_id: d.id.toLowerCase(),
          p_document_key: d.documentKey,
          p_version: d.version,
          p_locale: d.locale,
          p_body_hash: d.bodyHash,
          p_idempotency_key: operation.data.toLowerCase(),
        },
        s.cycle,
      )
      if (
        state.availability !== 'available' ||
        !state.document ||
        BigInt(state.cycle_revision) < BigInt(input.expectedRevision) ||
        state.document.id !== d.id.toLowerCase() ||
        state.document.document_key !== d.documentKey ||
        state.document.version !== d.version ||
        state.document.locale !== d.locale ||
        state.document.body_hash !== d.bodyHash
      )
        throw photoConsentError()
      return state
    },
  })
}
