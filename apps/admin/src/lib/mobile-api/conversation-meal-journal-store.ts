/** Private immutable journal transport only. No clinical capture, domain
 * writer, model, admission or implicit read recovery belongs to this adapter. */
import { isDeepStrictEqual } from 'node:util'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
} from './conversation-command-candidate-contracts'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  type ConversationMealDecisionReceipt,
  parseConversationMealDecisionReceipt,
} from './conversation-meal-decision-store'
import {
  type ConversationMealEditReceipt,
  detachConversationMealEditJson,
  parseConversationMealEditHistoricalReceipt,
} from './conversation-meal-edit-contracts'
import {
  type ConversationMealEffectReceipt,
  parseConversationMealEffectReceipt,
} from './conversation-meal-feedback-store'
import {
  conversationWriterClock,
  freezeConversationWriter,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'

export const conversationJournalUUID = z
  .string()
  .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
const idPart = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
const eventId = z.string().regex(new RegExp(`^(command/${idPart}|edit/${idPart}/${idPart})$`, 'u'))
const sqlClock = conversationWriterClock.refine((v) =>
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/u.test(v),
)
export const conversationJournalCursorSchema = z.object({ at: sqlClock, id: eventId }).strict()
export type ConversationMealJournalCursor = Readonly<
  z.infer<typeof conversationJournalCursorSchema>
>
export const conversationJournalQuerySchema = z
  .object({
    ownerId: conversationJournalUUID,
    epoch: conversationJournalUUID,
    limit: z.number().int().min(1).max(25),
    cursor: conversationJournalCursorSchema.nullable(),
  })
  .strict()
export type ConversationMealJournalQuery = Readonly<z.infer<typeof conversationJournalQuerySchema>>
export interface ConversationMealJournalCommandEntry {
  readonly kind: 'command'
  readonly eventId: string
  readonly at: string
  readonly binding: ConversationJournalBinding
  readonly command: BoundConversationMealCommand
  readonly status: 'pending' | 'registered' | 'not_recorded'
  readonly receipt: ConversationMealEffectReceipt | null
  readonly decision: ConversationMealDecisionReceipt | null
}
export interface ConversationMealJournalEditEntry {
  readonly kind: 'edit'
  readonly eventId: string
  readonly at: string
  readonly binding: ConversationJournalBinding
  readonly receipt: ConversationMealEditReceipt
}
export type ConversationMealJournalEntry =
  | ConversationMealJournalCommandEntry
  | ConversationMealJournalEditEntry
export interface ConversationMealJournalPage {
  readonly action: 'available'
  readonly ownerId: string
  readonly epoch: string
  readonly items: readonly ConversationMealJournalEntry[]
  readonly hasMore: boolean
  readonly nextCursor: ConversationMealJournalCursor | null
}
export type ConversationMealJournalOutcome =
  | ConversationMealJournalPage
  | { readonly action: 'absent' | 'stale_epoch' | 'cursor_conflict' | 'event_conflict' }
export interface ConversationMealJournalStore {
  read(input: ConversationMealJournalQuery): Promise<ConversationMealJournalOutcome>
}
export function conversationJournalUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_journal_unavailable',
    'Conversation history is unavailable',
  )
}
export function conversationJournalInstant(raw: string): bigint {
  conversationWriterClock.parse(raw)
  if (/\.\d{10}/u.test(raw)) return conversationJournalUnavailable()
  const fraction = /\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/u.exec(raw)?.[1] ?? ''
  return BigInt(Math.floor(Date.parse(raw) / 1000)) * 1000000000n + BigInt(fraction.padEnd(9, '0'))
}
export function conversationJournalExact<T>(schema: z.ZodType<T>, raw: unknown): T {
  const copy = detachConversationMealEditJson(raw),
    value = schema.parse(copy)
  if (!isDeepStrictEqual(copy, value)) return conversationJournalUnavailable()
  return freezeConversationWriter(value)
}
function binding(raw: unknown, expected: ConversationMealJournalQuery) {
  const value = conversationJournalExact(conversationJournalBindingSchema, raw)
  conversationJournalInstant(value.admitted_at)
  if (value.owner_id !== expected.ownerId || value.epoch !== expected.epoch)
    return conversationJournalUnavailable()
  return value
}
const entryBase = { event_id: eventId, at: sqlClock, command: conversationJournalBindingSchema }
function entry(raw: unknown, expected: ConversationMealJournalQuery): ConversationMealJournalEntry {
  const kind = z.object({ kind: z.enum(['command', 'edit']) }).parse(raw).kind
  if (kind === 'edit') {
    const v = conversationJournalExact(
        z.object({ ...entryBase, kind: z.literal('edit'), receipt: z.unknown() }).strict(),
        raw,
      ),
      b = binding(v.command, expected),
      receipt = parseConversationMealEditHistoricalReceipt(v.receipt, b)
    if (
      v.event_id !== `edit/${b.command_id}/${receipt.operation_id}` ||
      conversationJournalInstant(v.at) !== conversationJournalInstant(receipt.applied_at)
    )
      return conversationJournalUnavailable()
    return freezeConversationWriter({ kind, eventId: v.event_id, at: v.at, binding: b, receipt })
  }
  const v = conversationJournalExact(
      z
        .object({
          ...entryBase,
          kind: z.literal('command'),
          source_input: z.unknown(),
          status: z.enum(['pending', 'registered', 'not_recorded']),
          receipt: z.unknown().nullable(),
          decision: z.unknown().nullable(),
        })
        .strict(),
      raw,
    ),
    b = binding(v.command, expected),
    command = bindConversationCommand(expected.ownerId, `cmsg1:${b.command_id}`, v.source_input)
  if (
    command.commandId !== b.command_id ||
    command.inputHash !== b.input_hash ||
    v.event_id !== `command/${b.command_id}` ||
    conversationJournalInstant(v.at) !== conversationJournalInstant(b.admitted_at)
  )
    return conversationJournalUnavailable()
  const receipt =
      v.receipt === null ? null : parseConversationMealEffectReceipt(v.receipt, command),
    decision = v.decision === null ? null : parseConversationMealDecisionReceipt(v.decision, b)
  if (
    (v.status === 'registered') !== (receipt !== null) ||
    (v.status === 'not_recorded') !== (decision !== null) ||
    (receipt !== null && decision !== null)
  )
    return conversationJournalUnavailable()
  if (
    receipt &&
    conversationJournalInstant(receipt.consumed_at) < conversationJournalInstant(b.admitted_at)
  )
    return conversationJournalUnavailable()
  return freezeConversationWriter({
    kind,
    eventId: v.event_id,
    at: v.at,
    binding: b,
    command,
    status: v.status,
    receipt,
    decision,
  })
}
export function parseConversationMealJournalPage(
  raw: unknown,
  expected: ConversationMealJournalQuery,
): ConversationMealJournalOutcome {
  try {
    const query = conversationJournalExact(conversationJournalQuerySchema, expected),
      refused = z
        .object({ action: z.enum(['absent', 'stale_epoch', 'cursor_conflict', 'event_conflict']) })
        .strict()
        .safeParse(raw)
    if (refused.success) return freezeConversationWriter(refused.data)
    const v = conversationJournalExact(
      z
        .object({
          action: z.literal('available'),
          owner_id: conversationJournalUUID,
          epoch: conversationJournalUUID,
          items: z.array(z.unknown()).max(25),
          has_more: z.boolean(),
          next_cursor: conversationJournalCursorSchema.nullable(),
        })
        .strict(),
      raw,
    )
    if (v.owner_id !== query.ownerId || v.epoch !== query.epoch || v.items.length > query.limit)
      return conversationJournalUnavailable()
    const items = v.items.map((value) => entry(value, query)),
      ids = new Set<string>()
    let previous = query.cursor === null ? null : { at: query.cursor.at, eventId: query.cursor.id }
    for (const item of items) {
      if (ids.has(item.eventId)) return conversationJournalUnavailable()
      ids.add(item.eventId)
      if (previous) {
        const time = conversationJournalInstant(item.at),
          before = conversationJournalInstant(previous.at)
        if (time > before || (time === before && item.eventId >= previous.eventId))
          return conversationJournalUnavailable()
      }
      previous = item
    }
    const last = items.at(-1)
    if (
      v.has_more
        ? !last ||
          items.length !== query.limit ||
          !isDeepStrictEqual(v.next_cursor, { at: last.at, id: last.eventId })
        : v.next_cursor !== null
    )
      return conversationJournalUnavailable()
    return freezeConversationWriter({
      action: 'available',
      ownerId: v.owner_id,
      epoch: v.epoch,
      items,
      hasMore: v.has_more,
      nextCursor: v.next_cursor,
    })
  } catch {
    return conversationJournalUnavailable()
  }
}
/** Revalidate a detached typed-port result before it becomes public authority.
 * The SQL binding is preserved; no historical operation input is invented. */
export function validateConversationMealJournalPage(
  raw: unknown,
  expected: ConversationMealJournalQuery,
): ConversationMealJournalOutcome {
  try {
    const refusal = z
      .object({ action: z.enum(['absent', 'stale_epoch', 'cursor_conflict', 'event_conflict']) })
      .strict()
      .safeParse(raw)
    if (refusal.success) return parseConversationMealJournalPage(refusal.data, expected)
    const v = conversationJournalExact(
      z
        .object({
          action: z.literal('available'),
          ownerId: conversationJournalUUID,
          epoch: conversationJournalUUID,
          items: z.array(z.unknown()).max(25),
          hasMore: z.boolean(),
          nextCursor: conversationJournalCursorSchema.nullable(),
        })
        .strict(),
      raw,
    )
    const items = v.items.map((rawEntry) => {
      const kind = z.object({ kind: z.enum(['command', 'edit']) }).parse(rawEntry).kind
      if (kind === 'edit') {
        const e = conversationJournalExact(
          z
            .object({
              kind: z.literal('edit'),
              eventId,
              at: sqlClock,
              binding: conversationJournalBindingSchema,
              receipt: z.unknown(),
            })
            .strict(),
          rawEntry,
        )
        return { kind, event_id: e.eventId, at: e.at, command: e.binding, receipt: e.receipt }
      }
      const e = conversationJournalExact(
        z
          .object({
            kind: z.literal('command'),
            eventId,
            at: sqlClock,
            binding: conversationJournalBindingSchema,
            command: z.unknown(),
            status: z.enum(['pending', 'registered', 'not_recorded']),
            receipt: z.unknown().nullable(),
            decision: z.unknown().nullable(),
          })
          .strict(),
        rawEntry,
      )
      const bound = conversationJournalExact(
          z
            .object({
              ownerId: conversationJournalUUID,
              commandId: conversationJournalUUID,
              inputHash: z.string().regex(/^[0-9a-f]{64}$/u),
              command: z.unknown(),
            })
            .strict(),
          e.command,
        ),
        command = bindConversationCommand(bound.ownerId, `cmsg1:${bound.commandId}`, bound.command)
      if (!isDeepStrictEqual(command, bound)) return conversationJournalUnavailable()
      return {
        kind,
        event_id: e.eventId,
        at: e.at,
        command: e.binding,
        source_input: command.command,
        status: e.status,
        receipt: e.receipt,
        decision: e.decision,
      }
    })
    return parseConversationMealJournalPage(
      {
        action: v.action,
        owner_id: v.ownerId,
        epoch: v.epoch,
        items,
        has_more: v.hasMore,
        next_cursor: v.nextCursor,
      },
      expected,
    )
  } catch {
    return conversationJournalUnavailable()
  }
}
export function createSupabaseConversationMealJournalStore(
  db: ServiceClient,
): ConversationMealJournalStore {
  type RPC = (
    name: 'read_conversation_meal_journal_page',
    args: Record<string, Json>,
  ) => PromiseLike<unknown>
  const rpc = db.rpc.bind(db) as RPC
  return Object.freeze({
    async read(raw: ConversationMealJournalQuery) {
      try {
        const input = conversationJournalExact(conversationJournalQuerySchema, raw),
          response = z.object({ data: z.unknown(), error: z.unknown() }).parse(
            await rpc(
              'read_conversation_meal_journal_page',
              freezeConversationWriter({
                p_user_id: input.ownerId,
                p_expected_epoch: input.epoch,
                p_limit: input.limit,
                p_cursor: input.cursor,
              }),
            ),
          )
        if (response.error !== null) return conversationJournalUnavailable()
        return parseConversationMealJournalPage(response.data, input)
      } catch {
        return conversationJournalUnavailable()
      }
    },
  })
}
