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

export async function pauseUserAction(userId: string, days: number) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
  }).rpc('pause_user', { p_user_id: userId, p_days: days })
  if (error)
    return { error: (error as { message?: string }).message ?? String(error) }
  revalidatePath('/messages')
  return { ok: true }
}

export async function resumeUserAction(userId: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
  }).rpc('resume_user', { p_user_id: userId })
  if (error)
    return { error: (error as { message?: string }).message ?? String(error) }
  revalidatePath('/messages')
  return { ok: true }
}

export async function tagUserAction(userId: string, tag: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const t = tag.trim().toLowerCase().replace(/\s+/g, '-')
  if (!t) return { error: 'tag vazia' }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
  }).rpc('tag_user', { p_user_id: userId, p_tag: t })
  if (error)
    return { error: (error as { message?: string }).message ?? String(error) }
  revalidatePath('/messages')
  return { ok: true, tag: t }
}

export async function untagUserAction(userId: string, tag: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
  }).rpc('untag_user', { p_user_id: userId, p_tag: tag })
  if (error)
    return { error: (error as { message?: string }).message ?? String(error) }
  revalidatePath('/messages')
  return { ok: true }
}

export async function updateNotesAction(userId: string, notes: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const { error } = await (ctx.svc as unknown as {
    from: (t: string) => {
      update: (u: Record<string, unknown>) => {
        eq: (col: string, val: string) => Promise<{ error: { message: string } | null }>
      }
    }
  })
    .from('users')
    .update({ admin_notes: notes, updated_at: new Date().toISOString() })
    .eq('id', userId)
  if (error) return { error: error.message }
  revalidatePath('/messages')
  return { ok: true }
}

export async function updateUserNameAction(userId: string, name: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const trimmed = name.trim()
  const { error } = await ctx.svc
    .from('users')
    .update({ name: trimmed || null, updated_at: new Date().toISOString() })
    .eq('id', userId)
  if (error) return { error: error.message }
  revalidatePath('/messages')
  return { ok: true }
}

export type ReviewFlag =
  | 'hallucination'
  | 'great_response'
  | 'needs_review'
  | 'wrong_tool'
  | 'tone_off'
  | 'too_long'

export async function flagMessageAction(
  messageId: string,
  flag: ReviewFlag | null,
  note?: string,
) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }
  const updates = flag
    ? {
        review_flag: flag,
        review_flagged_by: ctx.user.id,
        review_flagged_at: new Date().toISOString(),
        review_note: note ?? null,
      }
    : {
        review_flag: null,
        review_flagged_by: null,
        review_flagged_at: null,
        review_note: null,
      }
  const { error } = await (ctx.svc as unknown as {
    from: (t: string) => {
      update: (u: Record<string, unknown>) => {
        eq: (col: string, val: string) => Promise<{ error: { message: string } | null }>
      }
    }
  })
    .from('messages')
    .update(updates)
    .eq('id', messageId)
  if (error) return { error: error.message }
  revalidatePath('/messages')
  return { ok: true }
}

/**
 * Reseta a conversa de um paciente: apaga messages, message_buffer,
 * tools_audit, meal_logs, workout_logs, daily_snapshots, user_progress,
 * subscription_events. **Mantém** users + user_profiles + subscriptions
 * (zera onboarding pra refazer do zero).
 *
 * Útil pra testar fluxo de onboarding sem precisar criar paciente novo.
 */
export async function resetUserConversationAction(userId: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }

  const { data: u } = await ctx.svc
    .from('users')
    .select('id, name, wpp')
    .eq('id', userId)
    .maybeSingle()
  if (!u) return { error: 'user não encontrado' }

  // Tabelas filhas que vamos limpar (mantém user + profile + subscriptions ativas)
  const tables = [
    'messages',
    'message_buffer',
    'tools_audit',
    'meal_logs',
    'workout_logs',
    'daily_snapshots',
    'reevaluations',
    'message_embeddings',
  ]
  for (const t of tables) {
    await (ctx.svc as unknown as {
      from: (t: string) => {
        delete: () => { eq: (col: string, val: string) => Promise<unknown> }
      }
    })
      .from(t)
      .delete()
      .eq('user_id', userId)
      .catch(() => {}) // tabelas podem não ter user_id ou outro cleanup
  }

  // Reseta user_profiles (mantém row mas zera campos)
  await ctx.svc
    .from('user_profiles')
    .update({
      sex: null,
      birth_date: null,
      height_cm: null,
      weight_kg: null,
      body_fat_percent: null,
      activity_level: null,
      training_frequency: null,
      water_intake: null,
      hunger_level: null,
      wake_time: null,
      bedtime: null,
      current_protocol: null,
      goal_type: null,
      goal_value: null,
      deficit_level: null,
      onboarding_completed: false,
      onboarding_step: 0,
      updated_at: new Date().toISOString(),
    })
    .eq('user_id', userId)

  // Reseta user_progress
  await ctx.svc
    .from('user_progress')
    .update({
      xp_total: 0,
      level: 1,
      current_streak: 0,
      longest_streak: 0,
      blocks_completed: 0,
      deficit_block: 0,
      current_weight: null,
      current_bf_percent: null,
      badges_earned: [],
      last_active_date: null,
      next_reevaluation: null,
      updated_at: new Date().toISOString(),
    })
    .eq('user_id', userId)

  // Reseta users: limpa name + summary + tags + admin_notes + country_confirmed,
  // mantém wpp + status. country fica como detect (pra agente perguntar de novo).
  await (ctx.svc as unknown as {
    from: (t: string) => {
      update: (u: Record<string, unknown>) => {
        eq: (col: string, val: string) => Promise<{ error: { message: string } | null }>
      }
    }
  })
    .from('users')
    .update({
      name: null,
      summary: null,
      summary_updated_at: null,
      tags: [],
      admin_notes: null,
      country_confirmed: false,
      last_active_at: null,
      metadata: {},
      updated_at: new Date().toISOString(),
    })
    .eq('id', userId)

  await ctx.svc.from('audit_log').insert({
    actor_id: ctx.user.id,
    actor_email: ctx.user.email,
    action: 'user.reset_conversation',
    entity: 'users',
    entity_id: userId,
    before: { name: u.name, wpp: u.wpp },
  })

  await ctx.svc.from('product_events').insert({
    user_id: userId,
    event: 'user.conversation_reset',
    properties: { actor: ctx.user.email, wpp: u.wpp },
  })

  revalidatePath('/messages')
  revalidatePath('/users')
  revalidatePath(`/users/${userId}`)
  return { ok: true, wpp: u.wpp }
}

/**
 * Apaga o paciente completamente: cascade DELETE no users → todas tabelas
 * filhas via FK. Para testar fluxo do zero como se fosse 1ª interação.
 */
export async function deleteUserAction(userId: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }

  const { data: u } = await ctx.svc
    .from('users')
    .select('*')
    .eq('id', userId)
    .maybeSingle()
  if (!u) return { error: 'user não encontrado' }

  // Snapshot pra audit antes de cascade
  const before = JSON.parse(JSON.stringify(u))

  const { error } = await ctx.svc.from('users').delete().eq('id', userId)
  if (error) return { error: error.message }

  await ctx.svc.from('audit_log').insert({
    actor_id: ctx.user.id,
    actor_email: ctx.user.email,
    action: 'user.delete_full',
    entity: 'users',
    entity_id: userId,
    before,
  })

  revalidatePath('/messages')
  revalidatePath('/users')
  return { ok: true }
}

/**
 * Força reprocessamento de uma mensagem IN: re-dispara o evento Inngest
 * message.received com os dados da mensagem original.
 */
export async function reprocessMessageAction(messageId: string) {
  const ctx = await requireAdmin()
  if ('error' in ctx) return { error: ctx.error }

  const { data: msg } = await ctx.svc
    .from('messages')
    .select(
      'user_id, direction, content, content_type, provider, provider_message_id, raw_payload, created_at',
    )
    .eq('id', messageId)
    .maybeSingle()
  if (!msg) return { error: 'msg não encontrada' }
  if ((msg as { direction: string }).direction === 'out')
    return { error: 'só msgs IN podem ser reprocessadas' }

  const { data: user } = await ctx.svc
    .from('users')
    .select('id, wpp')
    .eq('id', msg.user_id)
    .maybeSingle()
  if (!user) return { error: 'user não encontrado' }

  // Dispara via dispatch_inngest_event (RPC pg_net)
  const eventKey =
    'inngest.event_key' /* placeholder — Edge Function lê da DB */
  // Usa RPC já existente
  const { error } = await (ctx.svc as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
  }).rpc('dispatch_inngest_event', {
    p_event_name: 'message.received',
    p_data: {
      userId: msg.user_id,
      wpp: (user as { wpp: string }).wpp,
      providerMessageId: msg.provider_message_id ?? `reproc_${messageId}`,
      contentType: msg.content_type,
      text: msg.content,
      provider: msg.provider,
      timestamp: msg.created_at,
      reprocess: true,
    },
  })
  if (error) {
    return { error: (error as { message?: string }).message ?? String(error), eventKey }
  }
  return { ok: true }
}
