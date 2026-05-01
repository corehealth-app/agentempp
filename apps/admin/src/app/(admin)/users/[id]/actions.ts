'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function closeDay(userId: string, date: string) {
  try {
    const supabase = await createClient()
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return { error: 'Não autenticado' }

    const svc = createServiceClient()
    const { data: admin } = await svc
      .from('admin_users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle()
    if (!admin) return { error: 'Acesso negado' }

    const { data, error } = await svc.rpc('daily_close_user', {
      p_user_id: userId,
      p_date: date,
    })
    if (error) return { error: error.message }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'user.close_day',
      entity: 'daily_snapshots',
      entity_id: `${userId}:${date}`,
      after: data as Record<string, never>,
    })

    revalidatePath(`/users/${userId}`)
    return { ok: true, result: data as Record<string, unknown> }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
