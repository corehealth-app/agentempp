/** Private original-enrichment bridge. Trusted server policy may select it only
 * after a factual receipt; no header, route, domain writer or bootstrap lives here. */
import { isDeepStrictEqual } from 'node:util'
import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import type { RegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import type { RegistrationFeedbackV3 } from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import type { ConversationJournalBinding } from './conversation-command-candidate-contracts'
import {
  type ConversationCurrentScopeBinding,
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
  createConversationReadonlyAuth,
} from './conversation-current-scope'
import { projectSavedConversationMealCommandResult } from './conversation-meal-command-result'
import {
  detachConversationContinuationReadJson,
  parseConversationMealContinuationFeedbackBinding,
} from './conversation-meal-continuation-read-contracts'
import type { ConversationMealOriginalFeedbackInput } from './conversation-meal-feedback-service'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { conversationJournalUUID } from './conversation-meal-journal-store'
import type { ConversationMealReplyFeedbackInput } from './conversation-meal-reply-public-service'
import {
  type CapturedConversationWorkoutSource,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'
import { parseConversationWorkoutEffect } from './conversation-workout-writer'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  type FeedbackV3Identity,
  type FeedbackV3Observation,
  parseFeedbackV3Capture,
  pinFeedbackV3Identity,
} from './registration-feedback-v3-contracts'
import {
  ensureRegistrationFeedbackV3,
  readRegistrationFeedbackV3,
} from './registration-feedback-v3-service'
import type { FeedbackV3Scope } from './registration-feedback-v3-store'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

export type ConversationFeedbackV3Original =
  | RegistrationFeedback
  | RegistrationFeedbackV2
  | RegistrationFeedbackV3
export interface ConversationFeedbackV3RootInput extends ConversationMealOriginalFeedbackInput {
  /** Actual private server journal/preparation binding, never a request epoch. */
  readonly serverBinding: ConversationJournalBinding
}
export interface ConversationFeedbackV3WorkoutInput {
  readonly source: CapturedConversationWorkoutSource
  readonly prepared: unknown
  /** Full independently read/validated effect, not a rich mutation response. */
  readonly effect: unknown
}
export interface ConversationFeedbackV3OriginalBridge {
  ensureRoot(input: ConversationFeedbackV3RootInput): Promise<ConversationFeedbackV3Original | null>
  readRoot(input: ConversationFeedbackV3RootInput): Promise<ConversationFeedbackV3Original | null>
  ensureReply(
    input: ConversationMealReplyFeedbackInput,
  ): Promise<ConversationFeedbackV3Original | null>
  readReply(
    input: ConversationMealReplyFeedbackInput,
  ): Promise<ConversationFeedbackV3Original | null>
  ensureWorkout(
    input: ConversationFeedbackV3WorkoutInput,
  ): Promise<ConversationFeedbackV3Original | null>
  readWorkout(
    input: ConversationFeedbackV3WorkoutInput,
  ): Promise<ConversationFeedbackV3Original | null>
}
interface OriginalScope extends ConversationCurrentScopeBinding {
  readonly registrationId: string
  readonly origin: FeedbackV3Identity['origin']
  readonly kind: FeedbackV3Identity['kind']
  readonly commandId: string
  readonly inputHash: string
  readonly sourceHash: string | null
  readonly preparedHash: string | null
  readonly receiptVersion: string | number
  readonly parentCommandId: string | null
  readonly parentInputHash: string | null
  readonly parentDecisionHash: string | null
}
interface OriginalBinding {
  readonly identity: FeedbackV3Identity
  readonly scope: OriginalScope
  proveCapture(value: FeedbackV3Observation): void
  proveFeedback(value: ConversationFeedbackV3Original): void
}
function no(): never {
  throw new Error('Original canonical feedback unavailable')
}
function snapshot<T>(raw: T): T {
  return freezeInterpretation(detachConversationContinuationReadJson(raw) as T)
}
function same(a: unknown, b: unknown) {
  if (!isDeepStrictEqual(a, b)) no()
}
function mealFeedback(
  value: ConversationFeedbackV3Original,
  receipt: {
    readonly local_date: string
    readonly meal_type: string
    readonly log_ids: readonly string[]
  },
) {
  if (value.schema === 'registration.feedback.v1') {
    if (
      value.kind !== 'meal' ||
      (value.day !== null && value.day.local_date !== receipt.local_date)
    )
      no()
    return
  }
  if (
    value.local_date !== receipt.local_date ||
    value.registration.kind !== 'meal' ||
    value.registration.meal_kind !== receipt.meal_type
  )
    no()
  same([...value.registration.items.map((row) => row.log_id)].sort(), [...receipt.log_ids].sort())
}

/** Constructor is inert. The original Auth/epoch and dependency methods remain
 * fixed. Each operation pins its own actual event; scope revocation is sticky
 * across this request-local factory, including optional swallowed failures. */
export function createConversationFeedbackV3OriginalBridge(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  expectedEpoch: string,
  dependencies: ConversationCurrentScopeDependencies = {},
): ConversationFeedbackV3OriginalBridge {
  const auth = snapshot(originalAuth),
    owner = authenticatedReevaluationOwner(auth),
    epoch = conversationJournalUUID.parse(expectedEpoch)
  const rpc = db.rpc.bind(db),
    from = db.from.bind(db)
  const sdk = new Proxy(db, {
    get(target, key, receiver) {
      if (key === 'rpc') return rpc
      if (key === 'from') return from
      return Reflect.get(target, key, receiver)
    },
  })
  const a = dependencies.auth ?? createConversationReadonlyAuth(sdk),
    c = dependencies.clinical ?? createSupabaseCurrentClinicalStateSource(sdk)
  const scopeDependencies: ConversationCurrentScopeDependencies = Object.freeze({
    auth: Object.freeze({
      verifyAccessToken: a.verifyAccessToken.bind(a),
      loadPatient: a.loadPatient.bind(a),
      isAdmin: a.isAdmin.bind(a),
    }),
    clinical: Object.freeze({ capture: c.capture.bind(c) }),
  })
  let closed = false
  function inputAuth(value: MobileAuthContext) {
    same(value, auth)
    if (authenticatedReevaluationOwner(value) !== owner) no()
  }
  function event(
    registrationId: string,
    origin: FeedbackV3Identity['origin'],
    kind: FeedbackV3Identity['kind'],
    proof: Omit<
      OriginalScope,
      keyof ConversationCurrentScopeBinding | 'registrationId' | 'origin' | 'kind'
    >,
  ) {
    const identity = pinFeedbackV3Identity({ userId: owner, registrationId, origin, kind })
    const scope = snapshot({
      authUserId: auth.authUserId,
      ownerId: owner,
      epoch,
      registrationId,
      origin,
      kind,
      ...proof,
    })
    return { identity, scope }
  }
  function root(input: ConversationFeedbackV3RootInput): OriginalBinding {
    const raw = snapshot(input)
    inputAuth(raw.auth)
    // Reuse the existing complete factual proof codec. Its v1 projection is
    // only input validation here; no old presentation or payload is emitted.
    const saved = projectSavedConversationMealCommandResult({
      ...raw,
      expectedEpoch: epoch,
      feedback: null,
    })
    const receipt = saved.receipt
    return {
      ...event(receipt.registration_id, 'pending_registration', 'meal', {
        commandId: saved.command_id,
        inputHash: saved.input_hash,
        receiptVersion: receipt.effect_version,
        sourceHash: null,
        preparedHash: null,
        parentCommandId: null,
        parentInputHash: null,
        parentDecisionHash: null,
      }),
      proveCapture(value) {
        const s = value.context.source
        if (s.kind !== 'pending_registration' || s.command === null) no()
        same(s.command.receipt, receipt)
        same(s.command.command_id, saved.command_id)
        same(s.command.input_hash, saved.input_hash)
        same(s.command.epoch, epoch)
        same(s.command.continuation, null)
      },
      proveFeedback(value) {
        mealFeedback(value, receipt)
      },
    }
  }
  function reply(input: ConversationMealReplyFeedbackInput): OriginalBinding {
    const raw = snapshot(input)
    inputAuth(raw.auth)
    const b = parseConversationMealContinuationFeedbackBinding(raw.binding),
      p = b.parentBinding,
      child = b.childBinding,
      r = b.receipt
    if (
      p.owner_id !== owner ||
      child.owner_id !== owner ||
      p.epoch !== epoch ||
      child.epoch !== epoch
    )
      no()
    return {
      ...event(r.registration_id, 'pending_registration', 'meal', {
        commandId: child.command_id,
        inputHash: child.input_hash,
        receiptVersion: r.effect_version,
        sourceHash: null,
        preparedHash: null,
        parentCommandId: p.command_id,
        parentInputHash: p.input_hash,
        parentDecisionHash: b.parentDecisionHash,
      }),
      proveCapture(value) {
        const s = value.context.source
        if (s.kind !== 'pending_registration' || s.command === null) no()
        same(s.command.receipt, r)
        same(s.command.continuation, b)
        same(s.command.epoch, epoch)
        same(s.command.command_id, child.command_id)
        same(s.command.input_hash, child.input_hash)
      },
      proveFeedback(value) {
        mealFeedback(value, r)
      },
    }
  }
  function workout(input: ConversationFeedbackV3WorkoutInput): OriginalBinding {
    const raw = snapshot(input),
      old = raw.source
    const source = parseConversationWorkoutSource(old.command, {
      source_hash: old.sourceHash,
      context: old.context,
    })
    same(source, old)
    const effect = parseConversationWorkoutEffect(source, raw.prepared, raw.effect),
      r = effect.receipt
    if (source.command.ownerId !== owner || source.epoch !== epoch || r.epoch !== epoch) no()
    return {
      ...event(r.registration_id, 'conversation_workout', 'workout', {
        commandId: r.command_id,
        inputHash: r.input_hash,
        sourceHash: r.source_hash,
        preparedHash: r.prepared_hash,
        receiptVersion: r.effect_version,
        parentCommandId: null,
        parentInputHash: null,
        parentDecisionHash: null,
      }),
      proveCapture(value) {
        const s = value.context.source
        if (s.kind !== 'conversation_workout') no()
        same(s.input, source.command.command)
        same(s.captured, { source_hash: source.sourceHash, context: source.context })
        same(s.prepared, raw.prepared)
        same(s.effect, effect)
      },
      proveFeedback(value) {
        if (value.schema !== 'registration.feedback.v3' || value.local_date !== r.local_date) no()
        same(value.registration, { kind: 'workout', log_id: r.workout_id, ...r.activity })
      },
    }
  }
  async function run(
    bind: () => OriginalBinding,
    ensure: boolean,
  ): Promise<ConversationFeedbackV3Original | null> {
    try {
      if (closed) return null
      const b = bind(),
        current = createConversationCurrentScope(sdk, auth, b.scope, scopeDependencies)
      const scope: FeedbackV3Scope = {
        async checkCurrentScope(identity) {
          if (closed) return false
          const valid = await current.check({
            ...b.scope,
            ownerId: identity.owner_id,
            registrationId: identity.registration_id,
            origin: identity.origin,
            kind: identity.kind,
          })
          if (!valid) closed = true
          return valid && !closed
        },
      }
      const metadata = new Set([
        'read_mobile_registration_feedback_v3',
        'capture_mobile_registration_feedback_v3',
        'commit_mobile_registration_feedback_v3',
      ])
      const operation = new Proxy(sdk, {
        get(target, key, receiver) {
          if (key !== 'rpc') return Reflect.get(target, key, receiver)
          return async (...raw: unknown[]) => {
            const args = snapshot(raw),
              name = args[0],
              parameters = args[1]
            if (typeof name === 'string' && metadata.has(name)) {
              if (!parameters || typeof parameters !== 'object' || Array.isArray(parameters)) no()
              same(Reflect.get(parameters, 'p_user_id'), b.identity.userId)
              same(Reflect.get(parameters, 'p_registration_id'), b.identity.registrationId)
              same(Reflect.get(parameters, 'p_origin'), b.identity.origin)
            }
            const response = snapshot(await Reflect.apply(rpc, sdk, args))
            if (
              name === 'capture_mobile_registration_feedback_v3' &&
              response &&
              typeof response === 'object' &&
              !Array.isArray(response)
            ) {
              const data = Reflect.get(response, 'data'),
                error = Reflect.get(response, 'error')
              if (
                error === null &&
                data &&
                typeof data === 'object' &&
                !Array.isArray(data) &&
                Reflect.get(data, 'action') === 'available'
              )
                b.proveCapture(parseFeedbackV3Capture(Reflect.get(data, 'context'), b.identity))
            }
            return response
          }
        },
      })
      const value = ensure
        ? await ensureRegistrationFeedbackV3(operation, auth, b.identity, scope)
        : await readRegistrationFeedbackV3(operation, auth, b.identity, scope)
      if (value === null) return null
      b.proveFeedback(value)
      return snapshot(value)
    } catch {
      return null
    }
  }
  return Object.freeze({
    ensureRoot: (input: ConversationFeedbackV3RootInput) => run(() => root(input), true),
    readRoot: (input: ConversationFeedbackV3RootInput) => run(() => root(input), false),
    ensureReply: (input: ConversationMealReplyFeedbackInput) => run(() => reply(input), true),
    readReply: (input: ConversationMealReplyFeedbackInput) => run(() => reply(input), false),
    ensureWorkout: (input: ConversationFeedbackV3WorkoutInput) => run(() => workout(input), true),
    readWorkout: (input: ConversationFeedbackV3WorkoutInput) => run(() => workout(input), false),
  })
}
