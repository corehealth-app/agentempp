/**
 * POST /api/stripe/setup-products
 * Idempotente: cria/atualiza produtos+preços no Stripe (catálogo MPP).
 * Apenas admin autenticado.
 */
import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { setupStripeProducts } from '@/lib/stripe'

export const runtime = 'nodejs'

export async function POST() {
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

  try {
    const results = await setupStripeProducts()
    return NextResponse.json({ ok: true, results })
  } catch (e) {
    return NextResponse.json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    )
  }
}
