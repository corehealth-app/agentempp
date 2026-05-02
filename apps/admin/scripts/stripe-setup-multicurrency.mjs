/**
 * Sincroniza catálogo MPP em modo multi-currency.
 * 1 produto por plano (mensal, anual), N preços (1 por moeda: BRL, USD, EUR).
 * Idempotente.
 */
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const svc = createClient(
  process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false } },
)

const { data: row } = await svc
  .from('service_credentials')
  .select('value')
  .eq('service', 'stripe')
  .eq('key_name', 'secret_key')
  .eq('is_active', true)
  .maybeSingle()
if (!row?.value) {
  console.error('stripe.secret_key ausente')
  process.exit(1)
}
const stripe = new Stripe(row.value)

const CATALOG = [
  {
    name: 'Agente MPP — Mensal',
    description: 'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto.',
    plan: 'mensal',
    interval: 'month',
    trial_days: 7,
    prices: [
      { currency: 'brl', amount: 19700, lookup_key: 'mpp_mensal_brl_v1' },
      { currency: 'usd', amount: 3900, lookup_key: 'mpp_mensal_usd_v1' },
      { currency: 'eur', amount: 3700, lookup_key: 'mpp_mensal_eur_v1' },
    ],
  },
  {
    name: 'Agente MPP — Anual',
    description: 'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto. Plano anual com desconto.',
    plan: 'anual',
    interval: 'year',
    trial_days: 7,
    prices: [
      { currency: 'brl', amount: 116400, lookup_key: 'mpp_anual_brl_v1' },
      { currency: 'usd', amount: 23900, lookup_key: 'mpp_anual_usd_v1' },
      { currency: 'eur', amount: 22900, lookup_key: 'mpp_anual_eur_v1' },
    ],
  },
]

// Lista produtos existentes pra reuso
const allProducts = await stripe.products.list({ limit: 100, active: true })

for (const item of CATALOG) {
  // 1 produto por plano (reuse pelo metadata.plan)
  let product = allProducts.data.find(
    (p) => p.metadata.plan === item.plan && p.metadata.source === 'mpp_admin_setup',
  )
  if (!product) {
    product = await stripe.products.create({
      name: item.name,
      description: item.description,
      metadata: { plan: item.plan, source: 'mpp_admin_setup' },
    })
    console.log(`✓ produto criado: ${item.plan} → ${product.id}`)
  } else {
    console.log(`· produto reusado: ${item.plan} → ${product.id}`)
  }

  // 1 price por moeda
  for (const variant of item.prices) {
    const existing = await stripe.prices.list({
      lookup_keys: [variant.lookup_key],
      active: true,
      limit: 1,
    })
    if (existing.data.length > 0) {
      console.log(`  · EXISTIA  ${variant.lookup_key} → ${existing.data[0].id}`)
      continue
    }
    const price = await stripe.prices.create({
      product: product.id,
      unit_amount: variant.amount,
      currency: variant.currency,
      recurring: { interval: item.interval, interval_count: 1, trial_period_days: item.trial_days },
      lookup_key: variant.lookup_key,
      metadata: { plan: item.plan, currency: variant.currency },
    })
    console.log(`  ✓ CRIADO    ${variant.lookup_key} → ${price.id}`)
  }
}

console.log('\nDone.')
