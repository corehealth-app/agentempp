/**
 * Simula um paciente comprando: cria customer + payment method + subscription.
 * Stripe dispara checkout.session.completed → invoice.paid → o webhook real
 * persiste em subscriptions.
 */
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const svc = createClient(
  process.env.SUPABASE_URL,
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
const stripe = new Stripe(row.value)

// User real
const { data: users } = await svc
  .from('users')
  .select('id, wpp, name')
  .neq('wpp', '5511988887777')
  .order('created_at', { ascending: false })
  .limit(1)
const u = users[0]
console.log(`User: ${u.name} (${u.wpp})`)

// 1. Cria customer
const customer = await stripe.customers.create({
  name: u.name,
  metadata: { user_id: u.id, wpp: u.wpp },
  description: `MPP test customer for ${u.wpp}`,
})
console.log(`✓ Customer ${customer.id}`)

// 2. Anexa um test payment method (token tok_visa)
// Em test mode, podemos criar PM com card_data direta — mas Stripe recomenda
// usar pm_card_visa que já é um PM pronto.
const pm = await stripe.paymentMethods.attach('pm_card_visa', {
  customer: customer.id,
})
await stripe.customers.update(customer.id, {
  invoice_settings: { default_payment_method: pm.id },
})
console.log(`✓ PaymentMethod ${pm.id} attached as default`)

// 3. Pega price mensal
const prices = await stripe.prices.list({ lookup_keys: ['mpp_mensal_v1'], active: true, limit: 1 })
const priceId = prices.data[0].id

// 4. Cria subscription. Como tem trial_period_days=7 no preço, vai ficar como trialing.
const sub = await stripe.subscriptions.create({
  customer: customer.id,
  items: [{ price: priceId }],
  metadata: { user_id: u.id, wpp: u.wpp },
  payment_behavior: 'default_incomplete',
  payment_settings: { save_default_payment_method: 'on_subscription' },
  expand: ['latest_invoice.payment_intent'],
})
console.log(`✓ Subscription ${sub.id} status=${sub.status}`)
console.log(`  trial_end: ${sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : 'none'}`)
console.log(`  current_period_end: ${new Date(sub.current_period_end * 1000).toISOString()}`)

console.log()
console.log('⏳ Aguardando 8s para webhook processar...')
await new Promise((r) => setTimeout(r, 8000))

const { data: dbSub } = await svc
  .from('subscriptions')
  .select('*')
  .eq('user_id', u.id)
  .order('updated_at', { ascending: false })
  .limit(1)
  .maybeSingle()

if (dbSub) {
  console.log(`✓ Webhook funcionou! Row em subscriptions:`)
  console.log(`  plan=${dbSub.plan} status=${dbSub.status} provider_subscription_id=${dbSub.provider_subscription_id}`)
} else {
  console.log(`✗ Sem row em subscriptions. Verifica logs da edge function.`)
}

const { data: events } = await svc
  .from('subscription_events')
  .select('event_type, created_at')
  .order('created_at', { ascending: false })
  .limit(5)
console.log(`\nÚltimos eventos webhook:`)
for (const e of events ?? []) {
  console.log(`  ${e.created_at} ${e.event_type}`)
}
