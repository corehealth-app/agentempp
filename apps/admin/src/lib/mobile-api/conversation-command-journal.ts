/** Inert service-only transport for the durable journal. The candidate is an
 * immutable intermediate artifact, not authority for any registration writer. */
import { isDeepStrictEqual } from 'node:util'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ConversationCandidateEnvelope,
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
  conversationJournalUnavailable,
  detachAndFreeze,
  encodeConversationCandidate,
  parseConversationCandidate,
} from './conversation-command-candidate-contracts'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'

export interface ConversationCommandIdentity {
  ownerId: string
  commandId: string
}
export type ConversationJournalRead =
  | { action: 'absent' | 'stale_epoch' }
  | {
      action: 'available'
      binding: ConversationJournalBinding
      source: BoundConversationMealCommand
      state: 'admitted' | 'candidate_attached'
      candidate: ConversationCandidateEnvelope | null
      candidateHash: string | null
    }
export type ConversationJournalAdmit =
  | { action: 'admitted' | 'replay'; binding: ConversationJournalBinding }
  | { action: 'input_conflict' | 'stale_epoch' }
export type ConversationJournalAttach =
  | { action: 'attached' | 'replay'; candidateHash: string }
  | { action: 'input_conflict' | 'candidate_conflict' | 'stale_epoch' | 'absent' }
export interface ConversationCommandJournal {
  read(identity: ConversationCommandIdentity): Promise<ConversationJournalRead>
  admit(command: BoundConversationMealCommand): Promise<ConversationJournalAdmit>
  attach(
    command: BoundConversationMealCommand,
    preparation: unknown,
  ): Promise<ConversationJournalAttach>
}
const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const whoSchema = z.object({ ownerId: uuid, commandId: uuid }).strict()
const emptyRead = [
  z.object({ action: z.literal('absent') }).strict(),
  z.object({ action: z.literal('stale_epoch') }).strict(),
] as const
function data(raw: unknown): unknown {
  const result = z.object({ data: z.unknown(), error: z.unknown() }).parse(raw)
  if (result.error !== null) return conversationJournalUnavailable()
  return result.data
}
function bound(raw: BoundConversationMealCommand): BoundConversationMealCommand {
  const result = bindConversationCommand(raw.ownerId, `cmsg1:${raw.commandId}`, raw.command)
  if (!isDeepStrictEqual(result, raw)) return conversationJournalUnavailable()
  return result
}
function binding(raw: unknown, expected: BoundConversationMealCommand): ConversationJournalBinding {
  const value = conversationJournalBindingSchema.parse(raw)
  if (
    value.owner_id !== expected.ownerId ||
    value.command_id !== expected.commandId ||
    value.input_hash !== expected.inputHash
  )
    return conversationJournalUnavailable()
  return detachAndFreeze(value)
}
export function createSupabaseConversationCommandJournal(
  db: ServiceClient,
): ConversationCommandJournal {
  const rpc = db.rpc.bind(db)
  return Object.freeze({
    async read(identity: ConversationCommandIdentity): Promise<ConversationJournalRead> {
      try {
        const who = whoSchema.parse(identity)
        const result = z
          .discriminatedUnion('action', [
            ...emptyRead,
            z
              .object({
                action: z.literal('available'),
                command: z.unknown(),
                state: z.enum(['admitted', 'candidate_attached']),
                source_input: z.unknown(),
                candidate: z.unknown().nullable(),
                candidate_hash: hash.nullable(),
              })
              .strict(),
          ])
          .parse(
            data(
              await rpc('read_conversation_meal_command', {
                p_user_id: who.ownerId,
                p_command_id: who.commandId,
              }),
            ),
          )
        if (result.action !== 'available') return result
        const source = bindConversationCommand(
          who.ownerId,
          `cmsg1:${who.commandId}`,
          result.source_input,
        )
        const b = binding(result.command, source)
        if (
          (result.state === 'admitted') !==
            (result.candidate === null && result.candidate_hash === null) ||
          (result.state === 'candidate_attached' &&
            (result.candidate === null || result.candidate_hash === null))
        )
          return conversationJournalUnavailable()
        return Object.freeze({
          action: 'available',
          binding: b,
          source,
          state: result.state,
          candidate:
            result.candidate === null ? null : parseConversationCandidate(result.candidate, source),
          candidateHash: result.candidate_hash,
        })
      } catch {
        return conversationJournalUnavailable()
      }
    },
    async admit(input: BoundConversationMealCommand): Promise<ConversationJournalAdmit> {
      try {
        const c = bound(input)
        const result = z
          .discriminatedUnion('action', [
            z.object({ action: z.literal('admitted'), command: z.unknown() }).strict(),
            z.object({ action: z.literal('replay'), command: z.unknown() }).strict(),
            z.object({ action: z.literal('input_conflict') }).strict(),
            emptyRead[1],
          ])
          .parse(
            data(
              await rpc('admit_conversation_meal_command', {
                p_user_id: c.ownerId,
                p_input: c.command as unknown as Json,
              }),
            ),
          )
        return result.action === 'admitted' || result.action === 'replay'
          ? { action: result.action, binding: binding(result.command, c) }
          : result
      } catch {
        return conversationJournalUnavailable()
      }
    },
    async attach(
      input: BoundConversationMealCommand,
      preparation: unknown,
    ): Promise<ConversationJournalAttach> {
      try {
        const c = bound(input),
          candidate = encodeConversationCandidate(c, preparation)
        const result = z
          .discriminatedUnion('action', [
            z.object({ action: z.literal('attached'), candidate_hash: hash }).strict(),
            z.object({ action: z.literal('replay'), candidate_hash: hash }).strict(),
            z.object({ action: z.literal('input_conflict') }).strict(),
            z.object({ action: z.literal('candidate_conflict') }).strict(),
            ...emptyRead,
          ])
          .parse(
            data(
              await rpc('attach_conversation_meal_candidate', {
                p_user_id: c.ownerId,
                p_command_id: c.commandId,
                p_input_hash: c.inputHash,
                p_candidate: candidate as unknown as Json,
              }),
            ),
          )
        return result.action === 'attached' || result.action === 'replay'
          ? { action: result.action, candidateHash: result.candidate_hash }
          : result
      } catch {
        return conversationJournalUnavailable()
      }
    },
  })
}
