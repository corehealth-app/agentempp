/** Private neutral orchestration. Only the durable SQL selection chooses the
 * genuine typed service; routing output, a selection or a read is not an ACK.
 * No HTTP route, provider default, media projection or capability is installed. */
import { isDeepStrictEqual } from 'node:util'
import type { ConversationFeedbackPresentationNegotiation } from './conversation-feedback-presentation-negotiation'
import {
  type BoundConversationIntake,
  bindConversationIntake,
  type CapturedConversationIntakeSource,
  type ConversationIntakeSelection,
  parseConversationIntakeRoutingDecision,
  parseConversationIntakeSelection,
  parseConversationIntakeSource,
  pinConversationIntake,
} from './conversation-intake-contracts'
import {
  ConversationIntakeScopeRefusal,
  type createConversationIntakeStore,
} from './conversation-intake-store'
import type { createConversationMealCommandService } from './conversation-meal-command-service'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import type { createConversationWorkoutCommandService } from './conversation-workout-command-service'
import { workoutHash, workoutSnapshot, workoutUUID } from './conversation-workout-contracts'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { type CurrentClinicalSnapshot, readCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'

type Store = ReturnType<typeof createConversationIntakeStore>
type Binding = ConversationIntakeSelection['intake']
type Child = NonNullable<ConversationIntakeSelection['command']>
type MealService = ReturnType<typeof createConversationMealCommandService>
type WorkoutService = ReturnType<typeof createConversationWorkoutCommandService>
type TypedReply =
  | Awaited<ReturnType<MealService['submit']>>
  | Awaited<ReturnType<WorkoutService['submit']>>
export interface ConversationIntakeLookup {
  readonly ownerId: string
  readonly intakeId: string
  readonly inputHash: string
  readonly epoch: string
}
export interface ConversationIntakeDriverPorts {
  readonly store: Store
  readonly scope: {
    /** Real current Auth/admin/mapping/epoch observation; never historical data. */
    observeCurrentScope(identity: ConversationIntakeLookup): Promise<CurrentClinicalSnapshot>
  }
  readonly createRouter: () => {
    /** Factory construction is synchronous and side-effect free. Provider work
     * starts only in route, after the durable claim has been acquired. */
    route(source: CapturedConversationIntakeSource): Promise<unknown>
  }
  /** These ports MUST be bound to the existing typed services. Neither models,
   * arbitrary RPC payloads nor request JSON can supply a factual result here. */
  readonly domains: Readonly<
    Record<
      'meal' | 'workout',
      {
        submit(
          child: Child,
          negotiation: ConversationFeedbackPresentationNegotiation,
        ): Promise<TypedReply>
        read(
          child: Child,
          negotiation: ConversationFeedbackPresentationNegotiation,
        ): Promise<TypedReply>
      }
    >
  >
}
function failure(code: string, status = 409): MobileApiError {
  return new MobileApiError(status, code, 'The original neutral intake is unavailable')
}
function lookup(raw: ConversationIntakeLookup): ConversationIntakeLookup {
  const v = workoutSnapshot(raw)
  if (Object.keys(v).sort().join(',') !== 'epoch,inputHash,intakeId,ownerId')
    throw failure('conversation_intake_changed')
  workoutUUID.parse(v.ownerId)
  workoutUUID.parse(v.intakeId)
  workoutHash.parse(v.inputHash)
  workoutUUID.parse(v.epoch)
  return v
}
function sameBinding(b: Binding, id: ConversationIntakeLookup) {
  if (
    b.owner_id !== id.ownerId ||
    b.intake_id !== id.intakeId ||
    b.input_hash !== id.inputHash ||
    b.epoch !== id.epoch
  )
    throw failure('conversation_intake_changed')
  conversationJournalInstant(b.admitted_at)
}
function currentFeedback(reply: TypedReply, now: CurrentClinicalSnapshot): TypedReply {
  if (reply.status !== 'saved' || !reply.feedback) return reply
  try {
    const shown = reply.feedback,
      { observed_at: _a, ...actual } = projectCurrentClinicalPublicPolicy(now),
      { observed_at: _b, ...policy } = shown.current_policy,
      at = conversationJournalInstant(shown.provenance.observed_at),
      effectAt =
        reply.schema === 'conversation.meal-command-result.v1'
          ? reply.receipt.consumed_at
          : reply.registration.committed_at
    if (
      isDeepStrictEqual(actual, policy) &&
      shown.current_policy.observed_at === shown.provenance.observed_at &&
      at >= conversationJournalInstant(effectAt) &&
      at <= conversationJournalInstant(now.observed_at)
    )
      return reply
  } catch {
    /* Optional presentation cannot invalidate or repeat the factual effect. */
  }
  return workoutSnapshot({ ...reply, feedback: null })
}
function childReply(raw: TypedReply, child: Child, now: CurrentClinicalSnapshot): TypedReply {
  const value = workoutSnapshot(raw)
  const allowed =
    child.kind === 'meal.report'
      ? ['conversation.meal-command-result.v1', 'conversation.meal-command-state.v1']
      : ['conversation.workout-command-result.v1', 'conversation.workout-command-state.v1']
  if (
    !allowed.includes(value.schema) ||
    value.owner_id !== child.owner_id ||
    value.command_id !== child.command_id ||
    value.input_hash !== child.input_hash ||
    value.epoch !== child.epoch
  )
    throw failure('conversation_intake_child_changed')
  if (value.status === 'saved') {
    if (value.schema === 'conversation.meal-command-result.v1') {
      if (
        child.kind !== 'meal.report' ||
        value.receipt.owner_id !== child.owner_id ||
        value.receipt.command_id !== child.command_id ||
        value.receipt.input_hash !== child.input_hash ||
        conversationJournalInstant(value.admitted_at) !==
          conversationJournalInstant(child.admitted_at)
      )
        throw failure('conversation_intake_child_changed')
    } else if (
      child.kind !== 'workout.report' ||
      value.registration.registration_id !== child.command_id ||
      conversationJournalInstant(value.registration.performed_at) !==
        conversationJournalInstant(child.admitted_at)
    )
      throw failure('conversation_intake_child_changed')
  }
  return currentFeedback(value, now)
}
export function createConversationIntakeDriver(ports: ConversationIntakeDriverPorts) {
  const store = Object.freeze({
      read: ports.store.read.bind(ports.store),
      admit: ports.store.admit.bind(ports.store),
      capture: ports.store.capture.bind(ports.store),
      claim: ports.store.claim.bind(ports.store),
      seal: ports.store.seal.bind(ports.store),
    }),
    observe = ports.scope.observeCurrentScope.bind(ports.scope),
    makeRouter = ports.createRouter.bind(ports),
    domains = Object.freeze({
      meal: Object.freeze({
        submit: ports.domains.meal.submit.bind(ports.domains.meal),
        read: ports.domains.meal.read.bind(ports.domains.meal),
      }),
      workout: Object.freeze({
        submit: ports.domains.workout.submit.bind(ports.domains.workout),
        read: ports.domains.workout.read.bind(ports.domains.workout),
      }),
    })
  function operation(
    original: ConversationIntakeLookup,
    negotiation: ConversationFeedbackPresentationNegotiation,
  ) {
    const id = lookup(original)
    let closed: MobileApiError | null = null,
      previous: bigint | null = null,
      latest: CurrentClinicalSnapshot | null = null
    async function current() {
      if (closed) throw closed
      try {
        const v = readCurrentClinicalState(workoutSnapshot(await observe(id)), id.ownerId),
          at = conversationJournalInstant(v.observed_at)
        if (v.epoch !== id.epoch || (previous !== null && at < previous))
          throw failure('conversation_intake_scope_changed')
        previous = at
        latest = v
        return v
      } catch (error) {
        closed =
          error instanceof MobileApiError ? error : failure('conversation_intake_scope_changed')
        throw closed
      }
    }
    async function call<T>(fn: () => PromiseLike<T>): Promise<T> {
      await current()
      try {
        // Detach the SDK/service result BEFORE another asynchronous observation.
        const value = workoutSnapshot(await fn())
        await current()
        return value
      } catch (error) {
        await current()
        throw error
      }
    }
    function pending(
      reason: string,
      intake: Binding | null = null,
      status: 'pending' | 'held' = 'pending',
    ) {
      return workoutSnapshot({
        schema: 'conversation.intake-result.v1' as const,
        status,
        lookup: id,
        intake,
        reason,
      })
    }
    function ownedRead(value: Awaited<ReturnType<Store['read']>>) {
      if (value.action === 'stale_epoch' || value.action === 'input_conflict')
        throw failure('conversation_intake_changed')
      if (value.action !== 'available') return null
      sameBinding(value.intake, id)
      const c = bindConversationIntake(id.ownerId, `cintake1:${id.intakeId}`, value.source_input)
      if (c.intakeId !== id.intakeId || c.inputHash !== id.inputHash)
        throw failure('conversation_intake_changed')
      if (value.source_hash !== null) workoutHash.parse(value.source_hash)
      if ((value.claimed && value.source_hash === null) || (value.selection && !value.claimed))
        throw failure('conversation_intake_changed')
      const selected =
        value.selection === null
          ? null
          : parseConversationIntakeSelection(c, value.intake, value.selection)
      if (selected && selected.source_hash !== value.source_hash)
        throw failure('conversation_intake_changed')
      return { ...value, command: c, selection: selected }
    }
    async function selected(selection: ConversationIntakeSelection, method: 'submit' | 'read') {
      sameBinding(selection.intake, id)
      const d = selection.decision,
        c = selection.command
      if (d.kind === 'not_reported' || d.kind === 'clarification_required') {
        if (c !== null) throw failure('conversation_intake_changed')
        return workoutSnapshot({
          schema: 'conversation.intake-result.v1' as const,
          status:
            d.kind === 'not_reported'
              ? ('not_recorded' as const)
              : ('clarification_required' as const),
          intake: selection.intake,
          source_hash: selection.source_hash,
          decision_hash: selection.decision_hash,
          reason: d.reason,
          ...('question' in d ? { question: d.question } : {}),
        })
      }
      if (!c || c.kind !== d.kind) throw failure('conversation_intake_changed')
      const domain = c.kind === 'meal.report' ? domains.meal : domains.workout
      const raw = await call(() => domain[method](c, negotiation))
      if (!latest) throw failure('conversation_intake_scope_changed')
      const result = childReply(raw, c, latest),
        { input: _private, ...child } = c
      return workoutSnapshot({
        schema: 'conversation.intake-result.v1' as const,
        status: 'selected' as const,
        intake: selection.intake,
        selection: {
          kind: c.kind,
          source_hash: selection.source_hash,
          decision_hash: selection.decision_hash,
          selected_at: selection.selected_at,
          command: child,
        },
        result,
      })
    }
    async function readOnly(afterUnknown = false) {
      const row = ownedRead(await call(() => store.read(id)))
      if (row?.selection) return selected(row.selection, 'read')
      if (row)
        return pending(
          row.claimed ? 'routing_reconciliation_required' : 'intake_pending',
          row.intake,
        )
      return afterUnknown
        ? pending('intake_reconciliation_required')
        : workoutSnapshot({
            schema: 'conversation.intake-result.v1' as const,
            status: 'absent' as const,
            lookup: id,
          })
    }
    return {
      id,
      current,
      call,
      pending,
      ownedRead,
      selected,
      readOnly,
      mandatory(error: unknown) {
        // Auth/identity refusals stay closed. A typed 5xx may follow an effect;
        // only a read can determine its outcome without submitting it again.
        return (
          closed ??
          (error instanceof ConversationIntakeScopeRefusal ||
          (error instanceof MobileApiError && error.status < 500)
            ? error
            : null)
        )
      },
    }
  }
  return Object.freeze({
    async read(
      raw: ConversationIntakeLookup,
      negotiation: ConversationFeedbackPresentationNegotiation = 'legacy',
    ) {
      return operation(raw, negotiation).readOnly()
    },
    async submit(
      original: BoundConversationIntake,
      epoch: string,
      negotiation: ConversationFeedbackPresentationNegotiation = 'legacy',
    ) {
      const command = pinConversationIntake(original),
        op = operation(
          {
            ownerId: command.ownerId,
            intakeId: command.intakeId,
            inputHash: command.inputHash,
            epoch,
          },
          negotiation,
        )
      try {
        const prior = op.ownedRead(await op.call(() => store.read(op.id)))
        if (prior?.selection) return await op.selected(prior.selection, 'submit')
        if (prior?.claimed) return op.pending('routing_reconciliation_required', prior.intake)
        let binding = prior?.intake
        if (!binding) {
          const admitted = await op.call(() => store.admit(command, epoch))
          if (!('intake' in admitted)) return op.pending(admitted.action, null, 'held')
          binding = admitted.intake
          sameBinding(binding, op.id)
        }
        const captured = await op.call(() => store.capture(command, epoch))
        if (!('context' in captured)) return op.pending(captured.action, binding, 'held')
        const source = parseConversationIntakeSource(command, binding, {
          source_hash: captured.source_hash,
          context: captured.context,
        })
        // A neutral media action is never fabricated into the older typed user
        // actions. Genuine parent/media projection is a required later gate.
        if (command.input.source.channel === 'media')
          return op.pending('media_projection_required', binding, 'held')
        const router = makeRouter(),
          route = router.route.bind(router)
        const claim = await op.call(() => store.claim(command, epoch, source.sourceHash))
        if (claim.action === 'already_claimed') return op.readOnly(true)
        if (claim.action !== 'claimed') return op.pending(claim.action, binding, 'held')
        await op.current()
        const decision = parseConversationIntakeRoutingDecision(await op.call(() => route(source)))
        const sealed = await op.call(() =>
          store.seal(command, epoch, source.sourceHash, claim.claim_id, decision),
        )
        if (!('selection' in sealed)) return op.pending(sealed.action, binding, 'held')
        const selection = parseConversationIntakeSelection(command, binding, sealed.selection)
        if (
          selection.source_hash !== source.sourceHash ||
          !isDeepStrictEqual(selection.decision, decision)
        )
          throw failure('conversation_intake_changed')
        return await op.selected(selection, 'submit')
      } catch (error) {
        const mandatory = op.mandatory(error)
        if (mandatory) throw mandatory
        // An outcome may already be durable. Reconcile ONCE by reads only;
        // never repeat classification, seal or a typed submit in this attempt.
        return op.readOnly(true)
      }
    },
  })
}
