/**
 * POST /api/stripe/setup-products
 * Idempotente: cria/atualiza produtos+preços no Stripe (catálogo MPP).
 * Apenas admin autenticado.
 */
import { NextResponse } from 'next/server'
import { hasAdminRole, MASTER_ADMIN_ROLES } from '@/lib/admin-rbac'
import { setupStripeProducts } from '@/lib/stripe'
import { createClient } from '@/lib/supabase/server'

export const runtime = 'nodejs'

export async function POST() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'unauthenticated' }, { status: 401 })

  const { data: admin, error: adminError } = await supabase
    .from('admin_users')
    .select('id, role')
    .eq('id', user.id)
    .maybeSingle()
  if (adminError) {
    return NextResponse.json({ error: 'admin lookup failed' }, { status: 500 })
  }
  const adminRole = (admin as unknown as { role: string } | null)?.role
  if (!adminRole || !hasAdminRole(adminRole, MASTER_ADMIN_ROLES)) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 })
  }

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
