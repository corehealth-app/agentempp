import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY

const svc = createClient(SUPABASE_URL, KEY, { auth: { persistSession: false } })

const { data: row } = await svc
  .from('service_credentials')
  .select('value')
  .eq('service', 'stripe')
  .eq('key_name', 'secret_key')
  .eq('is_active', true)
  .maybeSingle()

if (!row?.value) {
  console.error('stripe.secret_key não encontrado em service_credentials')
  process.exit(1)
}

const stripe = new Stripe(row.value)

const CATALOG = [
  {
    name: 'Agente MPP — Mensal',
    description: 'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto.',
    plan: 'mensal',
    price_brl_cents: 19700,
    interval: 'month',
    interval_count: 1,
    lookup_key: 'mpp_mensal_v1',
    trial_days: 7,
  },
  {
    name: 'Agente MPP — Anual',
    description: 'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto. Plano anual com desconto de ~50%.',
    plan: 'anual',
    price_brl_cents: 116400,
    interval: 'year',
    interval_count: 1,
    lookup_key: 'mpp_anual_v1',
    trial_days: 7,
  },
]

for (const item of CATALOG) {
  const existing = await stripe.prices.list({
    lookup_keys: [item.lookup_key],
    active: true,
    expand: ['data.product'],
    limit: 1,
  })
  if (existing.data.length > 0) {
    const p = existing.data[0]
    console.log(`· EXISTIA ${item.lookup_key} → ${p.id} (product ${p.product.id})`)
    continue
  }
  const product = await stripe.products.create({
    name: item.name,
    description: item.description,
    metadata: { plan: item.plan, source: 'mpp_admin_setup' },
  })
  const price = await stripe.prices.create({
    product: product.id,
    unit_amount: item.price_brl_cents,
    currency: 'brl',
    recurring: {
      interval: item.interval,
      interval_count: item.interval_count,
      trial_period_days: item.trial_days,
    },
    lookup_key: item.lookup_key,
    metadata: { plan: item.plan },
  })
  console.log(`✓ CRIADO  ${item.lookup_key} → ${price.id} (product ${product.id})`)
}
