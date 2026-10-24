import { createHash } from 'node:crypto'
import {
  FLOW_CURATED_PHRASE_CATALOG,
  type FlowStatusPhraseCursor,
  type FlowStatusPhraseReceipt,
} from '@mpp/agent/flow-curated-phrases'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { StoredFlowMessage } from './flow-chat-service'

export interface FlowPhraseEventIdentity {
  userId: string
  eventKey: string
  inboundId: string
  inboundProviderMessageId: string
  assistantProviderMessageId: string
  expectedInboundContent: string
}
export interface FlowPhraseCursorSnapshot {
  anchorAssistantId: string | null
  cursorRevision: string
  cursor: FlowStatusPhraseCursor | null
}
export interface FlowPhraseReplyCommit extends FlowPhraseEventIdentity {
  expectedRequestId: string
  expectedAttemptStartedAt: string
  expectedAnchorAssistantId: string | null
  expectedCursorRevision: string
  expectedCursor: FlowStatusPhraseCursor | null
  nextCursor: FlowStatusPhraseCursor
  receipt: FlowStatusPhraseReceipt
  content: string
  createdAt: string
  metadata: {
    stage: string
    modelUsed: 'none'
    promptTokens: 0
    completionTokens: 0
    costUsd: 0
    latencyMs: number
  }
}
export type FlowPhraseEventReply =
  | { kind: 'c5'; message: StoredFlowMessage; receipt: FlowStatusPhraseReceipt }
  | { kind: 'legacy'; message: StoredFlowMessage }
export type FlowPhraseReplyCommitResult =
  | { action: 'committed' | 'replay'; message: StoredFlowMessage }
  | { action: 'cursor_conflict' | 'attempt_conflict' | 'event_conflict' }
export interface FlowPhraseOwnedAttempt {
  userId: string
  inboundId: string
  inboundProviderMessageId: string
  expectedRequestId: string
  expectedAttemptStartedAt: string
  errorCode: string
}
export interface FlowPhraseReplyStore {
  loadEventReply(input: FlowPhraseEventIdentity): Promise<FlowPhraseEventReply | null>
  loadCursor(userId: string): Promise<FlowPhraseCursorSnapshot>
  commitReply(input: FlowPhraseReplyCommit): Promise<FlowPhraseReplyCommitResult>
  failOwnedAttempt(input: FlowPhraseOwnedAttempt): Promise<boolean>
}

const uuid = z.string().regex(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const nonempty = z.string().refine((value) => value.trim().length > 0)
const revision = z
  .string()
  .regex(/^(0|[1-9][0-9]*)$/u)
  .refine((value) => value.length <= 19 && BigInt(value) <= 9223372036854775807n)
const cursorSchema = z
  .object({
    schema: z.literal('flow.phrase-state.v1'),
    userId: uuid,
    catalogVersion: z.literal(FLOW_CURATED_PHRASE_CATALOG.version),
    ordinal: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
    lastTextKey: hash.nullable(),
    usedTextKeys: z.array(hash),
  })
  .strict()
const selectionSchema = z
  .object({
    phrase: nonempty.nullable(),
    phraseId: z
      .string()
      .regex(/^engagement:[0-9]{3}$/u)
      .nullable(),
    sourceText: nonempty.nullable(),
    foodCanonicalName: z.null(),
    reason: z.enum([
      'selected_incentive',
      'unsupported_language',
      'no_eligible_phrase',
      'only_previous_phrase',
      'rotation_exhausted',
    ]),
  })
  .strict()
const receiptSchema = z
  .object({
    eventKey: nonempty,
    requestFingerprint: hash,
    selection: selectionSchema,
  })
  .strict()
const namespaceSchema = z
  .object({
    schema: z.literal('flow.phrase-store.v1'),
    cursor_revision: revision.refine((value) => value !== '0'),
    previous_anchor_assistant_id: uuid.nullable(),
    cursor: cursorSchema,
    receipt: receiptSchema,
  })
  .strict()
const coreRowSchema = z.object({
  id: uuid,
  direction: z.literal('out'),
  content: nonempty,
  delivery_status: z.literal('completed'),
  raw_payload: z.unknown(),
  created_at: z.string().refine((value) => Number.isFinite(Date.parse(value))),
})
const rowSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    provider: z.literal('mobile_flow'),
    provider_message_id: nonempty,
    direction: z.enum(['in', 'out']),
    role: z.enum(['user', 'assistant']),
    content_type: z.literal('text'),
    content: z.string(),
    delivery_status: z.enum(['processing', 'completed', 'failed']),
    raw_payload: z.unknown(),
    created_at: z.string().refine((value) => Number.isFinite(Date.parse(value))),
  })
  .strict()
const columns =
  'id,user_id,provider,provider_message_id,direction,role,content_type,content,delivery_status,raw_payload,created_at'

function corrupt(): never {
  throw new Error('Invalid private Flow phrase reply')
}
function parseCursor(value: unknown, userId: string): FlowStatusPhraseCursor {
  const cursor = cursorSchema.parse(value)
  if (
    cursor.userId !== userId ||
    new Set(cursor.usedTextKeys).size !== cursor.usedTextKeys.length ||
    cursor.usedTextKeys.length > cursor.ordinal ||
    (cursor.ordinal === 0
      ? cursor.lastTextKey !== null || cursor.usedTextKeys.length !== 0
      : cursor.lastTextKey === null || cursor.usedTextKeys.at(-1) !== cursor.lastTextKey)
  )
    corrupt()
  return cursor
}
function validateIdentity(input: FlowPhraseEventIdentity, allowLegacyReply = false): void {
  uuid.parse(input.userId)
  uuid.parse(input.inboundId)
  const prefix = `mobile_flow/${input.userId}/`
  const bareKey = input.eventKey.slice(prefix.length)
  if (
    !input.eventKey.startsWith(prefix) ||
    !/^[A-Za-z0-9._:-]{8,128}$/u.test(bareKey) ||
    ![input.eventKey, bareKey].includes(input.inboundProviderMessageId) ||
    (input.assistantProviderMessageId !== `${input.eventKey}/assistant` &&
      !(
        allowLegacyReply &&
        input.inboundProviderMessageId === bareKey &&
        input.assistantProviderMessageId === `${bareKey}:assistant`
      ))
  )
    corrupt()
}
function parseNamespace(value: unknown, input: FlowPhraseEventIdentity, content: string) {
  const namespace = namespaceSchema.parse(value)
  const cursor = parseCursor(namespace.cursor, input.userId)
  const { receipt } = namespace
  const { selection } = receipt
  if (
    receipt.eventKey !== input.eventKey ||
    (namespace.cursor_revision === '1') !== (namespace.previous_anchor_assistant_id === null)
  )
    corrupt()
  if (selection.phrase === null) {
    if (
      selection.phraseId !== null ||
      selection.sourceText !== null ||
      selection.reason === 'selected_incentive' ||
      (selection.reason === 'rotation_exhausted') !== (cursor.ordinal === Number.MAX_SAFE_INTEGER)
    )
      corrupt()
  } else if (
    selection.phraseId === null ||
    selection.sourceText === null ||
    selection.reason !== 'selected_incentive' ||
    cursor.ordinal === 0 ||
    !content.endsWith(selection.phrase) ||
    createHash('sha256').update(selection.phrase).digest('hex') !== cursor.lastTextKey
  )
    corrupt()
  return namespace
}
function parseMessage(
  value: unknown,
  input: FlowPhraseEventIdentity,
  requireC5: boolean,
): FlowPhraseEventReply {
  const row = coreRowSchema.parse(value)
  // Legacy mapping tolerated non-object raw values. They are not C5 proof.
  const raw =
    row.raw_payload !== null &&
    typeof row.raw_payload === 'object' &&
    !Array.isArray(row.raw_payload)
      ? z.record(z.unknown()).parse(row.raw_payload)
      : {}
  const message: StoredFlowMessage = {
    id: row.id,
    role: 'assistant',
    content: row.content,
    state: 'completed',
    requestId: typeof raw.request_id === 'string' ? raw.request_id : 'request-unavailable',
    createdAt: row.created_at,
  }
  if (!Object.hasOwn(raw, 'flow_phrase_v1')) {
    if (requireC5) corrupt()
    return { kind: 'legacy', message }
  }
  if (
    input.assistantProviderMessageId !== `${input.eventKey}/assistant` ||
    typeof raw.request_id !== 'string' ||
    raw.conversation_id !== 'flow'
  )
    corrupt()
  const { receipt } = parseNamespace(raw.flow_phrase_v1, input, row.content)
  return { kind: 'c5', message, receipt }
}

/** Stateless trusted-backend adapter. Constructing it never reads or advances C5. */
export function createSupabaseFlowPhraseReplyStore(supabase: ServiceClient): FlowPhraseReplyStore {
  return {
    async loadEventReply(input) {
      validateIdentity(input, true)
      const find = (direction: 'in' | 'out', key: string) =>
        supabase
          .from('messages')
          .select(columns)
          .eq('user_id', input.userId)
          .eq('provider', 'mobile_flow')
          .eq('direction', direction)
          .eq('provider_message_id', key)
          .maybeSingle()
      const [inside, outside] = await Promise.all([
        find('in', input.inboundProviderMessageId),
        find('out', input.assistantProviderMessageId),
      ])
      if (inside.error || outside.error) throw new Error('Unable to read Flow phrase event')
      if (inside.data !== null) {
        const row = rowSchema.parse(inside.data)
        if (
          row.id !== input.inboundId ||
          row.user_id !== input.userId ||
          row.direction !== 'in' ||
          row.role !== 'user' ||
          row.provider_message_id !== input.inboundProviderMessageId ||
          row.content !== input.expectedInboundContent
        )
          corrupt()
      }
      if (outside.data === null) return null
      if (inside.data === null) corrupt()
      const row = rowSchema.parse(outside.data)
      if (
        row.user_id !== input.userId ||
        row.direction !== 'out' ||
        row.role !== 'assistant' ||
        row.provider_message_id !== input.assistantProviderMessageId
      )
        corrupt()
      return parseMessage(row, input, false)
    },
    async loadCursor(userId) {
      uuid.parse(userId)
      const { data, error } = await supabase.rpc('read_flow_shared_phrase_cursor', {
        p_user_id: userId,
      })
      if (error) throw new Error('Unable to read Flow phrase cursor')
      const snapshot = z
        .object({
          schema: z.literal('flow.shared-phrase-snapshot.v1'),
          mode: z.enum(['legacy', 'shared']),
          legacy_cursor_revision: revision,
          anchor_assistant_id: uuid.nullable(),
          cursor_revision: revision,
          cursor: z.unknown(),
        })
        .strict()
        .parse(data)
      // Chat witness, common CAS revision and phrase ordinal have different meanings.
      // A registration may be the first common event without inventing a Flow OUT.
      if (
        (snapshot.legacy_cursor_revision === '0') !== (snapshot.anchor_assistant_id === null) ||
        (snapshot.mode === 'legacy'
          ? snapshot.cursor_revision !== snapshot.legacy_cursor_revision
          : snapshot.cursor_revision === '0' ||
            BigInt(snapshot.cursor_revision) < BigInt(snapshot.legacy_cursor_revision))
      )
        corrupt()
      if (snapshot.mode === 'legacy' && snapshot.cursor_revision === '0') {
        if (snapshot.cursor !== null) corrupt()
        return { anchorAssistantId: null, cursorRevision: '0', cursor: null }
      }
      return {
        anchorAssistantId: snapshot.anchor_assistant_id,
        cursorRevision: snapshot.cursor_revision,
        cursor: parseCursor(snapshot.cursor, userId),
      }
    },
    async commitReply(input) {
      validateIdentity(input)
      const jsonCursor = (cursor: FlowStatusPhraseCursor | null) =>
        cursor === null ? null : { ...cursor, usedTextKeys: [...cursor.usedTextKeys] }
      const { data, error } = await supabase.rpc('commit_flow_shared_phrase_reply', {
        p_user_id: input.userId,
        p_event_key: input.eventKey,
        p_expected_inbound_id: input.inboundId,
        p_inbound_provider_message_id: input.inboundProviderMessageId,
        p_assistant_provider_message_id: input.assistantProviderMessageId,
        p_expected_inbound_content: input.expectedInboundContent,
        p_expected_request_id: input.expectedRequestId,
        p_expected_attempt_started_at: input.expectedAttemptStartedAt,
        p_expected_anchor_assistant_id: input.expectedAnchorAssistantId,
        p_expected_cursor_revision: input.expectedCursorRevision,
        p_expected_cursor: jsonCursor(input.expectedCursor),
        p_next_cursor: jsonCursor(input.nextCursor),
        p_receipt: { ...input.receipt, selection: { ...input.receipt.selection } },
        p_content: input.content,
        p_created_at: input.createdAt,
        p_metadata: { ...input.metadata },
      })
      if (error) throw new Error('Unable to commit Flow phrase reply')
      const result = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('committed'), message: coreRowSchema.strict() }).strict(),
          z.object({ action: z.literal('replay'), message: coreRowSchema.strict() }).strict(),
          z.object({ action: z.literal('cursor_conflict') }).strict(),
          z.object({ action: z.literal('attempt_conflict') }).strict(),
          z.object({ action: z.literal('event_conflict') }).strict(),
        ])
        .parse(data)
      if (result.action === 'committed' || result.action === 'replay') {
        const message = parseMessage(result.message, input, true).message
        if (
          result.action === 'committed' &&
          (message.requestId !== input.expectedRequestId || message.content !== input.content)
        )
          corrupt()
        return { action: result.action, message }
      }
      return result
    },
    async failOwnedAttempt(input) {
      const { data, error } = await supabase
        .from('messages')
        .update({
          delivery_status: 'failed',
          delivery_error: { code: input.errorCode },
        })
        .eq('id', input.inboundId)
        .eq('user_id', input.userId)
        .eq('provider', 'mobile_flow')
        .eq('direction', 'in')
        .eq('provider_message_id', input.inboundProviderMessageId)
        .eq('delivery_status', 'processing')
        .eq('raw_payload->>request_id', input.expectedRequestId)
        .eq('raw_payload->>attempt_started_at', input.expectedAttemptStartedAt)
        .select('id')
      if (error) throw new Error('Unable to fail owned Flow phrase attempt')
      const changed = z
        .array(z.object({ id: uuid }).strict())
        .max(1)
        .parse(data)
      if (changed.length === 1 && changed[0].id !== input.inboundId) corrupt()
      return changed.length === 1
    },
  }
}
