'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

/**
 * Marca country_confirmed=true (e atualiza country se vier diferente).
 * Útil quando o paciente já interagiu múltiplas vezes mas o LLM nunca
 * chamou a tool confirma_pais_residencia — admin destrava manualmente.
 */
export async function confirmCountryAction(userId: string, country: string) {
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
    if (!admin) return { error: 'Acesso negado' }

    const iso = country.trim().toUpperCase()
    if (!/^[A-Z]{2}$/.test(iso)) return { error: 'país deve ser ISO alpha-2 (BR, US, …)' }

    const { data: before } = await svc
      .from('users')
      .select('country, country_confirmed')
      .eq('id', userId)
      .maybeSingle()

    const { error } = await (svc as unknown as {
      from: (t: string) => {
        update: (u: Record<string, unknown>) => {
          eq: (col: string, val: string) => Promise<{ error: { message: string } | null }>
        }
      }
    })
      .from('users')
      .update({
        country: iso,
        country_confirmed: true,
        updated_at: new Date().toISOString(),
      })
      .eq('id', userId)
    if (error) return { error: error.message }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'user.confirm_country',
      entity: 'users',
      entity_id: userId,
      before: before ?? {},
      after: { country: iso, country_confirmed: true },
    })

    revalidatePath(`/users/${userId}`)
    revalidatePath('/messages')
    return { ok: true, country: iso }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

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

    // daily_close_user SQL function foi removida na migration de auditoria.
    // Lógica 100% migrada pro Inngest worker daily-closer (TS).
    // Aqui marcamos snapshot como fechado e disparamos evento pro worker.
    const { error: closeErr } = await (svc as unknown as {
      from: (t: string) => {
        update: (u: Record<string, unknown>) => {
          eq: (col: string, val: string) => {
            eq: (col: string, val: string) => Promise<{ error: { message: string } | null }>
          }
        }
      }
    })
      .from('daily_snapshots')
      .update({ day_closed: true, closed_at: new Date().toISOString() })
      .eq('user_id', userId)
      .eq('date', date)
    if (closeErr) return { error: closeErr.message }

    // Dispara evento Inngest pra recalcular user_progress (XP/streak/blocks)
    await (svc as unknown as {
      rpc: (
        n: string,
        p: Record<string, unknown>,
      ) => Promise<{ error: { message?: string } | null }>
    })
      .rpc('dispatch_inngest_event', {
        p_event_name: 'day.close.tick',
        p_data: { hour: 99, fired_at: new Date().toISOString(), force_user_id: userId },
      })
      .catch(() => {
        // best-effort; admin já marcou snapshot como fechado
      })

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'user.close_day',
      entity: 'daily_snapshots',
      entity_id: `${userId}:${date}`,
      after: { closed_at: new Date().toISOString(), date },
    })

    revalidatePath(`/users/${userId}`)
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
