/** Five service-role RPCs only. A mandatory caller-owned Auth/admin/active-owner/
 * epoch observer fences every physical call, including errors. No retry or GET repair. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  type BoundConversationIntake,
  bindConversationIntake,
  type ConversationIntakeContext,
  type ConversationIntakeIdentity,
  type ConversationIntakeSelection,
  conversationIntakeBindingSchema,
  conversationIntakeSchema,
  intakeSnapshot,
  parseConversationIntakeBinding,
  parseConversationIntakeRoutingDecision,
  parseConversationIntakeSelection,
  parseConversationIntakeSource,
  pinConversationIntake,
} from './conversation-intake-contracts'
import { workoutHash, workoutUUID } from './conversation-workout-contracts'
import { MobileApiError } from './http'

export type ConversationIntakeRPCName =
  | 'admit_conversation_intake'
  | 'capture_conversation_intake_source'
  | 'claim_conversation_intake_routing'
  | 'seal_conversation_intake_routing'
  | 'read_conversation_intake'
export interface ConversationIntakeRPCPort {
  rpc(
    name: ConversationIntakeRPCName,
    args: Readonly<Record<string, unknown>>,
  ): PromiseLike<unknown>
}
export interface ConversationIntakeScopePort {
  /** Real existing-account Auth/admin/patient/epoch observer, never a DTO check. */
  checkCurrentScope(identity: Readonly<ConversationIntakeIdentity>): Promise<boolean>
}
const captureRefusals = [
  'stale_epoch',
  'input_conflict',
  'absent',
  'media_unavailable',
  'day_closed',
  'day_changed',
] as const
const refusal = <T extends string>(actions: readonly [T, ...T[]]) =>
  z.object({ action: z.enum(actions) }).strict()
const admitSchema = z.union([
  z
    .object({ action: z.enum(['admitted', 'replay']), intake: conversationIntakeBindingSchema })
    .strict(),
  refusal(['stale_epoch', 'input_conflict', 'rate_limited']),
])
const captureSchema = z.union([
  z
    .object({
      action: z.enum(['captured', 'replay']),
      source_hash: workoutHash,
      context: z.unknown(),
    })
    .strict(),
  refusal(captureRefusals),
])
const claimSchema = z.union([
  z.object({ action: z.literal('claimed'), claim_id: workoutUUID }).strict(),
  refusal(['already_claimed', ...captureRefusals, 'source_conflict']),
])
const sealSchema = z.union([
  z.object({ action: z.enum(['sealed', 'replay']), selection: z.unknown() }).strict(),
  refusal([
    ...captureRefusals,
    'source_conflict',
    'claim_conflict',
    'decision_conflict',
    'media_projection_required',
    'rate_limited',
  ]),
])
const readSchema = z.union([
  z
    .object({
      action: z.literal('available'),
      intake: conversationIntakeBindingSchema,
      source_input: conversationIntakeSchema,
      source_hash: workoutHash.nullable(),
      claimed: z.boolean(),
      selection: z.unknown(),
    })
    .strict(),
  refusal(['absent', 'stale_epoch', 'input_conflict']),
])
const identitySchema = z
  .object({
    ownerId: workoutUUID,
    intakeId: workoutUUID,
    inputHash: workoutHash,
    epoch: workoutUUID,
  })
  .strict()
const requiredJSON = z.unknown().refine((v) => v !== undefined)
const sdkSchema = z.object({ data: requiredJSON, error: requiredJSON }).passthrough()
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_intake_unavailable',
    'Conversation intake is unavailable',
  )
}
/** Preserve the closed public availability response while keeping a mandatory
 * observer denial distinguishable from an uncertain SDK/transport outcome. */
export class ConversationIntakeScopeRefusal extends MobileApiError {
  constructor() {
    super(503, 'conversation_intake_unavailable', 'Conversation intake is unavailable')
  }
}
function scopeUnavailable(): never {
  throw new ConversationIntakeScopeRefusal()
}
function check(value: boolean): asserts value {
  if (!value) unavailable()
}
function originalIdentity(
  bound: BoundConversationIntake,
  epoch: string,
): ConversationIntakeIdentity {
  return intakeSnapshot(
    identitySchema.parse({
      ownerId: bound.ownerId,
      intakeId: bound.intakeId,
      inputHash: bound.inputHash,
      epoch,
    }),
  )
}
function args(identity: ConversationIntakeIdentity) {
  return {
    p_user_id: identity.ownerId,
    p_intake_id: identity.intakeId,
    p_input_hash: identity.inputHash,
    p_expected_epoch: identity.epoch,
  }
}
function responseBinding(
  bound: BoundConversationIntake,
  raw: unknown,
  identity: ConversationIntakeIdentity,
) {
  const binding = parseConversationIntakeBinding(bound, raw)
  check(binding.epoch === identity.epoch)
  return binding
}
function bindingFromContext(raw: unknown) {
  const context = conversationIntakeBindingSchema.passthrough().parse(raw)
  return conversationIntakeBindingSchema.parse({
    owner_id: context.owner_id,
    intake_id: context.intake_id,
    input_hash: context.input_hash,
    epoch: context.epoch,
    admitted_at: context.admitted_at,
  })
}
function bindingFromSelection(raw: unknown) {
  return z.object({ intake: conversationIntakeBindingSchema }).passthrough().parse(raw).intake
}
export function createConversationIntakeStore(
  rpcPort: ConversationIntakeRPCPort,
  scopePort: ConversationIntakeScopePort,
) {
  if (typeof rpcPort?.rpc !== 'function' || typeof scopePort?.checkCurrentScope !== 'function')
    return unavailable()
  const rpc = rpcPort.rpc.bind(rpcPort),
    observe = scopePort.checkCurrentScope.bind(scopePort)
  async function call<T>(
    name: ConversationIntakeRPCName,
    identity: ConversationIntakeIdentity,
    rawArgs: Readonly<Record<string, unknown>>,
    decode: (value: unknown) => T,
  ): Promise<T> {
    const pinnedArgs = intakeSnapshot(rawArgs),
      who = intakeSnapshot(identity)
    let closed = false
    async function current() {
      if (closed) return scopeUnavailable()
      try {
        if ((await observe(who)) !== true || closed) throw new Error('Closed scope')
      } catch {
        closed = true
        return scopeUnavailable()
      }
    }
    await current()
    let snapshot: unknown
    try {
      // Do not move cloning below current(): the SDK still owns every alias.
      snapshot = intakeSnapshot(await rpc(name, pinnedArgs))
    } catch {
      await current()
      return unavailable()
    }
    await current()
    try {
      const envelope = sdkSchema.parse(snapshot)
      if (envelope.error !== null) return unavailable()
      return intakeSnapshot(decode(envelope.data))
    } catch {
      return unavailable()
    }
  }
  return Object.freeze({
    async admit(original: BoundConversationIntake, epoch: string) {
      const bound = pinConversationIntake(original),
        who = originalIdentity(bound, epoch)
      return call(
        'admit_conversation_intake',
        who,
        { p_user_id: who.ownerId, p_expected_epoch: who.epoch, p_input: bound.input },
        (raw) => {
          const result = admitSchema.parse(raw)
          if ('intake' in result)
            return { ...result, intake: responseBinding(bound, result.intake, who) }
          return result
        },
      )
    },
    async capture(original: BoundConversationIntake, epoch: string) {
      const bound = pinConversationIntake(original),
        who = originalIdentity(bound, epoch)
      return call('capture_conversation_intake_source', who, args(who), (raw) => {
        const result = captureSchema.parse(raw)
        if (result.action === 'captured' || result.action === 'replay') {
          const binding = responseBinding(bound, bindingFromContext(result.context), who),
            source = parseConversationIntakeSource(bound, binding, {
              source_hash: result.source_hash,
              context: result.context,
            })
          return {
            action: result.action,
            source_hash: source.sourceHash,
            context: source.context,
          } as {
            action: 'captured' | 'replay'
            source_hash: string
            context: ConversationIntakeContext
          }
        }
        return result
      })
    },
    async claim(original: BoundConversationIntake, epoch: string, sourceHash: string) {
      const bound = pinConversationIntake(original),
        who = originalIdentity(bound, epoch),
        hash = workoutHash.parse(sourceHash)
      return call(
        'claim_conversation_intake_routing',
        who,
        { ...args(who), p_source_hash: hash },
        (raw) => claimSchema.parse(raw),
      )
    },
    async seal(
      original: BoundConversationIntake,
      epoch: string,
      sourceHash: string,
      claimId: string,
      decision: unknown,
    ) {
      const bound = pinConversationIntake(original),
        who = originalIdentity(bound, epoch),
        hash = workoutHash.parse(sourceHash),
        claim = workoutUUID.parse(claimId),
        pinnedDecision = parseConversationIntakeRoutingDecision(decision)
      return call(
        'seal_conversation_intake_routing',
        who,
        { ...args(who), p_source_hash: hash, p_claim_id: claim, p_decision: pinnedDecision },
        (raw) => {
          const result = sealSchema.parse(raw)
          if (result.action === 'sealed' || result.action === 'replay') {
            const binding = responseBinding(bound, bindingFromSelection(result.selection), who),
              selection = parseConversationIntakeSelection(bound, binding, result.selection)
            check(
              selection.source_hash === hash &&
                isDeepStrictEqual(selection.decision, pinnedDecision),
            )
            return { action: result.action, selection } as {
              action: 'sealed' | 'replay'
              selection: ConversationIntakeSelection
            }
          }
          return result
        },
      )
    },
    async read(rawIdentity: ConversationIntakeIdentity) {
      const who = intakeSnapshot(identitySchema.parse(intakeSnapshot(rawIdentity)))
      return call('read_conversation_intake', who, args(who), (raw) => {
        const result = readSchema.parse(raw)
        if (result.action !== 'available') return result
        const bound = bindConversationIntake(
          who.ownerId,
          `cintake1:${who.intakeId}`,
          result.source_input,
        )
        check(bound.intakeId === who.intakeId && bound.inputHash === who.inputHash)
        const binding = responseBinding(bound, result.intake, who)
        check(!result.claimed || result.source_hash !== null)
        let selection: ConversationIntakeSelection | null = null
        if (result.selection !== null) {
          selection = parseConversationIntakeSelection(bound, binding, result.selection)
          check(
            result.claimed &&
              result.source_hash !== null &&
              selection.source_hash === result.source_hash,
          )
        }
        return { ...result, intake: binding, source_input: bound.input, selection }
      })
    },
  })
}
