import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { createServiceClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

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
  const auth = req.headers.get('authorization') ?? ''
  const expected = `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY ?? ''}`
  if (!expected || auth !== expected) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 })
  }

  const body = (await req.json().catch(() => null)) as
    | { user_id?: string; text?: string }
    | null
  const userId = body?.user_id
  const text = body?.text?.trim()
  if (!userId || !text) {
    return NextResponse.json({ error: 'missing user_id or text' }, { status: 400 })
  }

  const svc = createServiceClient()
  const { data: user } = await svc
    .from('users')
    .select('id, wpp, name')
    .eq('id', userId)
    .maybeSingle()
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

  let deliveryStatus: 'sent' | 'failed' = 'sent'
  let deliveryError: string | undefined
  try {
    const results = await sendHumanized(messaging, user.wpp, text, {
      showTyping: false,
      minDelay: 300,
      maxDelay: 800,
      charsPerSecond: 60,
    })
    if (results.some((r) => r.status !== 'sent')) {
      deliveryStatus = 'failed'
      deliveryError = results.find((r) => r.error)?.error
    }
  } catch (e) {
    deliveryStatus = 'failed'
    deliveryError = e instanceof Error ? e.message : String(e)
  }

  await svc.from('messages').insert({
    user_id: userId,
    direction: 'out',
    role: 'assistant',
    content_type: 'text',
    content: text,
    provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    agent_stage: 'admin_manual',
    delivery_status: deliveryStatus,
    delivery_error: deliveryError ? { msg: deliveryError } : null,
    raw_payload: { source: 'admin_api' },
  })

  return NextResponse.json({
    success: deliveryStatus === 'sent',
    user_id: userId,
    wpp: user.wpp,
    delivery_status: deliveryStatus,
    error: deliveryError ?? null,
  })
}
