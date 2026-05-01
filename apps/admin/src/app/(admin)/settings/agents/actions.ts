'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

interface UpdateInput {
  id: string
  model: string
  temperature: number
  max_tokens: number
  wait_seconds: number
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

    const { error } = await svc
      .from('agent_configs')
      .update({
        model: input.model,
        temperature: input.temperature,
        max_tokens: input.max_tokens,
        wait_seconds: input.wait_seconds,
        updated_at: new Date().toISOString(),
      })
      .eq('id', input.id)
    if (error) return { error: error.message }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'config.update',
      entity: 'agent_configs',
      entity_id: input.id,
      before: before ? JSON.parse(JSON.stringify(before)) : null,
      after: JSON.parse(JSON.stringify(input)),
    })

    revalidatePath('/settings/agents')
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
