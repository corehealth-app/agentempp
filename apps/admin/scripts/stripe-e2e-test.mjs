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

// Pega 1º user real
const { data: users } = await svc
  .from('users')
  .select('id, wpp, name, email')
  .neq('wpp', '5511988887777')
  .order('created_at', { ascending: false })
  .limit(1)
const u = users[0]
console.log(`User test: ${u.name ?? '(sem nome)'} (wpp=${u.wpp}, id=${u.id.slice(0, 8)})`)

// Cria checkout session
const prices = await stripe.prices.list({
  lookup_keys: ['mpp_mensal_v1'],
  active: true,
  limit: 1,
})
const session = await stripe.checkout.sessions.create({
  mode: 'subscription',
  payment_method_types: ['card'],
  line_items: [{ price: prices.data[0].id, quantity: 1 }],
  success_url: 'https://agentempp.vercel.app/users/' + u.id + '?stripe=success',
  cancel_url: 'https://agentempp.vercel.app/users/' + u.id + '?stripe=cancel',
  locale: 'pt-BR',
  metadata: { user_id: u.id, wpp: u.wpp },
  subscription_data: { metadata: { user_id: u.id, wpp: u.wpp } },
})
console.log(`✓ Checkout criado: ${session.id}`)
console.log(`  URL: ${session.url}`)
console.log()
console.log('Pra completar o teste, ABRIR a URL acima e pagar com cartão 4242 4242 4242 4242, qualquer data futura, qualquer CVV.')
console.log()
console.log(`Após o pagamento, em ~5s a webhook deve disparar e criar a row em subscriptions.`)
console.log(`Verifica com:`)
console.log(`  curl ${process.env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${u.id} -H "apikey: ..."`)
