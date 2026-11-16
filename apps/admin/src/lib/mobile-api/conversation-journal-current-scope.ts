/** Journal-only observation lane. Protected command/training readers retain
 * their byte-exact shared scope. Fresh mapping reads overlap only after Auth. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext, MobilePatient } from './auth'
import {
  assertConversationReadonlyNonAdmin,
  type ConversationCurrentScopeBinding,
  type ConversationCurrentScopeDependencies,
  type ConversationReadonlyAuth,
  createConversationReadonlyAuth,
  parseConversationReadonlyIdentity,
  parseConversationReadonlyPatient,
} from './conversation-current-scope'
import { detachConversationContinuationReadJson } from './conversation-meal-continuation-read-contracts'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import {
  conversationJournalInstant,
  conversationJournalUUID,
} from './conversation-meal-journal-store'
import { captureCurrentClinicalState, readCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

function snapshot<T>(raw: T): T {
  return freezeInterpretation(detachConversationContinuationReadJson(raw) as T)
}
function failure(status: number, code: string): MobileApiError {
  return new MobileApiError(status, code, 'The original authenticated patient scope is unavailable')
}
async function verified(auth: ConversationReadonlyAuth, token: string) {
  let raw: unknown
  try {
    raw = await auth.verifyAccessToken(token)
  } catch {
    throw failure(401, 'invalid_access_token')
  }
  return parseConversationReadonlyIdentity(raw)
}
async function nonAdmin(auth: ConversationReadonlyAuth, user: string) {
  assertConversationReadonlyNonAdmin(await auth.isAdmin(user))
}
async function patient(auth: ConversationReadonlyAuth, user: string): Promise<MobilePatient> {
  let raw: unknown
  try {
    raw = await auth.loadPatient(user)
  } catch {
    throw failure(503, 'patient_profile_unavailable')
  }
  return parseConversationReadonlyPatient(raw, user)
}
/** Journal-only serial, sticky clinical observations. Concurrent callers may
 * share a snapshot only when all were admitted before its capture begins.
 * Fresh pre/post Auth mapping remains required; completed snapshots are never
 * reused. This lane grants no write, bootstrap or token-renewal capability. */
export function createConversationJournalCurrentScope<
  Scope extends ConversationCurrentScopeBinding,
>(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  rawScope: Scope,
  dependencies: ConversationCurrentScopeDependencies = {},
) {
  const auth = snapshot(originalAuth),
    owner = authenticatedReevaluationOwner(auth),
    expectedScope = snapshot(rawScope)
  if (owner !== expectedScope.ownerId || auth.authUserId !== expectedScope.authUserId)
    throw failure(409, 'conversation_patient_changed')
  conversationJournalUUID.parse(expectedScope.epoch)
  const a = dependencies.auth ?? createConversationReadonlyAuth(db),
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
    })
  let closed: MobileApiError | null = null,
    previous: bigint | null = null
  const checkMapping = async () => {
    const current = await verified(ports, auth.accessToken)
    if (current.id !== auth.authUserId || current.id !== auth.identity.id)
      throw failure(409, 'conversation_patient_changed')
    const checks = await Promise.all([nonAdmin(ports, current.id), patient(ports, current.id)]),
      p = checks[1]
    if (p.id !== owner || p.authUserId !== auth.authUserId)
      throw failure(409, 'conversation_patient_changed')
  }
  async function observeNow(scope: Scope | undefined, sealAdmission: () => void) {
    if (closed) throw closed
    try {
      if (scope !== undefined && !isDeepStrictEqual(snapshot(scope), expectedScope))
        throw failure(409, 'conversation_scope_changed')
      await checkMapping()
      if (closed) throw closed
      // A caller arriving after this boundary needs a subsequent snapshot;
      // an in-flight capture may already have observed an earlier DB state.
      sealAdmission()
      const state = readCurrentClinicalState(
        await captureCurrentClinicalState(clinical, {
          userId: owner,
          mode: 'profile',
          expectedEpoch: expectedScope.epoch,
        }),
        owner,
      )
      if (state.epoch !== expectedScope.epoch) throw failure(409, 'conversation_epoch_changed')
      const at = conversationJournalInstant(state.observed_at)
      if (previous !== null && at < previous) throw failure(409, 'conversation_scope_changed')
      await checkMapping()
      if (closed) throw closed
      previous = at
      return state
    } catch (error) {
      closed =
        error instanceof MobileApiError ? error : failure(503, 'conversation_scope_unavailable')
      throw closed
    } finally {
      sealAdmission()
    }
  }
  let lane: Promise<void> = Promise.resolve()
  let pending: {
    admission: { open: boolean }
    work: Promise<Awaited<ReturnType<typeof observeNow>>>
  } | null = null
  function observe(scope?: Scope) {
    if (closed) return Promise.reject(closed)
    let wanted: Scope | undefined
    try {
      wanted = scope === undefined ? undefined : snapshot(scope)
      if (wanted !== undefined && !isDeepStrictEqual(wanted, expectedScope))
        throw failure(409, 'conversation_scope_changed')
    } catch (error) {
      closed =
        error instanceof MobileApiError ? error : failure(503, 'conversation_scope_unavailable')
      return Promise.reject(closed)
    }
    if (pending?.admission.open) return pending.work
    const admission = { open: true }
    const work = lane.then(() =>
      observeNow(wanted, () => {
        admission.open = false
      }),
    )
    pending = { admission, work }
    const clear = () => {
      if (pending?.work === work) pending = null
    }
    lane = work.then(clear, clear)
    return work
  }
  return Object.freeze({
    observe,
    async check(scope?: Scope) {
      try {
        await observe(scope)
        return true
      } catch {
        return false
      }
    },
  })
}
