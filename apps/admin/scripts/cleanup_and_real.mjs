import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const svc = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const { data: row } = await svc.from('service_credentials').select('value').eq('service','stripe').eq('key_name','secret_key').maybeSingle()
const stripe = new Stripe(row.value)

// 1. Cancela todas subs de teste
const subs = await stripe.subscriptions.list({ limit: 10 })
for (const s of subs.data) {
  await stripe.subscriptions.cancel(s.id).catch(() => {})
  console.log(`canceled stripe sub ${s.id}`)
}
// E limpa a tabela local pra começar limpo
await svc.from('subscription_events').delete().neq('id', '00000000-0000-0000-0000-000000000000')
await svc.from('subscriptions').delete().neq('id', '00000000-0000-0000-0000-000000000000')
console.log('DB limpa')

// 2. Cria customer + PM + sub TRIAL real (pago automaticamente, sem incomplete)
const { data: u } = await svc.from('users').select('id,wpp,name').eq('id','819e755d-14d4-4893-b252-31874db166ea').maybeSingle()
const customer = await stripe.customers.create({
  name: u.name,
  metadata: { user_id: u.id, wpp: u.wpp },
})
const pm = await stripe.paymentMethods.attach('pm_card_visa', { customer: customer.id })
await stripe.customers.update(customer.id, { invoice_settings: { default_payment_method: pm.id } })

const prices = await stripe.prices.list({ lookup_keys: ['mpp_mensal_v1'], active: true, limit: 1 })
// trial_period_days=7 já está no PRICE → status vai pra 'trialing'
const sub = await stripe.subscriptions.create({
  customer: customer.id,
  items: [{ price: prices.data[0].id }],
  metadata: { user_id: u.id, wpp: u.wpp },
})
console.log(`✓ Sub real criada: ${sub.id} status=${sub.status}`)
await new Promise(r => setTimeout(r, 6000))

const { data: dbSub } = await svc.from('subscriptions').select('plan,status,trial_ends_at,current_period_end,provider_subscription_id').eq('provider_subscription_id', sub.id).maybeSingle()
console.log('Webhook persistiu:', dbSub)

const { data: events } = await svc.from('subscription_events').select('event_type, created_at').order('created_at',{ascending:false}).limit(5)
console.log('\nEventos:')
for (const e of events) console.log(`  ${e.created_at.slice(11,19)} ${e.event_type}`)
