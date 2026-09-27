import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'

export type FlowMessageRole = 'user' | 'assistant'
export type FlowMessageState = 'processing' | 'completed' | 'failed'

export interface StoredFlowMessage {
  id: string
  role: FlowMessageRole
  content: string
  state: FlowMessageState
  requestId: string
  createdAt: string
}

interface NewFlowMessage {
  userId: string
  content: string
  providerMessageId: string
  requestId: string
  state: FlowMessageState
  createdAt: string
  metadata?: Record<string, unknown>
}

export interface FlowChatStore {
  loadHistory(userId: string, limit: number): Promise<StoredFlowMessage[]>
  countRecentInbound(userId: string, since: string): Promise<number>
  findInbound(userId: string, providerMessageId: string): Promise<StoredFlowMessage | null>
  findAssistant(userId: string, providerMessageId: string): Promise<StoredFlowMessage | null>
  insertInbound(input: NewFlowMessage): Promise<StoredFlowMessage>
  retryInbound(userId: string, providerMessageId: string, requestId: string): Promise<void>
  insertAssistant(input: NewFlowMessage): Promise<StoredFlowMessage>
  completeInbound(userId: string, providerMessageId: string): Promise<void>
  failInbound(userId: string, providerMessageId: string): Promise<void>
}

export interface FlowAgent {
  reply(input: {
    userId: string
    providerMessageId: string
    text: string
    timestamp: Date
  }): Promise<{ text: string; metadata: Record<string, unknown> }>
}

export interface FlowChatDependencies {
  store: FlowChatStore
  agent: FlowAgent
}

export interface SendFlowMessageInput {
  userId: string
  text: string
  idempotencyKey: string
  requestId: string
  now: Date
}

export interface FlowMessageDTO {
  id: string
  conversation_id: 'flow'
  role: FlowMessageRole
  content: string
  state: FlowMessageState
  request_id: string
  created_at: string
}

function dto(message: StoredFlowMessage): FlowMessageDTO {
  return {
    id: message.id,
    conversation_id: 'flow',
    role: message.role,
    content: message.content,
    state: message.state,
    request_id: message.requestId,
    created_at: message.createdAt,
  }
}

export async function loadFlowHistory(
  dependencies: FlowChatDependencies,
  userId: string,
  limit: number,
) {
  const rows = await dependencies.store.loadHistory(userId, limit)
  return {
    conversation_id: 'flow' as const,
    messages: rows
      .slice()
      .sort((left, right) => left.createdAt.localeCompare(right.createdAt))
      .map(dto),
  }
}

/**
 * `messages(provider, provider_message_id)` is unique across ALL users, while
 * an Idempotency-Key is only unique per user. The stored id therefore carries
 * the authenticated user (never a payload value). "/" is not allowed in an
 * Idempotency-Key, so a scoped id can never equal a legacy row's bare key.
 */
export function scopedFlowProviderMessageId(userId: string, idempotencyKey: string): string {
  return `mobile_flow/${userId}/${idempotencyKey}`
}

/**
 * Every reply is written as "<scoped inbound>/assistant" ("/" is also outside
 * the key charset), so no key — e.g. "x:assistant", or another user's legacy
 * row — can ever name it. A legacy turn's earlier reply, if any, is still read
 * from its original "<key>:assistant".
 */
function scopedReplyProviderMessageId(userId: string, idempotencyKey: string): string {
  return `${scopedFlowProviderMessageId(userId, idempotencyKey)}/assistant`
}

/** The row being inserted already exists (unique index on the provider id). */
export class FlowMessageAlreadyStoredError extends Error {
  constructor() {
    super('Flow message already stored')
    this.name = 'FlowMessageAlreadyStoredError'
  }
}

export async function sendFlowMessage(
  dependencies: FlowChatDependencies,
  input: SendFlowMessageInput,
) {
  // The inbound this key already created: a scoped row, or a legacy
  // (pre-scoping) row that used the bare key. Both lookups are pinned to the
  // authenticated user, so another user's rows are never read.
  let inboundProviderId = scopedFlowProviderMessageId(input.userId, input.idempotencyKey)
  let legacyTurn = false
  let existingInbound = await dependencies.store.findInbound(input.userId, inboundProviderId)
  if (!existingInbound) {
    const legacyInbound = await dependencies.store.findInbound(input.userId, input.idempotencyKey)
    if (legacyInbound) {
      existingInbound = legacyInbound
      inboundProviderId = input.idempotencyKey
      legacyTurn = true
    }
  }
  // Same key, different text: a new request under a used key, never a replay.
  if (existingInbound && existingInbound.content !== input.text) {
    throw new MobileApiError(
      409,
      'idempotency_key_conflict',
      'Idempotency-Key was already used with a different message',
    )
  }

  const assistantProviderId = scopedReplyProviderMessageId(input.userId, input.idempotencyKey)
  const existing =
    (await dependencies.store.findAssistant(input.userId, assistantProviderId)) ??
    (legacyTurn
      ? await dependencies.store.findAssistant(input.userId, `${input.idempotencyKey}:assistant`)
      : null)
  if (existing) {
    await dependencies.store.completeInbound(input.userId, inboundProviderId)
    return { conversation_id: 'flow' as const, message: dto(existing) }
  }

  if (existingInbound) {
    await dependencies.store.retryInbound(input.userId, inboundProviderId, input.requestId)
  } else {
    const since = new Date(input.now.getTime() - 60_000).toISOString()
    if ((await dependencies.store.countRecentInbound(input.userId, since)) >= 10) {
      throw new MobileApiError(429, 'flow_rate_limited', 'Please wait before sending again')
    }

    const createdAt = input.now.toISOString()
    try {
      await dependencies.store.insertInbound({
        userId: input.userId,
        content: input.text,
        providerMessageId: inboundProviderId,
        requestId: input.requestId,
        state: 'processing',
        createdAt,
      })
    } catch (error) {
      // The same turn was stored by a concurrent request; Flow is not called.
      if (error instanceof FlowMessageAlreadyStoredError) {
        throw new MobileApiError(
          409,
          'idempotency_request_in_progress',
          'The same request is already being processed',
        )
      }
      throw error
    }
  }

  const failTurn = async () => {
    await dependencies.store.failInbound(input.userId, inboundProviderId).catch(() => undefined)
    return new MobileApiError(502, 'flow_provider_failed', 'Flow is temporarily unavailable')
  }

  let reply: Awaited<ReturnType<FlowAgent['reply']>>
  try {
    reply = await dependencies.agent.reply({
      userId: input.userId,
      // The stored id, so the agent excludes this turn from its own history.
      providerMessageId: inboundProviderId,
      text: input.text,
      timestamp: input.now,
    })
  } catch {
    throw await failTurn()
  }

  let assistant: StoredFlowMessage
  try {
    assistant = await dependencies.store.insertAssistant({
      userId: input.userId,
      content: reply.text,
      providerMessageId: assistantProviderId,
      requestId: input.requestId,
      state: 'completed',
      createdAt: new Date().toISOString(),
      metadata: reply.metadata,
    })
  } catch (error) {
    // This turn's reply is already stored: replay it. Anything else fails the
    // turn, so the inbound never stays "processing".
    if (error instanceof FlowMessageAlreadyStoredError) {
      const stored = await dependencies.store
        .findAssistant(input.userId, assistantProviderId)
        .catch(() => null)
      if (stored) {
        await dependencies.store.completeInbound(input.userId, inboundProviderId)
        return { conversation_id: 'flow' as const, message: dto(stored) }
      }
    }
    throw await failTurn()
  }

  try {
    await dependencies.store.completeInbound(input.userId, inboundProviderId)
  } catch {
    throw await failTurn()
  }
  return { conversation_id: 'flow' as const, message: dto(assistant) }
}

/** 23505 on the messages unique index: this exact provider id is stored. */
function persistError(error: { code?: string } | null, message: string): Error {
  if (error?.code === '23505') return new FlowMessageAlreadyStoredError()
  return new Error(message)
}

type MessageRow = {
  id: string
  direction: string
  content: string | null
  delivery_status: string | null
  raw_payload: unknown
  created_at: string
}

function mapRow(row: MessageRow): StoredFlowMessage {
  const raw =
    row.raw_payload && typeof row.raw_payload === 'object'
      ? (row.raw_payload as Record<string, unknown>)
      : {}
  const state =
    row.delivery_status === 'processing' || row.delivery_status === 'failed'
      ? row.delivery_status
      : 'completed'
  return {
    id: row.id,
    role: row.direction === 'in' ? 'user' : 'assistant',
    content: row.content ?? '',
    state,
    requestId: typeof raw.request_id === 'string' ? raw.request_id : 'request-unavailable',
    createdAt: row.created_at,
  }
}

export function createSupabaseFlowChatStore(supabase: ServiceClient): FlowChatStore {
  const columns = 'id, direction, content, delivery_status, raw_payload, created_at'
  return {
    async loadHistory(userId, limit) {
      const { data, error } = await supabase
        .from('messages')
        .select(columns)
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .order('created_at', { ascending: false })
        .limit(limit)
      if (error) throw new Error('Unable to load Flow history')
      return ((data ?? []) as MessageRow[]).map(mapRow)
    },
    async countRecentInbound(userId, since) {
      const { count, error } = await supabase
        .from('messages')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('direction', 'in')
        .gte('created_at', since)
      if (error) throw new Error('Unable to enforce Flow rate limit')
      return count ?? 0
    },
    async findAssistant(userId, providerMessageId) {
      const { data, error } = await supabase
        .from('messages')
        .select(columns)
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'out')
        .maybeSingle()
      if (error) throw new Error('Unable to verify Flow replay')
      return data ? mapRow(data as MessageRow) : null
    },
    async findInbound(userId, providerMessageId) {
      const { data, error } = await supabase
        .from('messages')
        .select(columns)
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
        .maybeSingle()
      if (error) throw new Error('Unable to verify Flow input replay')
      return data ? mapRow(data as MessageRow) : null
    },
    async insertInbound(input) {
      const { data, error } = await supabase
        .from('messages')
        .insert({
          user_id: input.userId,
          direction: 'in',
          role: 'user',
          content_type: 'text',
          content: input.content,
          provider: 'mobile_flow',
          provider_message_id: input.providerMessageId,
          raw_payload: { request_id: input.requestId, conversation_id: 'flow' },
          delivery_status: input.state,
          created_at: input.createdAt,
        })
        .select(columns)
        .single()
      if (error || !data) throw persistError(error, 'Unable to persist Flow input')
      return mapRow(data as MessageRow)
    },
    async insertAssistant(input) {
      const metadata = input.metadata ?? {}
      const stringMetadata = (key: string) =>
        typeof metadata[key] === 'string' ? (metadata[key] as string) : null
      const numberMetadata = (key: string) =>
        typeof metadata[key] === 'number' ? (metadata[key] as number) : null
      const { data, error } = await supabase
        .from('messages')
        .insert({
          user_id: input.userId,
          direction: 'out',
          role: 'assistant',
          content_type: 'text',
          content: input.content,
          provider: 'mobile_flow',
          provider_message_id: input.providerMessageId,
          raw_payload: { request_id: input.requestId, conversation_id: 'flow' },
          delivery_status: input.state,
          agent_stage: stringMetadata('stage'),
          model_used: stringMetadata('modelUsed'),
          prompt_tokens: numberMetadata('promptTokens'),
          completion_tokens: numberMetadata('completionTokens'),
          cost_usd: numberMetadata('costUsd'),
          latency_ms: numberMetadata('latencyMs'),
          created_at: input.createdAt,
        })
        .select(columns)
        .single()
      if (error || !data) throw persistError(error, 'Unable to persist Flow output')
      return mapRow(data as MessageRow)
    },
    async retryInbound(userId, providerMessageId, requestId) {
      const { error } = await supabase
        .from('messages')
        .update({
          delivery_status: 'processing',
          delivery_error: null,
          raw_payload: { request_id: requestId, conversation_id: 'flow' },
        })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
      if (error) throw new Error('Unable to retry Flow input')
    },
    async completeInbound(userId, providerMessageId) {
      const { error } = await supabase
        .from('messages')
        .update({ delivery_status: 'completed' })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
      if (error) throw new Error('Unable to complete Flow input')
    },
    async failInbound(userId, providerMessageId) {
      const { error } = await supabase
        .from('messages')
        .update({ delivery_status: 'failed', delivery_error: { code: 'flow_provider_failed' } })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
      if (error) throw new Error('Unable to mark Flow input failed')
    },
  }
}
