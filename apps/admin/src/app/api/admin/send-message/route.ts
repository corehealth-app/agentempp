import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { NextResponse } from 'next/server'
import { createServiceClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'
export const runtime = 'nodejs'

/**
 * Admin-only manual message send. Usado pra:
 *   - notificar paciente sobre correção feita no produto
 *   - resposta proativa fora do fluxo normal
 *   - testes
 *
 * Auth: bearer com SUPABASE_SERVICE_ROLE_KEY (server-to-server).
 *
 * Body: { user_id: string, text: string }
 */
export async function POST(req: Request) {
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!serviceRoleKey) {
    return NextResponse.json({ error: 'service role key not configured' }, { status: 503 })
  }
  const auth = req.headers.get('authorization') ?? ''
  const expected = `Bearer ${serviceRoleKey}`
  if (auth !== expected) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 })
  }

  const body = (await req.json().catch(() => null)) as { user_id?: string; text?: string } | null
  const userId = body?.user_id
  const text = body?.text?.trim()
  if (!userId || !text) {
    return NextResponse.json({ error: 'missing user_id or text' }, { status: 400 })
  }

  const svc = createServiceClient()
  const { data: user, error: userError } = await svc
    .from('users')
    .select('id, wpp, name')
    .eq('id', userId)
    .maybeSingle()
  if (userError) {
    return NextResponse.json({ error: 'user lookup failed' }, { status: 500 })
  }
  if (!user?.wpp) {
    return NextResponse.json({ error: 'user not found or no wpp' }, { status: 404 })
  }

  const messaging = createMessagingProvider({
    MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
    META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
    META_APP_SECRET: process.env.META_APP_SECRET,
    META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
  })

  let deliveryStatus: 'queued' | 'sent' | 'failed' = 'failed'
  let deliveryError: string | undefined
  let providerMessageId: string | null = null
  let deliveredContent = text
  try {
    const results = await sendHumanized(messaging, user.wpp, text, {
      showTyping: false,
      minDelay: 300,
      maxDelay: 800,
      charsPerSecond: 60,
      singleMessage: true,
    })
    const delivery = results[0]
    if (!delivery) throw new Error('provider returned no delivery result')
    deliveryStatus = delivery.status
    deliveryError = delivery.error
    providerMessageId = delivery.providerMessageId
    deliveredContent = delivery.content
  } catch (e) {
    deliveryStatus = 'failed'
    deliveryError = e instanceof Error ? e.message : String(e)
  }

  const { error: persistenceError } = await svc.from('messages').insert({
    user_id: userId,
    direction: 'out',
    role: 'assistant',
    content_type: 'text',
    content: deliveredContent,
    provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    provider_message_id: providerMessageId,
    agent_stage: 'admin_manual',
    delivery_status: deliveryStatus,
    delivery_error: deliveryError ? { msg: deliveryError } : null,
    raw_payload: { source: 'admin_api' },
  })
  if (persistenceError) {
    return NextResponse.json(
      {
        success: false,
        delivered: deliveryStatus !== 'failed',
        delivery_status: deliveryStatus,
        provider_message_id: providerMessageId,
        error: 'message history persistence failed',
      },
      { status: 500 },
    )
  }

  return NextResponse.json(
    {
      success: deliveryStatus !== 'failed',
      user_id: userId,
      wpp: user.wpp,
      provider_message_id: providerMessageId,
      delivery_status: deliveryStatus,
      error: deliveryError ?? null,
    },
    { status: deliveryStatus === 'failed' ? 502 : 200 },
  )
}
