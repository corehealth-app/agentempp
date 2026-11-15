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
/** Journal-only serial, sticky clinical observations. Mapping checks remain
 * fresh before and after each observation; this lane grants no write capability,
 * bootstrap, token renewal or authority derived from historical rows. */
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
  async function observeNow(scope?: Scope) {
    if (closed) throw closed
    try {
      if (scope !== undefined && !isDeepStrictEqual(snapshot(scope), expectedScope))
        throw failure(409, 'conversation_scope_changed')
      await checkMapping()
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
      previous = at
      return state
    } catch (error) {
      closed =
        error instanceof MobileApiError ? error : failure(503, 'conversation_scope_unavailable')
      throw closed
    }
  }
  let lane: Promise<void> = Promise.resolve()
  function observe(scope?: Scope) {
    let wanted: Scope | undefined
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
