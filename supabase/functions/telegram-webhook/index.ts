// Edge function: telegram-webhook
//
// Recebe callback_query do Telegram quando user clica em [Aprovar] ou [Rejeitar]
// numa mensagem enviada por notify-telegram. Auth via secret_token (parametro
// que o Telegram envia em todo POST se configurado em setWebhook).
//
// Quando aprovado: aplica o fix correspondente (food_alias via INSERT direto
// usando service_role).
// Quando rejeitado: so atualiza status.
// Em ambos: editMessageText pra mostrar o status final na conversa do Telegram.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const TELEGRAM_BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? ''
const TELEGRAM_ADMIN_CHAT_ID = Deno.env.get('TELEGRAM_ADMIN_CHAT_ID') ?? ''
const TELEGRAM_WEBHOOK_SECRET = Deno.env.get('TELEGRAM_WEBHOOK_SECRET') ?? ''

interface FoodAliasPayload {
  food_name: string
  category: string
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  country_code?: string
}

async function tg(method: string, body: Record<string, unknown>) {
  const r = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!r.ok) console.error(`telegram ${method} failed`, await r.text())
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function applyFix(supabase: any, type: string, payload: Record<string, unknown>) {
  if (type === 'food_alias') {
    const p = payload as unknown as FoodAliasPayload
    // Skip se ja existe
    const { data: exist } = await supabase
      .from('food_db')
      .select('id')
      .eq('name_pt', p.food_name)
      .eq('country_code', p.country_code ?? 'BR')
      .maybeSingle()
    if (exist) return { ok: false, reason: 'ja existe' }
    const { data, error } = await supabase
      .from('food_db')
      .insert({
        name_pt: p.food_name,
        category: p.category,
        kcal_per_100g: p.kcal_per_100g,
        protein_g: p.protein_g,
        carbs_g: p.carbs_g,
        fat_g: p.fat_g,
        fiber_g: p.fiber_g,
        country_code: p.country_code ?? 'BR',
        source: 'alias_telegram_approved',
      })
      .select('id')
      .single()
    if (error) return { ok: false, reason: error.message }
    return { ok: true, food_db_id: (data as { id: number }).id }
  }
  if (type === 'structural_bug_report') {
    // Bug estrutural só aprovado vira "noted" — log em product_events.
    return { ok: true, note: 'estrutural — só registrado, nada de codigo muda' }
  }
  return { ok: false, reason: `tipo ${type} nao implementado pra auto-aplicar` }
}

Deno.serve(async (req: Request) => {
  // Telegram envia esse header se configurado em setWebhook.secret_token
  const secret = req.headers.get('x-telegram-bot-api-secret-token') ?? ''
  if (TELEGRAM_WEBHOOK_SECRET && secret !== TELEGRAM_WEBHOOK_SECRET) {
    return new Response('forbidden', { status: 403 })
  }
  if (req.method !== 'POST') return new Response('method', { status: 405 })

  let update: {
    callback_query?: {
      id: string
      from: { id: number }
      message?: { message_id: number; chat: { id: number } }
      data?: string
    }
  }
  try {
    update = await req.json()
  } catch {
    return new Response('bad json', { status: 400 })
  }

  // So processamos callback_queries (cliques em botoes)
  const cb = update.callback_query
  if (!cb) return new Response('ok', { status: 200 })

  // Auth: chat_id do user deve ser o admin
  if (String(cb.from.id) !== TELEGRAM_ADMIN_CHAT_ID) {
    await tg('answerCallbackQuery', {
      callback_query_id: cb.id,
      text: 'Não autorizado.',
      show_alert: true,
    })
    return new Response('ok', { status: 200 })
  }

  const data = cb.data ?? ''
  const [action, pendingId] = data.split(':')
  if (!['approve', 'reject'].includes(action) || !pendingId) {
    await tg('answerCallbackQuery', { callback_query_id: cb.id, text: 'Ação inválida.' })
    return new Response('ok', { status: 200 })
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  // Busca pending
  const { data: pending } = await supabase
    .from('pending_approvals')
    .select('*')
    .eq('id', pendingId)
    .single()

  if (!pending) {
    await tg('answerCallbackQuery', { callback_query_id: cb.id, text: 'Pending não encontrada.' })
    return new Response('ok', { status: 200 })
  }
  if ((pending.status as string) !== 'pending') {
    await tg('answerCallbackQuery', {
      callback_query_id: cb.id,
      text: `Já foi decidido: ${pending.status}`,
    })
    return new Response('ok', { status: 200 })
  }

  let newStatus: 'approved' | 'rejected' | 'applied' | 'failed_to_apply' = 'rejected'
  let appliedResult: Record<string, unknown> | null = null
  let applicationError: string | null = null

  if (action === 'approve') {
    newStatus = 'approved'
    // Tenta aplicar imediatamente
    const result = await applyFix(
      supabase,
      pending.type as string,
      pending.payload as Record<string, unknown>,
    )
    if (result.ok) {
      newStatus = 'applied'
      appliedResult = result as Record<string, unknown>
    } else {
      newStatus = 'failed_to_apply'
      applicationError = (result as { reason: string }).reason
    }
  }

  // Update pending
  await supabase
    .from('pending_approvals')
    .update({
      status: newStatus,
      decided_via: 'telegram',
      decided_at: new Date().toISOString(),
      application_result: appliedResult,
      application_error: applicationError,
    })
    .eq('id', pendingId)

  // Audit log
  await supabase.from('audit_log').insert({
    action: `pending_approval.${newStatus}`,
    entity: 'pending_approvals',
    entity_id: pendingId,
    details: {
      type: pending.type,
      decided_via: 'telegram',
      telegram_user_id: cb.from.id,
      payload_summary: JSON.stringify(pending.payload).slice(0, 300),
      application_error: applicationError,
    },
  })

  // Edita a msg original pra mostrar resultado final
  if (cb.message) {
    const statusEmoji =
      newStatus === 'applied'
        ? '✅ Aprovado e aplicado'
        : newStatus === 'failed_to_apply'
          ? '⚠️ Aprovado mas falhou ao aplicar'
          : newStatus === 'approved'
            ? '✅ Aprovado'
            : '❌ Rejeitado'
    const summaryLine = applicationError
      ? `\n\nErro: ${applicationError}`
      : appliedResult && (appliedResult as { food_db_id?: number }).food_db_id
        ? `\n\nfood_db.id = ${(appliedResult as { food_db_id: number }).food_db_id}`
        : ''
    await tg('editMessageText', {
      chat_id: cb.message.chat.id,
      message_id: cb.message.message_id,
      text:
        // texto original ja vai estar truncado, vamos so adicionar status no topo
        `${statusEmoji}${summaryLine}\n\n— decisão registrada —`,
    })
  }

  await tg('answerCallbackQuery', {
    callback_query_id: cb.id,
    text: newStatus === 'applied' ? 'Aplicado.' : newStatus === 'rejected' ? 'Rejeitado.' : 'OK',
  })

  return new Response('ok', { status: 200 })
})
