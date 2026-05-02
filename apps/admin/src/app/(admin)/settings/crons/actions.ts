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

export async function toggleCronAction(jobname: string, active: boolean) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: { message?: string } | null }>
  }).rpc('cron_toggle_job', { p_jobname: jobname, p_active: active })
  if (error) return { error: error.message ?? String(error) }
  revalidatePath('/settings/crons')
  return { ok: true }
}

export async function updateCronScheduleAction(jobname: string, schedule: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const trimmed = schedule.trim()
  if (!trimmed) return { error: 'schedule vazio' }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: { message?: string } | null }>
  }).rpc('cron_update_schedule', { p_jobname: jobname, p_schedule: trimmed })
  if (error) return { error: error.message ?? String(error) }
  revalidatePath('/settings/crons')
  return { ok: true }
}

export async function runCronNowAction(jobname: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: { message?: string } | null }>
  }).rpc('cron_run_now', { p_jobname: jobname })
  if (error) return { error: error.message ?? String(error) }
  revalidatePath('/settings/crons')
  return { ok: true }
}
