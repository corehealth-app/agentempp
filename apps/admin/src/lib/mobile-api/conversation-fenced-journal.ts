/** Original epoch is a precondition, not client write authority. Only the
 * new atomic fenced RPC may admit commands for the new public transport. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import {
  type ConversationCommandJournal,
  type ConversationJournalAdmit,
  createSupabaseConversationCommandJournal,
} from './conversation-command-journal'
import {
  bindConversationWriterCommand,
  conversationWriterClock,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'

function unavailable(status = 503): never {
  throw new MobileApiError(
    status,
    'conversation_fenced_admission_unavailable',
    'Command admission is unavailable',
  )
}
const outcome = z.union([
  z.object({ action: z.enum(['input_conflict', 'stale_epoch']) }).strict(),
  z.object({ action: z.literal('rate_limited') }).strict(),
  z
    .object({ action: z.enum(['admitted', 'replay']), command: conversationJournalBindingSchema })
    .strict(),
])
export function createSupabaseConversationFencedJournal(
  db: ServiceClient,
  originalEpoch: string,
): ConversationCommandJournal {
  const epoch = z
      .string()
      .uuid()
      .regex(/^[a-f0-9-]+$/u)
      .parse(originalEpoch),
    rpc = db.rpc.bind(db),
    old = createSupabaseConversationCommandJournal(db)
  return Object.freeze({
    async read(identity: Parameters<ConversationCommandJournal['read']>[0]) {
      const v = await old.read(identity)
      return v.action === 'available' && v.binding.epoch !== epoch
        ? { action: 'stale_epoch' as const }
        : v
    },
    attach: old.attach.bind(old),
    async admit(
      raw: Parameters<ConversationCommandJournal['admit']>[0],
    ): Promise<ConversationJournalAdmit> {
      try {
        const command = bindConversationWriterCommand(raw)
        const envelope = z.object({ data: z.unknown(), error: z.unknown() }).parse(
          await rpc('admit_conversation_meal_command_fenced', {
            p_user_id: command.ownerId,
            p_input: structuredClone(command.command),
            p_expected_epoch: epoch,
          }),
        )
        if (envelope.error !== null) {
          const code =
            envelope.error && typeof envelope.error === 'object' && 'code' in envelope.error
              ? envelope.error.code
              : null
          return unavailable(code === '55P03' || code === '40001' ? 409 : 503)
        }
        const copy = structuredClone(envelope.data),
          value = outcome.parse(copy)
        if (!isDeepStrictEqual(value, copy)) return unavailable()
        if (value.action === 'rate_limited')
          throw new MobileApiError(
            429,
            'conversation_admission_rate_limited',
            'Too many new commands; wait before submitting another',
          )
        if (!('command' in value)) return Object.freeze(value)
        const b = value.command
        conversationWriterClock.parse(b.admitted_at)
        if (
          b.owner_id !== command.ownerId ||
          b.command_id !== command.commandId ||
          b.input_hash !== command.inputHash ||
          b.epoch !== epoch
        )
          return unavailable()
        return Object.freeze({ action: value.action, binding: Object.freeze(b) })
      } catch (error) {
        if (
          error instanceof MobileApiError &&
          [
            'conversation_fenced_admission_unavailable',
            'conversation_admission_rate_limited',
          ].includes(error.code)
        )
          throw error
        return unavailable()
      }
    },
  })
}
