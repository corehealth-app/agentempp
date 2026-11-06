/** Private SQL recovery proofs only. One request's real Auth/admin/patient/epoch
 * observer is mandatory. No clock-based repair decision, retry, provider, typed
 * writer, GET repair or public projection is installed here. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  type BoundConversationIntake,
  type ConversationIntakeBinding,
  conversationIntakeBindingSchema,
  parseConversationIntakeBinding,
  parseConversationIntakeRoutingDecision,
  pinConversationIntake,
} from './conversation-intake-contracts'
import {
  type ConversationIntakeScopePort,
  ConversationIntakeScopeRefusal,
} from './conversation-intake-store'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  workoutClock,
  workoutDigest,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import { MobileApiError } from './http'

export type ConversationIntakeRecoveryRPCName =
  | 'read_conversation_intake_routing_result'
  | 'reconcile_conversation_intake_routing'
export interface ConversationIntakeRecoveryRPCPort {
  rpc(
    name: ConversationIntakeRecoveryRPCName,
    args: Readonly<Record<string, unknown>>,
  ): PromiseLike<unknown>
}
const requiredJSON = z.unknown().refine((value) => value !== undefined)
const resultSchema = z
  .object({
    schema: z.literal('conversation.intake-routing-result.v1'),
    decision_hash: workoutHash,
    decision: requiredJSON,
    recorded_at: workoutClock,
    origin: z.enum(['router', 'interrupted', 'sealed_selection_backfill']),
  })
  .strict()
const proofSchema = z
  .object({
    action: z.literal('available'),
    intake: conversationIntakeBindingSchema,
    source_hash: workoutHash,
    claim_id: workoutUUID,
    lease_anchor_at: workoutClock,
    lease_clock_origin: z.enum(['claim', 'migration_backfill']),
    result: resultSchema.nullable(),
  })
  .strict()
const readSchema = z.union([
  proofSchema,
  z
    .object({ action: z.enum(['absent', 'stale_epoch', 'input_conflict', 'source_conflict']) })
    .strict(),
])
const reconcileSchema = z.union([
  z.object({ action: z.enum(['reconciled', 'replay']), result: proofSchema }).strict(),
  z
    .object({
      action: z.enum([
        'absent',
        'stale_epoch',
        'input_conflict',
        'source_conflict',
        'claim_conflict',
        'in_flight',
      ]),
    })
    .strict(),
])
const sdkSchema = z.object({ data: requiredJSON, error: requiredJSON }).passthrough()
const interruptedDecision = parseConversationIntakeRoutingDecision({
  schema: 'conversation.intake-routing.v1',
  kind: 'clarification_required',
  reason: 'routing_interrupted',
  question: {
    field: 'description',
    text: 'Não foi possível concluir o processamento. Pode confirmar o que deseja registrar?',
  },
})
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_intake_unavailable',
    'Conversation intake is unavailable',
  )
}
function check(value: boolean): asserts value {
  if (!value) unavailable()
}
function originalFrame(
  original: BoundConversationIntake,
  actualParent: ConversationIntakeBinding,
  sourceHash: string,
) {
  try {
    const bound = pinConversationIntake(original),
      parent = workoutSnapshot(
        parseConversationIntakeBinding(bound, workoutSnapshot(actualParent)),
      ),
      hash = workoutHash.parse(sourceHash),
      identity = workoutSnapshot({
        ownerId: bound.ownerId,
        intakeId: bound.intakeId,
        inputHash: bound.inputHash,
        epoch: parent.epoch,
      })
    return { bound, parent, hash, identity }
  } catch {
    return unavailable()
  }
}
type Frame = ReturnType<typeof originalFrame>
function decodeProof(raw: unknown, frame: Frame, expectedClaim?: string) {
  const value = proofSchema.parse(workoutSnapshot(raw)),
    binding = parseConversationIntakeBinding(frame.bound, value.intake),
    instant = conversationJournalInstant,
    admitted = instant(frame.parent.admitted_at),
    anchor = instant(value.lease_anchor_at)
  check(binding.epoch === frame.parent.epoch && instant(binding.admitted_at) === admitted)
  check(
    value.source_hash === frame.hash &&
      (expectedClaim === undefined || value.claim_id === expectedClaim),
  )
  check(anchor >= admitted)
  if (value.result === null) return workoutSnapshot({ ...value, intake: binding, result: null })
  const result = value.result,
    decision = parseConversationIntakeRoutingDecision(result.decision),
    recorded = instant(result.recorded_at)
  check(result.decision_hash === workoutDigest(decision) && recorded >= admitted)
  if (result.origin === 'sealed_selection_backfill') {
    // This timestamp is the actual old selected_at, not a guessed claim time.
    // It can precede the explicitly conservative migration lease anchor.
    check(value.lease_clock_origin === 'migration_backfill')
  } else {
    check(recorded >= anchor)
    if (result.origin === 'interrupted')
      check(
        recorded >= anchor + 60_000_000_000n && isDeepStrictEqual(decision, interruptedDecision),
      )
  }
  return workoutSnapshot({ ...value, intake: binding, result: { ...result, decision } })
}
export function createConversationIntakeRecoveryStore(
  rpcPort: ConversationIntakeRecoveryRPCPort,
  scopePort: ConversationIntakeScopePort,
) {
  if (typeof rpcPort?.rpc !== 'function' || typeof scopePort?.checkCurrentScope !== 'function')
    return unavailable()
  const rpc = rpcPort.rpc.bind(rpcPort),
    observe = scopePort.checkCurrentScope.bind(scopePort)
  let closed = false
  async function call<T>(
    name: ConversationIntakeRecoveryRPCName,
    frame: Frame,
    extra: Readonly<Record<string, unknown>>,
    decode: (raw: unknown) => T,
  ): Promise<T> {
    const who = workoutSnapshot(frame.identity),
      args = workoutSnapshot({
        p_user_id: who.ownerId,
        p_intake_id: who.intakeId,
        p_input_hash: who.inputHash,
        p_expected_epoch: who.epoch,
        p_source_hash: frame.hash,
        ...extra,
      })
    async function current() {
      if (closed) throw new ConversationIntakeScopeRefusal()
      try {
        if ((await observe(who)) !== true || closed) throw new Error('Closed original intake scope')
      } catch {
        closed = true
        throw new ConversationIntakeScopeRefusal()
      }
    }
    await current()
    let snapshot: unknown
    try {
      // Detach before any post-RPC asynchronous observer can mutate SDK aliases.
      snapshot = workoutSnapshot(await rpc(name, args))
    } catch {
      await current()
      return unavailable()
    }
    await current()
    try {
      const envelope = sdkSchema.parse(snapshot)
      if (envelope.error !== null) return unavailable()
      return workoutSnapshot(decode(envelope.data))
    } catch {
      return unavailable()
    }
  }
  return Object.freeze({
    async read(
      original: BoundConversationIntake,
      actualParent: ConversationIntakeBinding,
      sourceHash: string,
    ) {
      if (closed) throw new ConversationIntakeScopeRefusal()
      const frame = originalFrame(original, actualParent, sourceHash)
      return call('read_conversation_intake_routing_result', frame, {}, (raw) => {
        const value = readSchema.parse(raw)
        return value.action === 'available' ? decodeProof(value, frame) : value
      })
    },
    async reconcile(
      original: BoundConversationIntake,
      actualParent: ConversationIntakeBinding,
      sourceHash: string,
      claimId: string,
    ) {
      if (closed) throw new ConversationIntakeScopeRefusal()
      const frame = originalFrame(original, actualParent, sourceHash)
      let claim: string
      try {
        claim = workoutUUID.parse(claimId)
      } catch {
        return unavailable()
      }
      return call('reconcile_conversation_intake_routing', frame, { p_claim_id: claim }, (raw) => {
        const value = reconcileSchema.parse(raw)
        if (value.action !== 'reconciled' && value.action !== 'replay') return value
        const proof = decodeProof(value.result, frame, claim)
        if (proof.result === null) return unavailable()
        if (value.action === 'reconciled') check(proof.result.origin === 'interrupted')
        return { ...value, result: { ...proof, result: proof.result } }
      })
    },
  })
}
