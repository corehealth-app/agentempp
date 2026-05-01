// Edge Function: webhook-whatsapp
// Recebe eventos do WhatsApp Cloud API e dispara processamento via Inngest.
//
// GET  → handshake de verify (hub.mode=subscribe + hub.verify_token + hub.challenge)
// POST → recebe eventos. Valida HMAC, dedupe, persiste msg in, dispara Inngest.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const INNGEST_EVENT_KEY = Deno.env.get('INNGEST_EVENT_KEY')

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
  // timing-safe comparison
  let mismatch = 0
  for (let i = 0; i < signature.length; i++) {
    mismatch |= signature.charCodeAt(i) ^ expected.charCodeAt(i)
  }
  return mismatch === 0
}

async function sendInngestEvent(eventName: string, data: Record<string, unknown>): Promise<void> {
  if (!INNGEST_EVENT_KEY) {
    console.warn('INNGEST_EVENT_KEY missing — skipping event dispatch')
    return
  }
  try {
    const r = await fetch(`https://inn.gs/e/${INNGEST_EVENT_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: eventName, data }),
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
    console.warn('Verify falhou', { mode, gotToken: !!token, expected: !!verifyToken })
    return new Response('forbidden', { status: 403 })
  }

  // ===== POST: webhook event =====
  if (req.method !== 'POST') return new Response('method', { status: 405 })

  const rawBody = await req.text()
  const appSecret = await getCredential(supabase, 'meta_whatsapp', 'app_secret')
  if (!appSecret) return new Response('not configured', { status: 500 })

  const sig = req.headers.get('x-hub-signature-256') ?? ''
  const ok = await verifyMetaSignature(appSecret, sig, rawBody)
  if (!ok) {
    console.warn('HMAC inválido')
    return new Response('forbidden', { status: 403 })
  }

  let payload: {
    entry?: Array<{
      changes?: Array<{
        field?: string
        value?: {
          messages?: Array<{
            id: string
            from: string
            type: string
            timestamp: string
            text?: { body: string }
            image?: { id: string; caption?: string; mime_type: string }
            audio?: { id: string; mime_type: string }
            video?: { id: string; mime_type: string }
          }>
          statuses?: Array<{ id: string; status: string; timestamp: string }>
        }
      }>
    }>
  }
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

        // dispara processamento via Inngest
        await sendInngestEvent('message.received', {
          userId,
          wpp: msg.from,
          providerMessageId: msg.id,
          contentType,
          text: msg.text?.body ?? msg.image?.caption,
          mediaUrl: msg.image?.id ?? msg.audio?.id,
          provider: 'whatsapp_cloud',
          timestamp: new Date(Number.parseInt(msg.timestamp, 10) * 1000).toISOString(),
        })
      }
    }
  }

  // Meta exige resposta 200 rápida (<5s)
  return new Response('ok', { status: 200 })
})
