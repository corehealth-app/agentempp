'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

interface SaveInput {
  id: string
  topic: string
  tipo: string
  content: string
  status: string
  display_order: number
  change_reason: string | null
}

async function requireEditor() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Não autenticado')
  const svc = createServiceClient()
  const { data: admin } = await svc
    .from('admin_users')
    .select('id, role, email')
    .eq('id', user.id)
    .maybeSingle()
  if (!admin || !['admin', 'editor'].includes(admin.role)) throw new Error('Acesso negado')
  return { user, admin }
}

export async function saveRule(input: SaveInput) {
  try {
    const { user, admin } = await requireEditor()

    // Apenas admin pode publicar (status='active')
    if (input.status === 'active' && admin.role !== 'admin') {
      return { error: 'Apenas admin pode publicar regras' }
    }

    const svc = createServiceClient()
    const tokenEstimate = Math.ceil(input.content.length / 4)

    const { error } = await svc
      .from('agent_rules')
      .update({
        topic: input.topic,
        tipo: input.tipo as 'regras_gerais',
        content: input.content,
        status: input.status as 'active',
        display_order: input.display_order,
        token_estimate: tokenEstimate,
        updated_by: user.id,
        updated_at: new Date().toISOString(),
      })
      .eq('id', input.id)
    if (error) return { error: error.message }

    // Atualiza a versão criada pelo trigger com o change_reason
    if (input.change_reason) {
      const { data: latest } = await svc
        .from('agent_rules_versions')
        .select('id')
        .eq('rule_id', input.id)
        .order('version_num', { ascending: false })
        .limit(1)
        .maybeSingle()

      if (latest) {
        await svc
          .from('agent_rules_versions')
          .update({ change_reason: input.change_reason })
          .eq('id', latest.id)
      }
    }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'rule.update',
      entity: 'agent_rules',
      entity_id: input.id,
      after: { topic: input.topic, status: input.status, change_reason: input.change_reason },
    })

    revalidatePath('/prompts')
    revalidatePath(`/prompts/${input.id}`)
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

export async function deleteRule(id: string) {
  try {
    const { user, admin } = await requireEditor()
    if (admin.role !== 'admin') return { error: 'Apenas admin pode apagar' }

    const svc = createServiceClient()
    const { error } = await svc.from('agent_rules').delete().eq('id', id)
    if (error) return { error: error.message }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'rule.delete',
      entity: 'agent_rules',
      entity_id: id,
    })

    revalidatePath('/prompts')
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
