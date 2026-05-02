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
