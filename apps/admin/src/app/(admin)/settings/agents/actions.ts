'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

interface UpdateInput {
  id: string
  model: string
  temperature: number
  top_p?: number | null
  frequency_penalty?: number
  presence_penalty?: number
  max_tokens: number
  wait_seconds: number
  max_tool_iterations?: number
  buffer_debounce_ms?: number
  llm_timeout_ms?: number
  vision_timeout_ms?: number
  stt_timeout_ms?: number
  allowed_tools?: string[] | null
  helicone_cache?: boolean
  streaming?: boolean
}

export async function updateAgentConfig(input: UpdateInput) {
  try {
    const supabase = await createClient()
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return { error: 'Não autenticado' }

    const svc = createServiceClient()
    const { data: admin } = await svc
      .from('admin_users')
      .select('id, role, email')
      .eq('id', user.id)
      .maybeSingle()
    if (!admin || admin.role !== 'admin') return { error: 'Acesso negado' }

    const { data: before } = await svc
      .from('agent_configs')
      .select('*')
      .eq('id', input.id)
      .single()

    const updates: Record<string, unknown> = {
      model: input.model,
      temperature: input.temperature,
      max_tokens: input.max_tokens,
      wait_seconds: input.wait_seconds,
      updated_at: new Date().toISOString(),
    }
    if (input.top_p !== undefined) updates.top_p = input.top_p
    if (input.frequency_penalty !== undefined) updates.frequency_penalty = input.frequency_penalty
    if (input.presence_penalty !== undefined) updates.presence_penalty = input.presence_penalty
    if (input.max_tool_iterations !== undefined)
      updates.max_tool_iterations = input.max_tool_iterations
    if (input.buffer_debounce_ms !== undefined)
      updates.buffer_debounce_ms = input.buffer_debounce_ms
    if (input.llm_timeout_ms !== undefined) updates.llm_timeout_ms = input.llm_timeout_ms
    if (input.vision_timeout_ms !== undefined) updates.vision_timeout_ms = input.vision_timeout_ms
    if (input.stt_timeout_ms !== undefined) updates.stt_timeout_ms = input.stt_timeout_ms
    if (input.allowed_tools !== undefined) updates.allowed_tools = input.allowed_tools
    if (input.helicone_cache !== undefined) updates.helicone_cache = input.helicone_cache
    if (input.streaming !== undefined) updates.streaming = input.streaming

    const { error } = await (svc as unknown as {
      from: (t: string) => {
        update: (u: Record<string, unknown>) => {
          eq: (col: string, val: string) => Promise<{ error: { message: string } | null }>
        }
      }
    })
      .from('agent_configs')
      .update(updates)
      .eq('id', input.id)
    if (error) return { error: error.message }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'config.update',
      entity: 'agent_configs',
      entity_id: input.id,
      before: before ? JSON.parse(JSON.stringify(before)) : null,
      after: JSON.parse(JSON.stringify(updates)),
    })

    revalidatePath('/settings/agents')
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
