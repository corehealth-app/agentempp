import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'
const svc = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const { data: row } = await svc.from('service_credentials').select('value').eq('service','stripe').eq('key_name','secret_key').maybeSingle()
const stripe = new Stripe(row.value)
// Pega a sub criada antes
const subs = await stripe.subscriptions.list({ limit: 1 })
const sub = subs.data[0]
console.log('sub:', sub.id, 'status:', sub.status)
// Re-emite evento via update (touch metadata)
const updated = await stripe.subscriptions.update(sub.id, {
  metadata: { ...sub.metadata, _touch: String(Date.now()) },
})
console.log('updated, esperando 5s...')
await new Promise(r => setTimeout(r, 5000))
const { data: dbSub } = await svc.from('subscriptions').select('plan,status,provider_subscription_id').eq('provider_subscription_id', updated.id).maybeSingle()
console.log('DB sub:', dbSub)
