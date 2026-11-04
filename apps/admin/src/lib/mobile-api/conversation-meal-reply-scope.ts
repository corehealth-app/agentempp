/** Actual existing-account Auth and profile-epoch observations only. A request
 * cannot renew a lease, bootstrap a patient or grant scope from historical IDs. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext, MobileAuthDependencies, MobilePatient } from './auth'
import {
  type ConversationMealContinuationReadIdentity,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationReadIdentity,
} from './conversation-meal-continuation-read-contracts'
import type { ConversationMealContinuationScope } from './conversation-meal-continuation-service'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import {
  conversationJournalInstant,
  conversationJournalUUID,
} from './conversation-meal-journal-store'
import {
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  readCurrentClinicalState,
} from './current-clinical-state'
import { extractBearerToken, MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileAuthDependencies } from './supabase-auth'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

export type ConversationMealReplyReadonlyAuth = Pick<
  MobileAuthDependencies,
  'verifyAccessToken' | 'loadPatient'
> & { isAdmin(authUserId: string): Promise<boolean> }
type ReadonlyAuth = ConversationMealReplyReadonlyAuth
export interface ConversationMealReplyScopeDependencies {
  readonly auth?: ReadonlyAuth
  readonly clinical?: CurrentClinicalStateSource
}
const identitySchema = z
  .object({
    id: conversationJournalUUID,
    email: z.string().nullable(),
    emailConfirmedAt: z.string().nullable(),
  })
  .strict()
const patientSchema = z
  .object({
    id: conversationJournalUUID,
    authUserId: conversationJournalUUID,
    email: z.string().nullable(),
    name: z.string().nullable(),
    locale: z.string().nullable(),
    timezone: z.string().nullable(),
    country: z.string().nullable(),
    countryConfirmed: z.boolean(),
    status: z.string(),
  })
  .strict()
/** Same ANY-admin membership exclusion as bootstrap_patient_profile, using
 * a read only; no patient bootstrap or role/provenance shortcut. */
export function createConversationMealReplyReadonlyAuth(db: ServiceClient): ReadonlyAuth {
  const auth = createMobileAuthDependencies(db),
    from = db.from.bind(db)
  return Object.freeze({
    verifyAccessToken: auth.verifyAccessToken.bind(auth),
    loadPatient: auth.loadPatient.bind(auth),
    async isAdmin(id: string) {
      const { data, error } = await from('admin_users').select('id').eq('id', id).maybeSingle()
      if (error) throw failure(503, 'patient_profile_unavailable')
      return data !== null
    },
  })
}
async function nonAdmin(auth: ReadonlyAuth, user: string) {
  const value = await auth.isAdmin(user)
  if (value === true) throw failure(403, 'patient_admin_account_conflict')
  if (value !== false) throw failure(503, 'patient_profile_unavailable')
}
function failure(status: number, code: string): MobileApiError {
  return new MobileApiError(status, code, 'The original authenticated patient scope is unavailable')
}
function snapshot<T>(raw: T): T {
  return freezeInterpretation(detachConversationContinuationReadJson(raw) as T)
}
async function verified(auth: ReadonlyAuth, token: string) {
  let raw: unknown
  try {
    raw = await auth.verifyAccessToken(token)
  } catch {
    throw failure(401, 'invalid_access_token')
  }
  if (raw === null) throw failure(401, 'invalid_access_token')
  const identity = identitySchema.parse(snapshot(raw))
  if (!identity.email || !identity.emailConfirmedAt) throw failure(403, 'email_not_confirmed')
  return identity
}
async function patient(auth: ReadonlyAuth, user: string): Promise<MobilePatient> {
  let raw: unknown
  try {
    raw = await auth.loadPatient(user)
  } catch {
    throw failure(503, 'patient_profile_unavailable')
  }
  if (raw === null) throw failure(403, 'patient_profile_unavailable')
  const value = patientSchema.parse(snapshot(raw))
  if (value.authUserId !== user) throw failure(409, 'conversation_patient_changed')
  if (value.status !== 'active') throw failure(403, 'patient_account_inactive')
  return value
}
export async function authenticateConversationReplyPatient(
  request: Request,
  dependencies: ReadonlyAuth,
): Promise<MobileAuthContext> {
  const token = extractBearerToken(request.headers)
  if (!token) throw failure(401, 'missing_access_token')
  const ports = Object.freeze({
      verifyAccessToken: dependencies.verifyAccessToken.bind(dependencies),
      loadPatient: dependencies.loadPatient.bind(dependencies),
      isAdmin: dependencies.isAdmin.bind(dependencies),
    }),
    identity = await verified(ports, token)
  await nonAdmin(ports, identity.id)
  const owner = await patient(ports, identity.id)
  return snapshot({
    accessToken: token,
    authUserId: identity.id,
    userId: owner.id,
    identity,
    patient: owner,
  })
}
export function createConversationMealReplyScope(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  rawIdentity: ConversationMealContinuationReadIdentity,
  dependencies: ConversationMealReplyScopeDependencies = {},
) {
  const auth = snapshot(originalAuth),
    owner = authenticatedReevaluationOwner(auth),
    identity = parseConversationMealContinuationReadIdentity(rawIdentity)
  if (owner !== identity.ownerId || !identity.replyId || !identity.replyInputHash)
    throw failure(409, 'conversation_patient_changed')
  const a = dependencies.auth ?? createConversationMealReplyReadonlyAuth(db),
    ports = Object.freeze({
      verifyAccessToken: a.verifyAccessToken.bind(a),
      loadPatient: a.loadPatient.bind(a),
      isAdmin: a.isAdmin.bind(a),
    }),
    c = dependencies.clinical ?? createSupabaseCurrentClinicalStateSource(db),
    capture = c.capture.bind(c),
    clinical = Object.freeze({
      async capture(request: Parameters<typeof capture>[0]) {
        return snapshot(await capture(request))
      },
    }),
    expectedScope = Object.freeze({
      authUserId: auth.authUserId,
      ownerId: owner,
      epoch: identity.epoch,
      parentCommandId: identity.parentCommandId,
      replyId: identity.replyId,
    })
  let closed: MobileApiError | null = null,
    previous: bigint | null = null
  const checkMapping = async () => {
    const current = await verified(ports, auth.accessToken)
    if (current.id !== auth.authUserId || current.id !== auth.identity.id)
      throw failure(409, 'conversation_patient_changed')
    await nonAdmin(ports, current.id)
    const p = await patient(ports, current.id)
    if (p.id !== owner || p.authUserId !== auth.authUserId)
      throw failure(409, 'conversation_patient_changed')
  }
  async function observeNow(scope?: ConversationMealContinuationScope) {
    if (closed) throw closed
    try {
      if (scope !== undefined && !isDeepStrictEqual(snapshot(scope), expectedScope))
        throw failure(409, 'conversation_scope_changed')
      await checkMapping()
      const state = readCurrentClinicalState(
        await captureCurrentClinicalState(clinical, {
          userId: owner,
          mode: 'profile',
          expectedEpoch: identity.epoch,
        }),
        owner,
      )
      if (state.epoch !== identity.epoch) throw failure(409, 'conversation_epoch_changed')
      const at = conversationJournalInstant(state.observed_at)
      if (previous !== null && at < previous) throw failure(409, 'conversation_scope_changed')
      await checkMapping()
      previous = at
      return state
    } catch (error) {
      closed =
        error instanceof MobileApiError ? error : failure(503, 'conversation_scope_unavailable')
      throw closed
    }
  }
  let lane: Promise<void> = Promise.resolve()
  function observe(scope?: ConversationMealContinuationScope) {
    let wanted: ConversationMealContinuationScope | undefined
    try {
      wanted = scope === undefined ? undefined : snapshot(scope)
    } catch {
      closed = failure(503, 'conversation_scope_unavailable')
      return Promise.reject(closed)
    }
    const work = lane.then(() => observeNow(wanted))
    lane = work.then(
      () => undefined,
      () => undefined,
    )
    return work
  }
  return Object.freeze({
    observe,
    async check(scope?: ConversationMealContinuationScope) {
      try {
        await observe(scope)
        return true
      } catch {
        return false
      }
    },
  })
}
export type ConversationMealReplyScope = ReturnType<typeof createConversationMealReplyScope>
