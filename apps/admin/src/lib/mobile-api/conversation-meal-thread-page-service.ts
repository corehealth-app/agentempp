/** Opt-in v2 public history. Observed heads are history, never answer/write
 * permission. A linked effect stays linked; it is never relabelled as v1. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { bindConversationCommand } from './conversation-command-contracts'
import { projectSavedConversationMealCommandResult } from './conversation-meal-command-result'
import {
  type ConversationMealFeedbackPresentation,
  type ConversationMealFeedbackPresentationService,
  createSupabaseConversationMealFeedbackPresentation,
} from './conversation-meal-feedback-presentation'
import {
  conversationJournalExact as exact,
  conversationJournalInstant as instant,
  conversationJournalUnavailable as unavailable,
  conversationJournalUUID as uuid,
} from './conversation-meal-journal-store'
import {
  type ConversationMealThreadCursor,
  type ConversationMealThreadDescriptor,
  type ConversationMealThreadEvent,
  type ConversationMealThreadPageStore,
  conversationThreadCursorSchema,
  createSupabaseConversationMealThreadPageStore,
  parseConversationMealThreadPage,
} from './conversation-meal-thread-page-store'
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

export interface ConversationMealThreadPageRequest {
  readonly epoch: string
  readonly limit: number
  readonly cursor: string | null
}
type PublicEvent<T> = T extends { kind: 'report' | 'fulfillment' }
  ? Omit<T, 'feedback_ref'> & { readonly feedback: ConversationMealFeedbackPresentation | null }
  : T
export type PublicConversationMealThreadEvent = PublicEvent<ConversationMealThreadEvent>
export interface PublicConversationMealThreadPage {
  readonly schema: 'conversation.journal-page.v2'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly observed_at: string
  readonly threads: readonly ConversationMealThreadDescriptor[]
  readonly items: readonly PublicConversationMealThreadEvent[]
  readonly has_more: boolean
  readonly next_cursor: string | null
}
export interface ConversationMealThreadPagePorts {
  readonly store?: ConversationMealThreadPageStore
  readonly clinical?: CurrentClinicalStateSource
  readonly presentation?: ConversationMealFeedbackPresentationService
}
const requestSchema = z
  .object({
    epoch: uuid,
    limit: z.number().int().min(1).max(25),
    cursor: z.string().min(1).max(1024).nullable(),
  })
  .strict()
const cursorSchema = conversationThreadCursorSchema
  .extend({ v: z.literal(2), owner_id: uuid, epoch: uuid })
  .strict()
export const CONVERSATION_THREAD_PAGE_BYTE_CAP = 240000
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
export function encodeConversationMealThreadCursor(
  owner: string,
  epoch: string,
  anchor: ConversationMealThreadCursor,
): string {
  const v = exact(cursorSchema, { v: 2, owner_id: owner, epoch, ...anchor })
  return Buffer.from(
    JSON.stringify({ v: 2, owner_id: v.owner_id, epoch: v.epoch, at: v.at, id: v.id }),
    'utf8',
  ).toString('base64url')
}
export function decodeConversationMealThreadCursor(
  raw: string,
  owner: string,
  epoch: string,
): ConversationMealThreadCursor {
  let v: z.infer<typeof cursorSchema>
  try {
    if (!/^[A-Za-z0-9_-]{1,1024}$/u.test(raw)) return invalidCursor()
    const bytes = Buffer.from(raw, 'base64url')
    if (bytes.toString('base64url') !== raw) return invalidCursor()
    v = exact(cursorSchema, JSON.parse(bytes.toString('utf8')))
    if (encodeConversationMealThreadCursor(v.owner_id, v.epoch, { at: v.at, id: v.id }) !== raw)
      return invalidCursor()
  } catch {
    return invalidCursor()
  }
  if (v.owner_id !== owner || v.epoch !== epoch) return changed()
  return freezeConversationWriter({ at: v.at, id: v.id })
}
function required<T>(value: T | null | undefined): T {
  if (value === null || value === undefined) return unavailable()
  return value
}
function samePolicy(
  a: ReturnType<typeof projectCurrentClinicalPublicPolicy>,
  b: ReturnType<typeof projectCurrentClinicalPublicPolicy>,
) {
  const { observed_at: _a, ...left } = a,
    { observed_at: _b, ...right } = b
  return isDeepStrictEqual(left, right)
}
export function createConversationMealThreadPageService(
  db: ServiceClient,
  ports: ConversationMealThreadPagePorts = {},
) {
  const s = ports.store ?? createSupabaseConversationMealThreadPageStore(db),
    read = s.read.bind(s),
    c = ports.clinical ?? createSupabaseCurrentClinicalStateSource(db),
    clinical = Object.freeze({ capture: c.capture.bind(c) }),
    p = ports.presentation ?? createSupabaseConversationMealFeedbackPresentation(db),
    readHistorical = p.readHistorical.bind(p)
  return Object.freeze({
    async read(
      auth: MobileAuthContext,
      raw: ConversationMealThreadPageRequest,
    ): Promise<PublicConversationMealThreadPage> {
      try {
        const who = freezeConversationWriter(structuredClone(auth)),
          owner = authenticatedReevaluationOwner(who),
          authId = uuid.parse(who.authUserId),
          request = exact(requestSchema, raw),
          query = freezeConversationWriter({
            ownerId: owner,
            epoch: request.epoch,
            limit: request.limit,
            cursor:
              request.cursor === null
                ? null
                : decodeConversationMealThreadCursor(request.cursor, owner, request.epoch),
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
        const page = parseConversationMealThreadPage(await read(query), query)
        if (page.action !== 'available') {
          if (page.action === 'cursor_conflict')
            throw new MobileApiError(
              409,
              'conversation_journal_cursor_conflict',
              'The original history cursor is unavailable',
            )
          if (page.action === 'event_conflict') return unavailable()
          return changed()
        }
        const threads = new Map(page.threads.map((t) => [t.thread_id, t])),
          entries: PublicConversationMealThreadEvent[] = []
        for (const e of page.items) {
          if (e.kind !== 'report' && e.kind !== 'fulfillment') {
            entries.push(e)
            continue
          }
          let feedback: ConversationMealFeedbackPresentation | null = null
          if (e.kind === 'report' && e.receipt && e.feedback_ref) {
            const t = required(threads.get(e.thread_id)),
              command = bindConversationCommand(owner, `cmsg1:${t.thread_id}`, t.original_command)
            try {
              const proposed = await readHistorical({
                auth: who,
                command,
                receipt: e.receipt,
                serverBinding: t.parent_binding,
              })
              feedback = projectSavedConversationMealCommandResult({
                auth: who,
                command,
                expectedEpoch: request.epoch,
                serverBinding: t.parent_binding,
                receipt: e.receipt,
                feedback: proposed,
              }).feedback
              if (
                feedback &&
                (feedback.original.schema !== e.feedback_ref.schema ||
                  feedback.original.registration_id !== e.feedback_ref.registration_id)
              )
                return unavailable()
            } catch {
              /* Optional original feedback never repeats or invalidates the effect. */ feedback =
                null
            }
          }
          // Linked historical presentation is a separately qualified seam. A reference
          // alone is not a rendered six-block result, and no v1 adapter receives a child.
          const { feedback_ref: _ref, ...visible } = e
          entries.push(freezeConversationWriter({ ...visible, feedback }))
        }
        const after = readCurrentClinicalState(
          await captureCurrentClinicalState(clinical, clinicalRequest),
          owner,
        )
        if (
          after.epoch !== request.epoch ||
          instant(after.observed_at) < instant(before.observed_at) ||
          currentClinicalReadBinding(before) !== currentClinicalReadBinding(after) ||
          instant(page.observed_at) < instant(before.observed_at) ||
          instant(page.observed_at) > instant(after.observed_at)
        )
          return changed()
        const policy = projectCurrentClinicalPublicPolicy(after)
        for (const e of entries) {
          if ((e.kind === 'report' || e.kind === 'fulfillment') && e.feedback) {
            const f = e.feedback,
              at = instant(f.provenance.observed_at)
            if (
              !samePolicy(f.current_policy, policy) ||
              at < instant(before.observed_at) ||
              at > instant(after.observed_at)
            )
              return changed()
          }
        }
        const items: PublicConversationMealThreadEvent[] = [],
          included = new Map<string, ConversationMealThreadDescriptor>()
        const packet = (
          more: boolean,
          cursor: string | null,
        ): PublicConversationMealThreadPage => ({
          schema: 'conversation.journal-page.v2',
          auth_user_id: authId,
          owner_id: owner,
          epoch: request.epoch,
          observed_at: after.observed_at,
          threads: [...included.values()].sort((a, b) =>
            a.thread_id < b.thread_id ? -1 : a.thread_id > b.thread_id ? 1 : 0,
          ),
          items,
          has_more: more,
          next_cursor: cursor,
        })
        const cursorFor = (e: PublicConversationMealThreadEvent) =>
          encodeConversationMealThreadCursor(owner, request.epoch, { at: e.at, id: e.event_id })
        for (let i = 0; i < entries.length; i++) {
          const e = entries[i],
            added = !included.has(e.thread_id)
          items.push(e)
          if (added) included.set(e.thread_id, required(threads.get(e.thread_id)))
          const more = page.has_more || i < entries.length - 1
          if (
            Buffer.byteLength(JSON.stringify(packet(more, more ? cursorFor(e) : null)), 'utf8') >
            CONVERSATION_THREAD_PAGE_BYTE_CAP
          ) {
            items.pop()
            if (added) included.delete(e.thread_id)
            if (!items.length)
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
            page.has_more,
            page.has_more && items.length ? cursorFor(items[items.length - 1]) : null,
          ),
        )
      } catch (error) {
        if (error instanceof MobileApiError) throw error
        return unavailable()
      }
    },
  })
}
