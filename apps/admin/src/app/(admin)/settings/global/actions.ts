'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function updateGlobalConfig(key: string, value: unknown) {
  try {
    const supabase = await createClient()
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return { error: 'Não autenticado' }

    const svc = createServiceClient()
    const { data: admin } = await svc
      .from('admin_users')
      .select('id, role')
      .eq('id', user.id)
      .maybeSingle()
    if (!admin || admin.role !== 'admin') return { error: 'Acesso negado' }

    const { error } = await (svc as unknown as {
      rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
    }).rpc('set_global_config', { p_key: key, p_value: value })
    if (error) {
      const msg = (error as { message?: string }).message ?? String(error)
      return { error: msg }
    }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'global_config.update',
      entity: 'global_config',
      entity_id: key,
      after: { key, value: JSON.parse(JSON.stringify(value)) },
    })

    revalidatePath('/settings/global')
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
