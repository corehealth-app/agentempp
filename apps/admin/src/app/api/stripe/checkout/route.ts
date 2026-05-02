/**
 * POST /api/stripe/checkout
 * Body: { user_id: string, lookup_key: 'mpp_mensal_v1' | 'mpp_anual_v1' }
 * Retorna: { url } pra redirecionar ao Stripe Checkout.
 */
import { NextResponse } from 'next/server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { createCheckoutSession } from '@/lib/stripe'

export const runtime = 'nodejs'

export async function POST(req: Request) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'unauthenticated' }, { status: 401 })

  const { data: admin } = await supabase
    .from('admin_users')
    .select('id')
    .eq('id', user.id)
    .maybeSingle()
  if (!admin) return NextResponse.json({ error: 'forbidden' }, { status: 403 })

  let body: { user_id?: string; lookup_key?: string } = {}
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'invalid json' }, { status: 400 })
  }
  if (!body.user_id || !body.lookup_key) {
    return NextResponse.json(
      { error: 'campos user_id e lookup_key obrigatórios' },
      { status: 400 },
    )
  }

  const svc = createServiceClient()
  const { data: target } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        eq: (col: string, val: string) => {
          maybeSingle: () => Promise<{ data: unknown }>
        }
      }
    }
  })
    .from('users')
    .select('id, wpp, email, name, country')
    .eq('id', body.user_id)
    .maybeSingle()
  const targetUser = target as
    | {
        id: string
        wpp: string
        email: string | null
        name: string | null
        country: string | null
      }
    | null
  if (!targetUser) {
    return NextResponse.json({ error: 'user not found' }, { status: 404 })
  }

  const origin = req.headers.get('origin') ?? 'https://agentempp.vercel.app'

  try {
    const result = await createCheckoutSession({
      lookup_key: body.lookup_key,
      user_id: targetUser.id,
      user_wpp: targetUser.wpp,
      user_email: targetUser.email,
      user_name: targetUser.name,
      user_country: targetUser.country,
      success_url: `${origin}/users/${targetUser.id}?stripe=success`,
      cancel_url: `${origin}/users/${targetUser.id}?stripe=cancel`,
    })
    return NextResponse.json({ ok: true, ...result })
  } catch (e) {
    return NextResponse.json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    )
  }
}
