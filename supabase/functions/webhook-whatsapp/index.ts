// Edge Function: webhook-whatsapp
// Recebe eventos do WhatsApp Cloud API e EMPILHA mensagens em buffer
// (debounce 8s) antes de disparar o agente — evita 1 LLM call por linha
// quando o user manda várias msgs rápidas em sequência.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const INNGEST_EVENT_KEY = Deno.env.get('INNGEST_EVENT_KEY')

const BUFFER_DEBOUNCE_MS = 8000 // 8s — agrega msgs próximas

async function getCredential(
  supabase: ReturnType<typeof createClient>,
  service: string,
  keyName: string,
): Promise<string | null> {
  const { data } = await supabase
    .from('service_credentials')
    .select('value')
    .eq('service', service)
    .eq('key_name', keyName)
    .eq('is_active', true)
    .maybeSingle()
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
): Promise<void> {
  if (!INNGEST_EVENT_KEY) return
  try {
    const body: Record<string, unknown> = { name: eventName, data }
    if (delayMs && delayMs > 0) {
      body.ts = Date.now() + delayMs
    }
    const r = await fetch(`https://inn.gs/e/${INNGEST_EVENT_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    if (!r.ok) console.error('Inngest dispatch failed', r.status, await r.text())
  } catch (e) {
    console.error('Inngest dispatch exception', e)
  }
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url)
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

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

  let payload: any
  try {
    payload = JSON.parse(rawBody)
  } catch {
    return new Response('bad json', { status: 400 })
  }

  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      if (change.field !== 'messages') continue

      // Status updates (sent/delivered/read/failed)
      for (const status of change.value?.statuses ?? []) {
        await supabase
          .from('messages')
          .update({ delivery_status: status.status })
          .eq('provider_message_id', status.id)
      }

      // Incoming messages
      for (const msg of change.value?.messages ?? []) {
        // Idempotência
        const { error: dupErr } = await supabase
          .from('processed_messages')
          .insert({ provider_message_id: msg.id })
        if (dupErr?.code === '23505') continue

        // ensure user
        const { data: existingUser } = await supabase
          .from('users')
          .select('id')
          .eq('wpp', msg.from)
          .maybeSingle()

        let userId: string
        if (existingUser) {
          userId = (existingUser as { id: string }).id
        } else {
          const { data: created } = await supabase
            .from('users')
            .insert({ wpp: msg.from, status: 'active' })
            .select('id')
            .single()
          userId = (created as { id: string }).id
          await supabase.from('user_profiles').insert({ user_id: userId })
          await supabase.from('user_progress').insert({ user_id: userId })
        }

        const contentType =
          msg.type === 'text'
            ? 'text'
            : msg.type === 'audio'
              ? 'audio'
              : msg.type === 'image'
                ? 'image'
                : 'text'

        // persiste msg in
        await supabase.from('messages').insert({
          user_id: userId,
          direction: 'in',
          role: 'user',
          content_type: contentType,
          content: msg.text?.body ?? msg.image?.caption ?? null,
          provider: 'whatsapp_cloud',
          provider_message_id: msg.id,
          raw_payload: msg,
        })

        // ============================================================
        //  EMPILHAMENTO: push no buffer com debounce
        // ============================================================
        const flushAt = new Date(Date.now() + BUFFER_DEBOUNCE_MS).toISOString()
        const newMsgEntry = {
          provider_message_id: msg.id,
          content_type: contentType,
          text: msg.text?.body ?? msg.image?.caption ?? null,
          mediaUrl: msg.image?.id ?? msg.audio?.id,
          received_at: new Date().toISOString(),
        }

        // Tenta upsert: se já existe buffer pro user, append e estende flush_after
        const { data: existing } = await supabase
          .from('message_buffer')
          .select('messages')
          .eq('user_id', userId)
          .maybeSingle()

        const accumulated = existing
          ? [...((existing.messages as unknown[]) ?? []), newMsgEntry]
          : [newMsgEntry]

        await supabase.from('message_buffer').upsert(
          {
            user_id: userId,
            messages: accumulated,
            buffered_at: new Date().toISOString(),
            flush_after: flushAt,
          },
          { onConflict: 'user_id' },
        )

        // Dispara evento com delay — Inngest aciona buffer-flush em 8s
        // Cada msg dispara um evento, mas o worker é idempotente:
        // só processa se ainda houver buffer com flush_after expirado.
        await sendInngestEvent(
          'buffer.flush',
          { userId, count: accumulated.length, fired_at: new Date().toISOString() },
          BUFFER_DEBOUNCE_MS + 200,
        )
      }
    }
  }

  return new Response('ok', { status: 200 })
})
