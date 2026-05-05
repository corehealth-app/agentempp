// Edge function: notify-telegram
//
// Recebe um pending_approval ou cria um novo. Formata mensagem em PT-BR
// com botoes inline [Aprovar] [Rejeitar] e envia pro chat admin via
// MargotPiper_Bot. Salva message_id pra editar depois quando decidido.
//
// Body (POST):
//   { pending_id }                   → reenviar uma pending existente
//   OU
//   { type, payload, reason, confidence, run_id }
//                                    → criar nova pending + notificar
//
// Auth: header x-audit-secret (mesmo da audit-findings).

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const AUDIT_SECRET = Deno.env.get('AUDIT_SECRET') ?? ''
const TELEGRAM_BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? ''
const TELEGRAM_ADMIN_CHAT_ID = Deno.env.get('TELEGRAM_ADMIN_CHAT_ID') ?? ''

interface CreateBody {
  type: 'food_alias' | 'global_config_update' | 'rule_update' | 'structural_bug_report'
  payload: Record<string, unknown>
  reason?: string
  confidence?: 'high' | 'medium' | 'low'
  run_id?: string
}

function formatMessage(
  type: string,
  payload: Record<string, unknown>,
  reason: string | null,
  confidence: string | null,
  pendingId: string,
): string {
  const conf = confidence ? ` _(confiança ${confidence})_` : ''
  const reasonLine = reason ? `\n📋 ${reason}` : ''

  const idLine = `\n\nid: ${pendingId.slice(0, 8)}`

  if (type === 'food_alias') {
    const p = payload as Record<string, number | string>
    return (
      `🤖 Auditoria automática sugeriu adicionar ao food_db${conf}:\n\n` +
      `🍽️ ${p.food_name}\n` +
      `Categoria: ${p.category} · País: ${p.country_code ?? 'BR'}\n` +
      `${p.kcal_per_100g} kcal · ${p.protein_g}g prot · ${p.carbs_g}g carb · ${p.fat_g}g gord · ${p.fiber_g}g fib (por 100g)` +
      reasonLine +
      idLine
    )
  }
  if (type === 'global_config_update') {
    const p = payload as { key: string; new_value: unknown; old_value?: unknown }
    return (
      `🤖 Auditoria sugeriu mudar config global${conf}:\n\n` +
      `⚙️ ${p.key}\n` +
      `${p.old_value !== undefined ? `de ${JSON.stringify(p.old_value)} ` : ''}para ${JSON.stringify(p.new_value)}` +
      reasonLine +
      idLine
    )
  }
  if (type === 'rule_update') {
    const p = payload as { slug: string; action: string }
    return (
      `🤖 Auditoria sugeriu mexer em uma regra do agent${conf}:\n\n` +
      `📜 ${p.slug} (${p.action})` +
      reasonLine +
      idLine
    )
  }
  if (type === 'structural_bug_report') {
    const p = payload as { title: string; description: string }
    return (
      `🚨 Bug estrutural detectado${conf}\n\n` +
      `${p.title}\n` +
      `${p.description}` +
      reasonLine +
      idLine
    )
  }
  return `🤖 Auditoria sugeriu mudança ${type}${conf}\n${JSON.stringify(payload).slice(0, 200)}${idLine}`
}

async function sendTelegramMessage(
  chatId: string,
  text: string,
  pendingId: string,
): Promise<{ ok: boolean; message_id?: number; error?: string }> {
  const body = {
    chat_id: chatId,
    text,
    reply_markup: {
      inline_keyboard: [
        [
          { text: '✅ Aprovar', callback_data: `approve:${pendingId}` },
          { text: '❌ Rejeitar', callback_data: `reject:${pendingId}` },
        ],
        [{ text: '🔍 Detalhes (admin)', url: `https://agentempp.vercel.app/audit#pending-${pendingId}` }],
      ],
    },
  }
  // Tenta MarkdownV2 — se falhar, retry sem parse_mode
  const r = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (r.ok) {
    const j = await r.json()
    return { ok: true, message_id: j.result?.message_id }
  }
  // Fallback: sem markdown (texto cru)
  const fallback = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...body, parse_mode: undefined }),
  })
  if (fallback.ok) {
    const j = await fallback.json()
    return { ok: true, message_id: j.result?.message_id }
  }
  return { ok: false, error: await fallback.text() }
}

Deno.serve(async (req: Request) => {
  if (req.headers.get('x-audit-secret') !== AUDIT_SECRET || !AUDIT_SECRET) {
    return new Response('forbidden', { status: 403 })
  }
  if (req.method !== 'POST') return new Response('method', { status: 405 })

  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_ADMIN_CHAT_ID) {
    return Response.json({ ok: false, error: 'telegram not configured' }, { status: 500 })
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  let body: { pending_id?: string } & Partial<CreateBody>
  try {
    body = await req.json()
  } catch {
    return new Response('bad json', { status: 400 })
  }

  let pendingId: string
  let type: string
  let payload: Record<string, unknown>
  let reason: string | null
  let confidence: string | null

  if (body.pending_id) {
    const { data, error } = await supabase
      .from('pending_approvals')
      .select('*')
      .eq('id', body.pending_id)
      .single()
    if (error || !data) return Response.json({ ok: false, error: 'pending not found' }, { status: 404 })
    pendingId = data.id as string
    type = data.type as string
    payload = data.payload as Record<string, unknown>
    reason = (data.reason as string | null) ?? null
    confidence = (data.confidence as string | null) ?? null
  } else if (body.type && body.payload) {
    const insertRow = {
      type: body.type,
      payload: body.payload,
      reason: body.reason ?? null,
      confidence: body.confidence ?? null,
      run_id: body.run_id ?? null,
      telegram_chat_id: TELEGRAM_ADMIN_CHAT_ID,
      status: 'pending',
    }
    const { data, error } = await supabase
      .from('pending_approvals')
      .insert(insertRow)
      .select('id')
      .single()
    if (error) return Response.json({ ok: false, error: error.message }, { status: 500 })
    pendingId = (data as { id: string }).id
    type = body.type
    payload = body.payload
    reason = body.reason ?? null
    confidence = body.confidence ?? null
  } else {
    return Response.json({ ok: false, error: 'pending_id or (type,payload) required' }, { status: 400 })
  }

  // MarkdownV2 escape pra texto unico (chat title etc nao usado aqui)
  // Mas usamos cuidadosamente em formatMessage com escape minimo:
  // chars que precisam escape: _*[]()~`>#+-=|{}.!
  // Como o texto e gerado por nos, vamos usar parse_mode=Markdown (legacy v1) que
  // e mais permissivo. Usar parse_mode com fallback.
  const text = formatMessage(type, payload, reason, confidence, pendingId)

  const result = await sendTelegramMessage(TELEGRAM_ADMIN_CHAT_ID, text, pendingId)
  if (!result.ok) {
    return Response.json({ ok: false, error: result.error, pending_id: pendingId }, { status: 502 })
  }

  // Salva message_id no pending pra editar depois
  await supabase
    .from('pending_approvals')
    .update({ telegram_message_id: result.message_id })
    .eq('id', pendingId)

  return Response.json({
    ok: true,
    pending_id: pendingId,
    telegram_message_id: result.message_id,
  })
})
