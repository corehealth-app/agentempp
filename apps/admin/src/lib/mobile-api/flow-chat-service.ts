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

export async function sendFlowMessage(
  dependencies: FlowChatDependencies,
  input: SendFlowMessageInput,
) {
  const assistantProviderId = `${input.idempotencyKey}:assistant`
  const existing = await dependencies.store.findAssistant(input.userId, assistantProviderId)
  if (existing) {
    await dependencies.store.completeInbound(input.userId, input.idempotencyKey)
    return { conversation_id: 'flow' as const, message: dto(existing) }
  }

  const existingInbound = await dependencies.store.findInbound(input.userId, input.idempotencyKey)
  if (existingInbound) {
    await dependencies.store.retryInbound(input.userId, input.idempotencyKey, input.requestId)
  } else {
    const since = new Date(input.now.getTime() - 60_000).toISOString()
    if ((await dependencies.store.countRecentInbound(input.userId, since)) >= 10) {
      throw new MobileApiError(429, 'flow_rate_limited', 'Please wait before sending again')
    }

    const createdAt = input.now.toISOString()
    await dependencies.store.insertInbound({
      userId: input.userId,
      content: input.text,
      providerMessageId: input.idempotencyKey,
      requestId: input.requestId,
      state: 'processing',
      createdAt,
    })
  }

  try {
    const reply = await dependencies.agent.reply({
      userId: input.userId,
      providerMessageId: input.idempotencyKey,
      text: input.text,
      timestamp: input.now,
    })
    const assistant = await dependencies.store.insertAssistant({
      userId: input.userId,
      content: reply.text,
      providerMessageId: assistantProviderId,
      requestId: input.requestId,
      state: 'completed',
      createdAt: new Date().toISOString(),
      metadata: reply.metadata,
    })
    await dependencies.store.completeInbound(input.userId, input.idempotencyKey)
    return { conversation_id: 'flow' as const, message: dto(assistant) }
  } catch {
    await dependencies.store.failInbound(input.userId, input.idempotencyKey).catch(() => undefined)
    throw new MobileApiError(502, 'flow_provider_failed', 'Flow is temporarily unavailable')
  }
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
      if (error || !data) throw new Error('Unable to persist Flow input')
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
      if (error || !data) throw new Error('Unable to persist Flow output')
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
