// Edge Function: webhook-whatsapp
// Recebe eventos do WhatsApp Cloud API e enfileira processamento.
//
// Setup:
//   - Configure no Meta App: webhook URL apontando aqui
//   - Verify Token: igual ao salvo em service_credentials/meta_whatsapp.verify_token
//
// Esta função é leve: valida HMAC, deduplica, persiste msg in, dispara
// processamento em background. NÃO chama LLM (timeout de 5s da Meta).
//
// Para o MVP sem WhatsApp ativado, este arquivo serve como placeholder.
// Quando MESSAGING_PROVIDER=whatsapp_cloud for ativado:
//   1. Configure secrets via `supabase secrets set ...`
//   2. Deploy: `supabase functions deploy webhook-whatsapp --no-verify-jwt`

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

async function getCredential(supabase: ReturnType<typeof createClient>, service: string, keyName: string) {
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
  return signature === expected
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
      return new Response(challenge, { status: 200 })
    }
    return new Response('forbidden', { status: 403 })
  }

  // ===== POST: webhook event =====
  if (req.method !== 'POST') return new Response('method', { status: 405 })

  const rawBody = await req.text()
  const appSecret = await getCredential(supabase, 'meta_whatsapp', 'app_secret')
  if (!appSecret) return new Response('not configured', { status: 500 })

  const sig = req.headers.get('x-hub-signature-256') ?? ''
  const ok = await verifyMetaSignature(appSecret, sig, rawBody)
  if (!ok) return new Response('forbidden', { status: 403 })

  const payload = JSON.parse(rawBody)

  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      if (change.field !== 'messages') continue
      for (const msg of change.value?.messages ?? []) {
        // Idempotência
        const { error: dupErr } = await supabase
          .from('processed_messages')
          .insert({ provider_message_id: msg.id })
        if (dupErr?.code === '23505') continue // já processado

        // TODO: persistir + enfileirar para worker (Inngest ou pgmq).
        // Por ora, apenas registra como mensagem inbound bruta.
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

        await supabase.from('messages').insert({
          user_id: userId,
          direction: 'in',
          role: 'user',
          content_type:
            msg.type === 'text'
              ? 'text'
              : msg.type === 'audio'
                ? 'audio'
                : msg.type === 'image'
                  ? 'image'
                  : 'text',
          content: msg.text?.body ?? msg.image?.caption ?? null,
          provider: 'whatsapp_cloud',
          provider_message_id: msg.id,
          raw_payload: msg,
        })

        // TODO Fase final: enfileirar evento para worker que chame processMessage.
        // Por agora a mensagem fica registrada e o admin pode triggar manualmente.
      }
    }
  }

  return new Response('ok', { status: 200 })
})
