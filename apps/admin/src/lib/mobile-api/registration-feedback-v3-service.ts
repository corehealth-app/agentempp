/** Optional metadata after an already durable domain effect. Receipt read wins
 * before source/current day/education. No registration or reward writer lives here. */
import { prepareRegistrationFeedbackV3 } from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { loadFeedbackV3ClinicalContext } from './registration-feedback-v3-clinical'
import {
  type CanonicalRegistrationFeedback,
  type FeedbackV3Identity,
  feedbackV3Json,
  freezeFeedbackV3,
  pinFeedbackV3Identity,
} from './registration-feedback-v3-contracts'
import {
  createRegistrationFeedbackV3Store,
  type FeedbackV3RPCPort,
  type FeedbackV3Scope,
} from './registration-feedback-v3-store'

const rpcBase = z
  .object({
    p_user_id: z.string().uuid(),
    p_registration_id: z.string().uuid(),
    p_origin: z.enum(['pending_registration', 'conversation_workout']),
  })
  .strict()
const rpcCommit = rpcBase
  .extend({ p_expected_context: feedbackV3Json, p_feedback: feedbackV3Json })
  .strict()
function sdkPort(db: ServiceClient): FeedbackV3RPCPort {
  return {
    rpc(name, raw) {
      if (name === 'commit_mobile_registration_feedback_v3')
        return db.rpc(name, rpcCommit.parse(raw))
      const args = rpcBase.parse(raw)
      return name === 'capture_mobile_registration_feedback_v3'
        ? db.rpc(name, args)
        : db.rpc('read_mobile_registration_feedback_v3', args)
    },
  }
}
/** Clinical enrichment is read-only, including swallowed failures. Every actual
 * SDK dispatch shares the receipt store's sticky scope latch. Builder creation
 * is inert; its thenable dispatch is guarded only when awaited. */
function clinicalReadClient(
  db: ServiceClient,
  observe: <T>(read: () => PromiseLike<T>) => Promise<T>,
): ServiceClient {
  const rpc = db.rpc.bind(db)
  const from = typeof db.from === 'function' ? db.from.bind(db) : null
  const rpcs = new Set([
    'get_mobile_current_clinical_state',
    'get_mobile_clinical_daily_context',
    'list_mobile_routine_items',
  ])
  const tables = new Set([
    'user_profiles',
    'daily_snapshots',
    'user_progress',
    'pending_registrations',
    'notification_preferences',
    'meal_logs',
    'product_events',
    'global_config',
  ])
  const methods = new Set([
    'select',
    'eq',
    'neq',
    'gt',
    'gte',
    'lt',
    'lte',
    'in',
    'is',
    'not',
    'filter',
    'order',
    'limit',
    'range',
    'maybeSingle',
    'single',
    'throwOnError',
  ])
  const no = (): never => {
    throw new Error('Optional clinical read unavailable')
  }
  function query(raw: unknown): unknown {
    if (!raw || typeof raw !== 'object') return no()
    return new Proxy(raw, {
      get(target, key) {
        if (key === 'then')
          return (resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) =>
            observe(() => Promise.resolve(target)).then(resolve, reject)
        if (typeof key !== 'string' || !methods.has(key)) return no()
        const method = Reflect.get(target, key, target)
        if (typeof method !== 'function') return no()
        return (...args: unknown[]) => query(Reflect.apply(method, target, structuredClone(args)))
      },
    })
  }
  return new Proxy(db, {
    get(_target, key) {
      if (key === 'rpc')
        return (...raw: unknown[]) => {
          const args = structuredClone(raw)
          if (typeof args[0] !== 'string' || !rpcs.has(args[0])) return no()
          return observe(() => Reflect.apply(rpc, db, args))
        }
      if (key === 'from')
        return (table: unknown) => {
          if (typeof table !== 'string' || !tables.has(table) || !from) return no()
          return query(Reflect.apply(from, db, [table]))
        }
      return no()
    },
  })
}
function bind(auth: MobileAuthContext, raw: FeedbackV3Identity) {
  const who = freezeFeedbackV3(structuredClone(auth)),
    identity = pinFeedbackV3Identity(raw)
  if (authenticatedReevaluationOwner(who) !== identity.userId)
    throw new Error('Feedback owner changed')
  return { who, identity }
}
export interface FeedbackV3ServiceDependencies {
  loadClinical?: typeof loadFeedbackV3ClinicalContext
}
/** Historical original only. Future public timeline must apply its current
 * presentation/clinical surface separately, never rewriting the old receipt. */
export async function readRegistrationFeedbackV3(
  db: ServiceClient,
  auth: MobileAuthContext,
  rawIdentity: FeedbackV3Identity,
  scope: FeedbackV3Scope,
): Promise<CanonicalRegistrationFeedback | null> {
  try {
    const { identity } = bind(auth, rawIdentity)
    const result = await createRegistrationFeedbackV3Store(
      sdkPort(db),
      scope,
      identity,
    ).readReceipt()
    return result.action === 'available' ? result.feedback : null
  } catch {
    return null
  }
}
export async function ensureRegistrationFeedbackV3(
  db: ServiceClient,
  auth: MobileAuthContext,
  rawIdentity: FeedbackV3Identity,
  scope: FeedbackV3Scope,
  dependencies: FeedbackV3ServiceDependencies = {},
): Promise<CanonicalRegistrationFeedback | null> {
  try {
    const { who, identity } = bind(auth, rawIdentity),
      loadClinical = dependencies.loadClinical ?? loadFeedbackV3ClinicalContext
    const store = createRegistrationFeedbackV3Store(sdkPort(db), scope, identity)
    const prior = await store.readReceipt()
    if (prior.action === 'available') return prior.feedback
    if (prior.action !== 'absent') return null
    const captured = await store.capture()
    if (captured.action !== 'available') return null
    const observation = captured.observation
    const clinicalDb = clinicalReadClient(db, store.withCurrentScope)
    const clinical = await store.withCurrentScope(() => loadClinical(clinicalDb, who, observation))
    const feedback = prepareRegistrationFeedbackV3({
      registrationId: identity.registrationId,
      localDate: observation.localDate,
      locale: who.patient.locale,
      registration: observation.registration,
      policy: clinical.policy,
      officialDay: clinical.officialDay,
      preferencesKnown: false,
    })
    try {
      const result = await store.commit(observation, feedback)
      if (result.action === 'source_conflict' || result.action === 'event_conflict') return null
    } catch {
      if (store.scopeClosed()) return null
      // Unknown outcome gets one durable read, never another commit, source
      // capture, domain effect, phrase selection or education preparation.
    }
    const saved = await store.readReceipt()
    return saved.action === 'available' ? saved.feedback : null
  } catch {
    // Enrichment failure never changes the domain acknowledgement or leaks
    // provider/private clinical detail. Nothing here retries that registration.
    return null
  }
}
