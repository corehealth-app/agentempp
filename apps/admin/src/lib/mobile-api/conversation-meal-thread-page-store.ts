/** Compact private thread transport. One read, closed immutable DTOs, no source
 * capture or write authority. SQL tokens and historical reply hashes stay opaque. */
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  parseConversationMealQuestion,
  parseConversationMealReplyBody,
  validateConversationMealReplyQuestion,
} from './conversation-meal-continuation-input'
import { parseConversationMealEffectReceipt } from './conversation-meal-feedback-store'
import {
  conversationJournalExact as exact,
  conversationJournalInstant as instant,
  conversationJournalUnavailable as unavailable,
  conversationJournalUUID as uuid,
} from './conversation-meal-journal-store'
import {
  conversationWriterClock,
  freezeConversationWriter,
} from './conversation-meal-writer-contracts'

const hash = z.string().regex(/^[0-9a-f]{64}$/u)
const clock = conversationWriterClock.refine((s) =>
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/u.test(s),
)
const persistedClock = conversationWriterClock.refine((s) => !/\.\d{10}/u.test(s))
const part = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
const eventId = z
  .string()
  .regex(
    new RegExp(`^(command/${part}|(?:reply|reply-result|fulfillment|edit)/${part}/${part})$`, 'u'),
  )
export const conversationThreadCursorSchema = z.object({ at: clock, id: eventId }).strict()
export const conversationThreadQuerySchema = z
  .object({
    ownerId: uuid,
    epoch: uuid,
    limit: z.number().int().min(1).max(25),
    cursor: conversationThreadCursorSchema.nullable(),
  })
  .strict()
export type ConversationMealThreadCursor = Readonly<z.infer<typeof conversationThreadCursorSchema>>
export type ConversationMealThreadQuery = Readonly<z.infer<typeof conversationThreadQuerySchema>>
const parentBinding = conversationJournalBindingSchema.extend({ admitted_at: clock }).strict()
const childBinding = parentBinding
  .extend({
    command_protocol: z.literal('conversation.clarification.v1'),
    kind: z.literal('meal.clarify'),
  })
  .strict()
export type ConversationMealThreadParentBinding = z.infer<typeof parentBinding>
export type ConversationMealThreadChildBinding = z.infer<typeof childBinding>
const decision = z
  .object({
    schema: z.literal('conversation.meal-decision-public.v1'),
    status: z.literal('not_recorded'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    epoch: uuid,
    reason: z.string().regex(/^[a-z_]{1,80}$/u),
    food_indexes: z
      .array(z.number().int().min(0).max(29))
      .max(30)
      .refine((a) => new Set(a).size === a.length),
    decision_hash: hash,
    sealed_at: clock,
  })
  .strict()
const head = z
  .object({
    revision: z.number().int().min(0).max(31),
    question: z.unknown().nullable(),
    fulfilled_by: uuid.nullable(),
  })
  .strict()
const rawThread = z
  .object({
    schema: z.literal('conversation.meal-thread.v1'),
    thread_id: uuid,
    parent_binding: parentBinding,
    original_command: z.unknown(),
    terminal_receipt: decision.nullable(),
    continuation: head.nullable(),
  })
  .strict()
export type ConversationMealThreadDescriptor = Omit<
  z.infer<typeof rawThread>,
  'original_command' | 'continuation'
> & {
  original_command: ReturnType<typeof bindConversationCommand>['command']
  continuation:
    | null
    | (Omit<z.infer<typeof head>, 'question'> & {
        question: ReturnType<typeof parseConversationMealQuestion> | null
      })
}
const feedbackRef = z
  .object({
    schema: z.enum(['registration.feedback.v1', 'registration.feedback.v2']),
    registration_id: uuid,
  })
  .strict()
const logIds = z
  .array(uuid)
  .min(1)
  .max(30)
  .refine((a) => new Set(a).size === a.length)
const linkedEffect = z
  .object({
    schema: z.literal('conversation.meal-continuation-effect.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    parent_command_id: uuid,
    parent_input_hash: hash,
    parent_decision_hash: hash,
    epoch: uuid,
    registration_id: uuid,
    provider_key: z.string(),
    meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
    local_date: z.string().date(),
    timezone: z.string().min(1),
    consumed_at: clock,
    log_ids: logIds,
    effect_version: z.string().regex(/^cmeal1:[a-f0-9]{64}$/u),
  })
  .strict()
export type ConversationMealThreadLinkedEffect = z.infer<typeof linkedEffect>
const ids = z
  .array(uuid)
  .max(30)
  .refine((a) => new Set(a).size === a.length)
const editEffect = z
  .object({
    schema: z.literal('conversation.meal-edit-effect-public.v1'),
    owner_id: uuid,
    command_id: uuid,
    operation_id: uuid,
    input_hash: hash,
    kind: z.enum(['saved', 'save_undone', 'registration_undone']),
    revision: z.number().int().min(1).max(2147483647),
    applied_at: persistedClock,
    undo_expires_at: persistedClock.nullable(),
    target_operation_id: uuid.nullable(),
    removed_item_ids: ids.refine((a) => a.length > 0),
    new_item_ids: ids,
    next_record_id: uuid.nullable(),
  })
  .strict()
const base = { event_id: eventId, at: clock, thread_id: uuid }
type EventBase = z.infer<z.ZodObject<typeof base>>
export type ConversationMealThreadEvent =
  | (EventBase & {
      kind: 'report'
      status: 'pending' | 'registered' | 'not_recorded'
      receipt: ReturnType<typeof parseConversationMealEffectReceipt> | null
      feedback_ref: z.infer<typeof feedbackRef> | null
    })
  | (EventBase & {
      kind: 'reply'
      child_binding: ConversationMealThreadChildBinding
      body: ReturnType<typeof parseConversationMealReplyBody>
      question: ReturnType<typeof parseConversationMealQuestion>
    })
  | (EventBase & {
      kind: 'reply_result'
      child_binding: ConversationMealThreadChildBinding
      prepared_hash: string
      status: 'needs_reply' | 'prepared'
      next_question: ReturnType<typeof parseConversationMealQuestion> | null
    })
  | (EventBase & {
      kind: 'fulfillment'
      child_binding: ConversationMealThreadChildBinding
      receipt: ConversationMealThreadLinkedEffect
      feedback_ref: z.infer<typeof feedbackRef> | null
    })
  | (EventBase & {
      kind: 'edit'
      effect_binding: ConversationMealThreadParentBinding | ConversationMealThreadChildBinding
      receipt: z.infer<typeof editEffect>
    })
export interface ConversationMealThreadPage {
  readonly action: 'available'
  readonly schema: 'conversation.journal-page-private.v2'
  readonly owner_id: string
  readonly epoch: string
  readonly observed_at: string
  readonly threads: readonly ConversationMealThreadDescriptor[]
  readonly items: readonly ConversationMealThreadEvent[]
  readonly has_more: boolean
  readonly next_cursor: ConversationMealThreadCursor | null
}
export type ConversationMealThreadOutcome =
  | ConversationMealThreadPage
  | { readonly action: 'absent' | 'stale_epoch' | 'cursor_conflict' | 'event_conflict' }
export interface ConversationMealThreadPageStore {
  read(input: ConversationMealThreadQuery): Promise<ConversationMealThreadOutcome>
}
function required<T>(value: T | null | undefined): T {
  if (value === null || value === undefined) return unavailable()
  return value
}
function between(s: string, lo: string, hi: string) {
  if (instant(s) < instant(lo) || instant(s) > instant(hi)) unavailable()
}
function descriptor(
  raw: unknown,
  q: ConversationMealThreadQuery,
  observed: string,
): ConversationMealThreadDescriptor {
  const t = exact(rawThread, raw),
    b = t.parent_binding,
    c = bindConversationCommand(q.ownerId, `cmsg1:${b.command_id}`, t.original_command)
  if (
    t.thread_id !== b.command_id ||
    b.owner_id !== q.ownerId ||
    b.epoch !== q.epoch ||
    c.commandId !== b.command_id ||
    c.inputHash !== b.input_hash
  )
    unavailable()
  between(b.admitted_at, b.admitted_at, observed)
  const d = t.terminal_receipt
  if (d) {
    if (
      d.owner_id !== q.ownerId ||
      d.command_id !== b.command_id ||
      d.input_hash !== b.input_hash ||
      d.epoch !== q.epoch
    )
      unavailable()
    between(d.sealed_at, b.admitted_at, observed)
  }
  const h = t.continuation,
    question = h?.question === null || !h ? null : parseConversationMealQuestion(h.question)
  if (
    h &&
    (!d ||
      h.fulfilled_by === b.command_id ||
      (h.fulfilled_by === null) !== (question !== null) ||
      (question !== null && question.revision !== h.revision))
  )
    unavailable()
  return freezeConversationWriter({
    ...t,
    original_command: c.command,
    continuation: h ? { ...h, question } : null,
  })
}
function parseEvent(
  raw: unknown,
  t: ConversationMealThreadDescriptor,
  q: ConversationMealThreadQuery,
  observed: string,
): ConversationMealThreadEvent {
  const kind = z
      .object({ kind: z.enum(['report', 'reply', 'reply_result', 'fulfillment', 'edit']) })
      .parse(raw).kind,
    b = t.parent_binding
  const verifyChild = (c: ConversationMealThreadChildBinding) => {
    if (
      !t.terminal_receipt ||
      !t.continuation ||
      c.owner_id !== q.ownerId ||
      c.epoch !== q.epoch ||
      c.command_id === b.command_id
    )
      unavailable()
    between(c.admitted_at, t.terminal_receipt.sealed_at, observed)
  }
  const verifyRef = (
    ref: z.infer<typeof feedbackRef> | null,
    r: { registration_id: string } | null,
  ) => {
    if (ref && (!r || ref.registration_id !== r.registration_id)) unavailable()
  }
  if (kind === 'report') {
    const v = exact(
      z
        .object({
          ...base,
          kind: z.literal(kind),
          status: z.enum(['pending', 'registered', 'not_recorded']),
          receipt: z.unknown().nullable(),
          feedback_ref: feedbackRef.nullable(),
        })
        .strict(),
      raw,
    )
    const bound = bindConversationCommand(q.ownerId, `cmsg1:${b.command_id}`, t.original_command),
      r = v.receipt === null ? null : parseConversationMealEffectReceipt(v.receipt, bound)
    if (
      v.event_id !== `command/${b.command_id}` ||
      v.at !== b.admitted_at ||
      (v.status === 'registered') !== (r !== null) ||
      (v.status === 'not_recorded') !== (t.terminal_receipt !== null)
    )
      unavailable()
    if (r) {
      clock.parse(r.consumed_at)
      between(r.consumed_at, b.admitted_at, observed)
    }
    verifyRef(v.feedback_ref, r)
    return { ...v, receipt: r }
  }
  if (kind === 'reply') {
    const v = exact(
        z
          .object({
            ...base,
            kind: z.literal(kind),
            child_binding: childBinding,
            body: z.unknown(),
            question: z.unknown(),
          })
          .strict(),
        raw,
      ),
      c = v.child_binding
    verifyChild(c)
    const body = parseConversationMealReplyBody(v.body),
      question = parseConversationMealQuestion(v.question)
    validateConversationMealReplyQuestion(body, question)
    if (
      v.event_id !== `reply/${b.command_id}/${c.command_id}` ||
      v.at !== c.admitted_at ||
      body.expected_revision > required(t.continuation).revision ||
      (body.expected_revision === required(t.continuation).revision &&
        !isDeepStrictEqual(question, required(t.continuation).question))
    )
      unavailable()
    return { ...v, body, question }
  }
  if (kind === 'reply_result') {
    const v = exact(
        z
          .object({
            ...base,
            kind: z.literal(kind),
            child_binding: childBinding,
            prepared_hash: hash,
            status: z.enum(['needs_reply', 'prepared']),
            next_question: z.unknown().nullable(),
          })
          .strict(),
        raw,
      ),
      c = v.child_binding
    verifyChild(c)
    const next = v.next_question === null ? null : parseConversationMealQuestion(v.next_question)
    if (
      v.event_id !== `reply-result/${b.command_id}/${c.command_id}` ||
      (v.status === 'needs_reply') !== (next !== null) ||
      (next && next.revision > required(t.continuation).revision)
    )
      unavailable()
    between(v.at, c.admitted_at, observed)
    return { ...v, next_question: next }
  }
  if (kind === 'fulfillment') {
    const v = exact(
        z
          .object({
            ...base,
            kind: z.literal(kind),
            child_binding: childBinding,
            receipt: linkedEffect,
            feedback_ref: feedbackRef.nullable(),
          })
          .strict(),
        raw,
      ),
      c = v.child_binding,
      r = v.receipt
    verifyChild(c)
    if (
      v.event_id !== `fulfillment/${b.command_id}/${c.command_id}` ||
      required(t.continuation).fulfilled_by !== c.command_id ||
      r.owner_id !== q.ownerId ||
      r.command_id !== c.command_id ||
      r.input_hash !== c.input_hash ||
      r.epoch !== q.epoch ||
      r.parent_command_id !== b.command_id ||
      r.parent_input_hash !== b.input_hash ||
      r.parent_decision_hash !== required(t.terminal_receipt).decision_hash ||
      r.provider_key !== `conversation.clarification/${q.ownerId}/${b.command_id}` ||
      v.at !== r.consumed_at ||
      getLocalDateString(r.timezone, new Date(r.consumed_at)) !== r.local_date ||
      (t.original_command.meal_type !== undefined && t.original_command.meal_type !== r.meal_type)
    )
      unavailable()
    between(v.at, c.admitted_at, observed)
    verifyRef(v.feedback_ref, r)
    return v
  }
  const v = exact(
      z
        .object({
          ...base,
          kind: z.literal('edit'),
          effect_binding: z.union([parentBinding, childBinding]),
          receipt: editEffect,
        })
        .strict(),
      raw,
    ),
    c = v.effect_binding,
    r = v.receipt
  if (c.command_protocol === 'conversation.clarification.v1') {
    verifyChild(c)
    if (required(t.continuation).fulfilled_by !== c.command_id) unavailable()
  } else if (!isDeepStrictEqual(c, b) || t.terminal_receipt !== null) unavailable()
  if (
    v.event_id !== `edit/${c.command_id}/${r.operation_id}` ||
    r.owner_id !== q.ownerId ||
    r.command_id !== c.command_id ||
    instant(v.at) !== instant(r.applied_at) ||
    r.removed_item_ids.some((id) => r.new_item_ids.includes(id))
  )
    unavailable()
  between(v.at, c.admitted_at, observed)
  if (r.kind === 'saved') {
    if (
      r.target_operation_id !== null ||
      !r.undo_expires_at ||
      instant(r.undo_expires_at) - instant(r.applied_at) !== 300000000000n ||
      r.removed_item_ids.length !== 1 ||
      r.new_item_ids.length === 0 ||
      r.next_record_id !== r.new_item_ids[0]
    )
      unavailable()
  } else {
    if (
      r.undo_expires_at !== null ||
      (r.kind === 'save_undone') !== (r.target_operation_id !== null) ||
      (r.kind === 'save_undone' ? r.new_item_ids.length !== 1 : r.new_item_ids.length !== 0) ||
      (r.kind === 'save_undone' &&
        (r.revision < 2 ||
          r.target_operation_id === r.operation_id ||
          r.next_record_id !== r.new_item_ids[0])) ||
      (r.kind === 'registration_undone' && (r.revision !== 1 || r.next_record_id !== null))
    )
      unavailable()
  }
  return v
}
export function parseConversationMealThreadPage(
  raw: unknown,
  expected: ConversationMealThreadQuery,
): ConversationMealThreadOutcome {
  try {
    const q = exact(conversationThreadQuerySchema, expected),
      copy = exact(z.unknown(), raw),
      refused = z
        .object({ action: z.enum(['absent', 'stale_epoch', 'cursor_conflict', 'event_conflict']) })
        .strict()
        .safeParse(copy)
    if (refused.success) return freezeConversationWriter(refused.data)
    const p = exact(
      z
        .object({
          action: z.literal('available'),
          schema: z.literal('conversation.journal-page-private.v2'),
          owner_id: uuid,
          epoch: uuid,
          observed_at: clock,
          threads: z.array(z.unknown()).max(25),
          items: z.array(z.unknown()).max(25),
          has_more: z.boolean(),
          next_cursor: conversationThreadCursorSchema.nullable(),
        })
        .strict(),
      copy,
    )
    if (p.owner_id !== q.ownerId || p.epoch !== q.epoch || p.items.length > q.limit) unavailable()
    const threads = p.threads.map((t) => descriptor(t, q, p.observed_at)),
      byId = new Map(threads.map((t) => [t.thread_id, t])),
      used = new Set<string>(),
      childParents = new Map<string, string>(),
      children = new Map<string, ConversationMealThreadChildBinding>(),
      idsSeen = new Set<string>()
    if (
      byId.size !== threads.length ||
      threads.some((t, i) => i > 0 && t.thread_id <= threads[i - 1].thread_id)
    )
      unavailable()
    let previous = q.cursor
    const items = p.items.map((rawItem) => {
      const ref = exact(z.object({ thread_id: uuid }).passthrough(), rawItem).thread_id,
        t = byId.get(ref)
      if (!t) return unavailable()
      const e = parseEvent(rawItem, t, q, p.observed_at)
      used.add(ref)
      if (idsSeen.has(e.event_id)) unavailable()
      idsSeen.add(e.event_id)
      between(e.at, t.parent_binding.admitted_at, p.observed_at)
      if (
        previous &&
        (instant(e.at) > instant(previous.at) ||
          (instant(e.at) === instant(previous.at) && e.event_id >= previous.id))
      )
        unavailable()
      previous = { at: e.at, id: e.event_id }
      const c =
        'child_binding' in e
          ? e.child_binding
          : e.kind === 'edit' &&
              e.effect_binding.command_protocol === 'conversation.clarification.v1'
            ? e.effect_binding
            : null
      if (c) {
        if (byId.has(c.command_id)) unavailable()
        if (childParents.has(c.command_id) && childParents.get(c.command_id) !== ref) unavailable()
        if (children.has(c.command_id) && !isDeepStrictEqual(children.get(c.command_id), c))
          unavailable()
        childParents.set(c.command_id, ref)
        children.set(c.command_id, c)
      }
      return e
    })
    if (used.size !== threads.length) unavailable()
    for (const e of items) {
      if (e.kind === 'fulfillment') {
        const prepared = items.find(
          (x) =>
            x.kind === 'reply_result' && x.child_binding.command_id === e.child_binding.command_id,
        )
        if (
          prepared &&
          (prepared.kind !== 'reply_result' ||
            prepared.status !== 'prepared' ||
            instant(prepared.at) > instant(e.at))
        )
          unavailable()
      }
      if (e.kind === 'reply_result') {
        const reply = items.find(
          (x) => x.kind === 'reply' && x.child_binding.command_id === e.child_binding.command_id,
        )
        if (
          reply?.kind === 'reply' &&
          e.next_question &&
          e.next_question.revision !== reply.body.expected_revision + 1
        )
          unavailable()
      }
    }
    const last = items.at(-1)
    if (
      p.has_more
        ? !last ||
          items.length !== q.limit ||
          !isDeepStrictEqual(p.next_cursor, { at: last.at, id: last.event_id })
        : p.next_cursor !== null
    )
      unavailable()
    return freezeConversationWriter({ ...p, threads, items })
  } catch {
    return unavailable()
  }
}
export function createSupabaseConversationMealThreadPageStore(
  db: ServiceClient,
): ConversationMealThreadPageStore {
  const rpc = db.rpc.bind(db)
  return Object.freeze({
    async read(raw: ConversationMealThreadQuery) {
      try {
        const q = exact(conversationThreadQuerySchema, raw),
          r = await rpc('read_conversation_meal_journal_page_v2', {
            p_user_id: q.ownerId,
            p_expected_epoch: q.epoch,
            p_limit: q.limit,
            p_cursor: q.cursor as Json | null,
          })
        if (r.error) return unavailable()
        return parseConversationMealThreadPage(r.data, q)
      } catch {
        return unavailable()
      }
    },
  })
}
