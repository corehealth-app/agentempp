'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

async function requireAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { error: 'unauthenticated' as const }

  const svc = createServiceClient()
  const { data: admin } = await svc
    .from('admin_users')
    .select('id, role, email')
    .eq('id', user.id)
    .maybeSingle()
  if (!admin) return { error: 'forbidden' as const }
  return { user, admin, svc }
}

export async function attentionSnoozeAction(userId: string, kind: string, hours = 24) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: { message?: string } | null }>
  }).rpc('attention_snooze', { p_user_id: userId, p_kind: kind, p_hours: hours })
  if (error) return { error: error.message ?? String(error) }
  revalidatePath('/dashboard')
  return { ok: true }
}

export async function attentionDismissAction(userId: string, kind: string, reason?: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: { message?: string } | null }>
  }).rpc('attention_dismiss', { p_user_id: userId, p_kind: kind, p_reason: reason ?? null })
  if (error) return { error: error.message ?? String(error) }
  revalidatePath('/dashboard')
  return { ok: true }
}
