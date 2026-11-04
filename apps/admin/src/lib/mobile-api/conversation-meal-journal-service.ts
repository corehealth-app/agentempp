/** Current-policy guarded public history. A page read is never an outbox ACK
 * and cannot invoke admission, a calculator, provider or a domain writer. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  projectSavedConversationMealCommandResult,
  type SavedConversationMealCommandResult,
} from './conversation-meal-command-result'
import type { ConversationMealCommandState } from './conversation-meal-command-service'
import {
  type PublicConversationMealEditResult,
  projectConversationMealEditEffect,
} from './conversation-meal-edit-public'
import {
  type ConversationMealFeedbackPresentationService,
  createSupabaseConversationMealFeedbackPresentation,
} from './conversation-meal-feedback-presentation'
import {
  type ConversationMealJournalCursor,
  type ConversationMealJournalEntry,
  type ConversationMealJournalStore,
  conversationJournalCursorSchema,
  conversationJournalExact,
  conversationJournalInstant,
  conversationJournalUnavailable,
  conversationJournalUUID,
  createSupabaseConversationMealJournalStore,
  validateConversationMealJournalPage,
} from './conversation-meal-journal-store'
import { freezeConversationWriter } from './conversation-meal-writer-contracts'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import {
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  readCurrentClinicalState,
} from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

export interface ConversationMealJournalRequest {
  readonly epoch: string
  readonly limit: number
  readonly cursor: string | null
}
export interface ConversationMealJournalTerminalReceipt {
  readonly schema: 'conversation.meal-decision-public.v1'
  readonly status: 'not_recorded'
  readonly owner_id: string
  readonly command_id: string
  readonly input_hash: string
  readonly epoch: string
  readonly reason: string
  readonly food_indexes: readonly number[]
  readonly decision_hash: string
  readonly sealed_at: string
}
export type PublicConversationMealJournalEntry =
  | {
      readonly event_id: string
      readonly at: string
      readonly kind: 'command'
      readonly original_command: Extract<
        ConversationMealJournalEntry,
        { kind: 'command' }
      >['command']['command']
      readonly result: ConversationMealCommandState | SavedConversationMealCommandResult
      readonly terminal_receipt: ConversationMealJournalTerminalReceipt | null
    }
  | {
      readonly event_id: string
      readonly at: string
      readonly kind: 'edit'
      readonly result: PublicConversationMealEditResult
    }
export interface PublicConversationMealJournalPage {
  readonly schema: 'conversation.journal-page.v1'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly observed_at: string
  readonly items: readonly PublicConversationMealJournalEntry[]
  readonly has_more: boolean
  readonly next_cursor: string | null
}
export interface ConversationMealJournalServicePorts {
  readonly store?: ConversationMealJournalStore
  readonly clinical?: CurrentClinicalStateSource
  readonly presentation?: ConversationMealFeedbackPresentationService
}
const requestSchema = z
  .object({
    epoch: conversationJournalUUID,
    limit: z.number().int().min(1).max(25),
    cursor: z.string().min(1).max(1024).nullable(),
  })
  .strict()
const cursorSchema = conversationJournalCursorSchema
  .extend({ v: z.literal(1), owner_id: conversationJournalUUID, epoch: conversationJournalUUID })
  .strict()
export const CONVERSATION_JOURNAL_BYTE_CAP = 240000
function changed(): never {
  throw new MobileApiError(
    409,
    'conversation_journal_changed',
    'The account or current history policy has changed',
  )
}
function invalidCursor(): never {
  throw new MobileApiError(
    422,
    'conversation_journal_invalid_cursor',
    'A canonical history cursor is required',
  )
}
export function encodeConversationMealJournalCursor(
  owner: string,
  epoch: string,
  anchor: ConversationMealJournalCursor,
): string {
  const v = conversationJournalExact(cursorSchema, { v: 1, owner_id: owner, epoch, ...anchor })
  return Buffer.from(
    JSON.stringify({ v: 1, owner_id: v.owner_id, epoch: v.epoch, at: v.at, id: v.id }),
    'utf8',
  ).toString('base64url')
}
export function decodeConversationMealJournalCursor(
  raw: string,
  owner: string,
  epoch: string,
): ConversationMealJournalCursor {
  let v: z.infer<typeof cursorSchema>
  try {
    if (!/^[A-Za-z0-9_-]{1,1024}$/u.test(raw)) return invalidCursor()
    const bytes = Buffer.from(raw, 'base64url')
    if (bytes.toString('base64url') !== raw) return invalidCursor()
    v = conversationJournalExact(cursorSchema, JSON.parse(bytes.toString('utf8')))
    if (encodeConversationMealJournalCursor(v.owner_id, v.epoch, { at: v.at, id: v.id }) !== raw)
      return invalidCursor()
  } catch {
    return invalidCursor()
  }
  if (v.owner_id !== owner || v.epoch !== epoch) return changed()
  return freezeConversationWriter({ at: v.at, id: v.id })
}
function samePolicy(
  a: ReturnType<typeof projectCurrentClinicalPublicPolicy>,
  b: ReturnType<typeof projectCurrentClinicalPublicPolicy>,
) {
  const { observed_at: _a, ...left } = a,
    { observed_at: _b, ...right } = b
  return isDeepStrictEqual(left, right)
}
export function createConversationMealJournalService(
  db: ServiceClient,
  ports: ConversationMealJournalServicePorts = {},
) {
  const s = ports.store ?? createSupabaseConversationMealJournalStore(db),
    read = s.read.bind(s),
    c = ports.clinical ?? createSupabaseCurrentClinicalStateSource(db),
    clinical = Object.freeze({ capture: c.capture.bind(c) }),
    p = ports.presentation ?? createSupabaseConversationMealFeedbackPresentation(db),
    readHistorical = p.readHistorical.bind(p)
  return Object.freeze({
    async read(
      auth: MobileAuthContext,
      rawRequest: ConversationMealJournalRequest,
    ): Promise<PublicConversationMealJournalPage> {
      try {
        const who = freezeConversationWriter(structuredClone(auth)),
          owner = authenticatedReevaluationOwner(who),
          authId = conversationJournalUUID.parse(who.authUserId),
          request = conversationJournalExact(requestSchema, rawRequest),
          query = freezeConversationWriter({
            ownerId: owner,
            epoch: request.epoch,
            limit: request.limit,
            cursor:
              request.cursor === null
                ? null
                : decodeConversationMealJournalCursor(request.cursor, owner, request.epoch),
          }),
          clinicalRequest = Object.freeze({
            userId: owner,
            mode: 'profile' as const,
            expectedEpoch: request.epoch,
          })
        const before = readCurrentClinicalState(
          await captureCurrentClinicalState(clinical, clinicalRequest),
          owner,
        )
        if (before.epoch !== request.epoch) return changed()
        const page = validateConversationMealJournalPage(await read(query), query)
        if (page.action !== 'available') {
          if (page.action === 'cursor_conflict')
            throw new MobileApiError(
              409,
              'conversation_journal_cursor_conflict',
              'The original history cursor is unavailable',
            )
          return changed()
        }
        const entries: PublicConversationMealJournalEntry[] = []
        for (const entry of page.items) {
          if (entry.kind === 'edit') {
            entries.push(
              freezeConversationWriter({
                event_id: entry.eventId,
                at: entry.at,
                kind: 'edit',
                result: {
                  schema: 'conversation.meal-edit-result.v1',
                  status: 'saved',
                  owner_id: owner,
                  command_id: entry.binding.command_id,
                  input_hash: entry.binding.input_hash,
                  epoch: entry.binding.epoch,
                  receipt: projectConversationMealEditEffect(entry.receipt),
                },
              }),
            )
            continue
          }
          let result: ConversationMealCommandState | SavedConversationMealCommandResult
          if (entry.receipt) {
            let feedback: unknown = null
            try {
              feedback = await readHistorical({
                auth: who,
                command: entry.command,
                receipt: entry.receipt,
                serverBinding: entry.binding,
              })
            } catch {
              /* Optional history never repeats or invalidates a factual effect. */
            }
            result = projectSavedConversationMealCommandResult({
              auth: who,
              command: entry.command,
              expectedEpoch: request.epoch,
              serverBinding: entry.binding,
              receipt: entry.receipt,
              feedback,
            })
          } else {
            result = freezeConversationWriter({
              schema: 'conversation.meal-command-state.v1',
              status: entry.decision ? 'not_recorded' : 'pending',
              owner_id: owner,
              command_id: entry.command.commandId,
              input_hash: entry.command.inputHash,
              epoch: request.epoch,
              ...(entry.decision
                ? { reason: entry.decision.reason, food_indexes: [...entry.decision.food_indexes] }
                : {}),
            })
          }
          const d = entry.decision,
            terminal: ConversationMealJournalTerminalReceipt | null =
              d === null
                ? null
                : {
                    schema: 'conversation.meal-decision-public.v1',
                    status: 'not_recorded',
                    owner_id: d.owner_id,
                    command_id: d.command_id,
                    input_hash: d.input_hash,
                    epoch: d.epoch,
                    reason: d.reason,
                    food_indexes: [...d.food_indexes],
                    decision_hash: d.decision_hash,
                    sealed_at: d.sealed_at,
                  }
          entries.push(
            freezeConversationWriter({
              event_id: entry.eventId,
              at: entry.at,
              kind: 'command',
              original_command: entry.command.command,
              result,
              terminal_receipt: terminal,
            }),
          )
        }
        const after = readCurrentClinicalState(
          await captureCurrentClinicalState(clinical, clinicalRequest),
          owner,
        )
        if (
          after.epoch !== request.epoch ||
          conversationJournalInstant(after.observed_at) <
            conversationJournalInstant(before.observed_at) ||
          currentClinicalReadBinding(before) !== currentClinicalReadBinding(after)
        )
          return changed()
        const policy = projectCurrentClinicalPublicPolicy(after)
        for (const entry of entries) {
          if (conversationJournalInstant(entry.at) > conversationJournalInstant(after.observed_at))
            return changed()
          if (entry.kind !== 'command') continue
          if (
            entry.result.status === 'saved' &&
            conversationJournalInstant(entry.result.receipt.consumed_at) >
              conversationJournalInstant(after.observed_at)
          )
            return changed()
          if (
            entry.terminal_receipt &&
            conversationJournalInstant(entry.terminal_receipt.sealed_at) >
              conversationJournalInstant(after.observed_at)
          )
            return changed()
          if (entry.result.status === 'saved' && entry.result.feedback) {
            const feedback = entry.result.feedback,
              clock = conversationJournalInstant(feedback.provenance.observed_at)
            if (
              !samePolicy(feedback.current_policy, policy) ||
              clock < conversationJournalInstant(before.observed_at) ||
              clock > conversationJournalInstant(after.observed_at)
            )
              return changed()
          }
        }
        const items: PublicConversationMealJournalEntry[] = []
        const packet = (
          hasMore: boolean,
          next: string | null,
        ): PublicConversationMealJournalPage => ({
          schema: 'conversation.journal-page.v1',
          auth_user_id: authId,
          owner_id: owner,
          epoch: request.epoch,
          observed_at: after.observed_at,
          items,
          has_more: hasMore,
          next_cursor: next,
        })
        const cursorFor = (e: PublicConversationMealJournalEntry) =>
          encodeConversationMealJournalCursor(owner, request.epoch, { at: e.at, id: e.event_id })
        for (let i = 0; i < entries.length; i++) {
          items.push(entries[i])
          const more = page.hasMore || i < entries.length - 1,
            candidate = packet(more, more ? cursorFor(entries[i]) : null)
          if (
            Buffer.byteLength(JSON.stringify(candidate), 'utf8') > CONVERSATION_JOURNAL_BYTE_CAP
          ) {
            items.pop()
            if (items.length === 0)
              throw new MobileApiError(
                503,
                'conversation_journal_entry_too_large',
                'The original history entry cannot be represented within the page limit',
              )
            return freezeConversationWriter(packet(true, cursorFor(items[items.length - 1])))
          }
        }
        return freezeConversationWriter(
          packet(
            page.hasMore,
            page.hasMore && items.length ? cursorFor(items[items.length - 1]) : null,
          ),
        )
      } catch (error) {
        if (error instanceof MobileApiError) throw error
        return conversationJournalUnavailable()
      }
    },
  })
}
