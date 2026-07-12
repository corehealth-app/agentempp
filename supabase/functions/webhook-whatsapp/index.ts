// Edge Function: webhook-whatsapp
// Recebe eventos do WhatsApp Cloud API e EMPILHA mensagens em buffer
// (debounce 8s) antes de disparar o agente — evita 1 LLM call por linha
// quando o user manda várias msgs rápidas em sequência.

import { createClient } from 'jsr:@supabase/supabase-js@2'
import { resolveProviderTimestamp } from '../_shared/provider-timestamp.ts'

function requireEnv(name: string): string {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`${name} is not configured`)
  return value
}

type InteractiveReply = { id?: string; title?: string }
type WhatsAppInboundMessage = {
  id?: string
  from?: string
  timestamp?: unknown
  type?: string
  text?: { body?: string }
  image?: { id?: string; caption?: string }
  audio?: { id?: string }
  interactive?: {
    type?: string
    button_reply?: InteractiveReply
    list_reply?: InteractiveReply
  }
  [key: string]: unknown
}
type WhatsAppWebhookPayload = {
  entry?: Array<{
    changes?: Array<{
      field?: string
      value?: {
        statuses?: Array<{ id?: string; status?: string }>
        messages?: WhatsAppInboundMessage[]
      }
    }>
  }>
}

const SUPABASE_URL = requireEnv('SUPABASE_URL')
const SUPABASE_SERVICE_ROLE_KEY = requireEnv('SUPABASE_SERVICE_ROLE_KEY')
const INNGEST_EVENT_KEY = Deno.env.get('INNGEST_EVENT_KEY')

function createEdgeSupabaseClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

type EdgeSupabaseClient = ReturnType<typeof createEdgeSupabaseClient>

// Buffer debounce — editável via /settings/global → buffer.debounce_ms.
// Cache 60s, fallback 8000ms.
const DEFAULT_BUFFER_DEBOUNCE_MS = 8000
let cachedBufferDebounce: { value: number; expiresAt: number } | null = null
const BUFFER_CACHE_TTL_MS = 60_000

async function getBufferDebounceMs(
  supabase: EdgeSupabaseClient,
): Promise<number> {
  const now = Date.now()
  if (cachedBufferDebounce && cachedBufferDebounce.expiresAt > now) {
    return cachedBufferDebounce.value
  }
  const { data } = await supabase
    .from('global_config')
    .select('value')
    .eq('key', 'buffer.debounce_ms')
    .maybeSingle()
  const raw = (data as { value: unknown } | null)?.value
  const num = Number(raw ?? DEFAULT_BUFFER_DEBOUNCE_MS)
  const value = Number.isFinite(num) && num > 0 ? num : DEFAULT_BUFFER_DEBOUNCE_MS
  cachedBufferDebounce = { value, expiresAt: now + BUFFER_CACHE_TTL_MS }
  return value
}

async function getCredential(
  supabase: EdgeSupabaseClient,
  service: string,
  keyName: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from('service_credentials')
    .select('value')
    .eq('service', service)
    .eq('key_name', keyName)
    .eq('is_active', true)
    .maybeSingle()
  if (error) throw new Error('service credential lookup failed')
  return (data as { value: string } | null)?.value ?? null
}

async function verifyMetaSignature(
  appSecret: string,
  signature: string,
  rawBody: string,
): Promise<boolean> {
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(appSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sigBytes = await crypto.subtle.sign('HMAC', key, enc.encode(rawBody))
  const expected = `sha256=${Array.from(new Uint8Array(sigBytes))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')}`
  if (signature.length !== expected.length) return false
  let mismatch = 0
  for (let i = 0; i < signature.length; i++) {
    mismatch |= signature.charCodeAt(i) ^ expected.charCodeAt(i)
  }
  return mismatch === 0
}

async function sendInngestEvent(
  eventName: string,
  data: Record<string, unknown>,
  delayMs?: number,
  eventId?: string,
): Promise<void> {
  if (!INNGEST_EVENT_KEY) throw new Error('INNGEST_EVENT_KEY is not configured')
  const body: Record<string, unknown> = { name: eventName, data }
  if (eventId) body.id = eventId
  if (delayMs && delayMs > 0) {
    body.ts = Date.now() + delayMs
  }
  const r = await fetch(`https://inn.gs/e/${INNGEST_EVENT_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!r.ok) {
    const responseText = (await r.text()).slice(0, 500)
    throw new Error(`Inngest dispatch failed (${r.status}): ${responseText}`)
  }
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url)
  const supabase = createEdgeSupabaseClient()

  // ===== GET: verify challenge =====
  if (req.method === 'GET') {
    const verifyToken = await getCredential(supabase, 'meta_whatsapp', 'verify_token')
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge')
    if (mode === 'subscribe' && token === verifyToken && challenge) {
      return new Response(challenge, { status: 200, headers: { 'Content-Type': 'text/plain' } })
    }
    return new Response('forbidden', { status: 403 })
  }

  if (req.method !== 'POST') return new Response('method', { status: 405 })

  const rawBody = await req.text()
  const appSecret = await getCredential(supabase, 'meta_whatsapp', 'app_secret')
  if (!appSecret) return new Response('not configured', { status: 500 })

  const sig = req.headers.get('x-hub-signature-256') ?? ''
  const ok = await verifyMetaSignature(appSecret, sig, rawBody)
  if (!ok) return new Response('forbidden', { status: 403 })

  let payload: WhatsAppWebhookPayload
  try {
    const parsed: unknown = JSON.parse(rawBody)
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return new Response('bad json', { status: 400 })
    }
    payload = parsed as WhatsAppWebhookPayload
  } catch {
    return new Response('bad json', { status: 400 })
  }

  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      if (change.field !== 'messages') continue

      // Status updates (sent/delivered/read/failed)
      for (const status of change.value?.statuses ?? []) {
        if (!status.id || !status.status) continue
        const { error: statusError } = await supabase
          .from('messages')
          .update({ delivery_status: status.status })
          .eq('provider', 'whatsapp_cloud')
          .eq('direction', 'out')
          .eq('provider_message_id', status.id)
        if (statusError) throw new Error('message delivery status update failed')
      }

      // Incoming messages
      for (const msg of change.value?.messages ?? []) {
        if (!msg.id || !msg.from) throw new Error('invalid inbound message identity')
        const messageTime = resolveProviderTimestamp(msg.timestamp)

        // ============================================================
        //  INTERACTIVE BUTTON TAP (Roberto 2026-05-28 — Fase A botões #4)
        //  Tap do paciente em [Sim, registrar]/[Editar] chega como msg.type
        //  'interactive' com button_reply.id (nosso ID interno tipo
        //  "confirm_<pending_id>" ou "edit_<pending_id>"). NÃO passa pelo
        //  buffer — é ação discreta, handler determinístico imediato.
        // ============================================================
        // Roberto 2026-06-01 Fase 2: List Message (4-10 opções) chega como
        // `list_reply` em vez de `button_reply`. Mesmo handler (id já tem
        // formato btn_<field>_<value> compatível). 1 só branch pra ambos.
        const interactiveReply =
          msg.type === 'interactive' && msg.interactive?.type === 'button_reply'
            ? msg.interactive?.button_reply
            : msg.type === 'interactive' && msg.interactive?.type === 'list_reply'
              ? msg.interactive?.list_reply
              : null
        const interactiveId =
          typeof interactiveReply?.id === 'string' && interactiveReply.id.length > 0
            ? interactiveReply.id
            : null
        const isInteractive = interactiveId !== null
        const contentType = isInteractive
          ? 'interactive'
          : msg.type === 'text'
            ? 'text'
            : msg.type === 'audio'
              ? 'audio'
              : msg.type === 'image'
                ? 'image'
                : 'text'
        const content = isInteractive
          ? interactiveId
          : (msg.text?.body ?? msg.image?.caption ?? null)
        const shouldBuffer = !isInteractive
        const debounceMs = shouldBuffer
          ? await getBufferDebounceMs(supabase)
          : DEFAULT_BUFFER_DEBOUNCE_MS

        const { data: ingestRaw, error: ingestError } = await supabase.rpc(
          'ingest_whatsapp_inbound',
          {
            p_provider_message_id: msg.id,
            p_wpp: msg.from,
            p_content_type: contentType,
            p_content: content,
            p_media_url: msg.image?.id ?? msg.audio?.id ?? null,
            p_raw_payload: msg,
            p_received_at: messageTime.timestamp,
            p_server_received_at: messageTime.serverReceivedAt,
            p_debounce_ms: debounceMs,
            p_buffer: shouldBuffer,
          },
        )
        if (ingestError) throw new Error(`inbound ingest failed: ${ingestError.message}`)

        const ingest = ingestRaw as {
          duplicate?: boolean
          user_id?: string
          buffer_count?: number
        } | null
        const userId = ingest?.user_id
        if (!userId) throw new Error('inbound ingest returned no user id')

        if (!ingest?.duplicate && messageTime.source === 'server_fallback') {
          await supabase.from('product_events').insert({
            user_id: userId,
            event: 'message.provider_timestamp_fallback',
            properties: {
              reason: messageTime.fallbackReason,
              content_type: msg.type ?? null,
            },
          })
        }

        if (isInteractive) {
          const buttonId = interactiveId
          const buttonTitle =
            typeof interactiveReply?.title === 'string' ? interactiveReply.title : ''
          await sendInngestEvent(
            'interactive.button.tapped',
            {
              userId,
              wpp: msg.from,
              buttonId,
              buttonTitle,
              providerMessageId: msg.id,
              tappedAt: messageTime.timestamp,
            },
            0, // sem delay — tap é ação imediata
            `wa:${msg.id}`,
          )
          continue
        }
        const aggregatedCount = Number(ingest?.buffer_count ?? 1)

        // Dispara evento com delay — Inngest aciona buffer-flush após debounce.
        // Cada msg dispara um evento, mas o worker é idempotente:
        // só processa se ainda houver buffer com flush_after expirado.
        //
        // MARGEM 1500ms (Roberto/Paulo 2026-05-27): antes era +200ms — RACE quando
        // msg2 chega perto do fim do debounce: a RPC de append da msg2 não terminava
        // antes do dispatch fire, e o flush rodava só com msg1 (foto ignorada,
        // 8 ocorrências em 7d). 1500ms cobre o tempo de RPC com folga.
        await sendInngestEvent(
          'buffer.flush',
          { userId, count: aggregatedCount, fired_at: new Date().toISOString() },
          debounceMs + 1500,
          `wa:${msg.id}`,
        )
      }
    }
  }

  return new Response('ok', { status: 200 })
})
