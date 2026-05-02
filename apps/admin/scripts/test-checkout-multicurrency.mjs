import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const svc = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false } },
)
const { data: row } = await svc.from('service_credentials').select('value').eq('service','stripe').eq('key_name','secret_key').maybeSingle()
const stripe = new Stripe(row.value)

// Pegando os 3 users fake
const { data: users } = await svc.from('users').select('id,name,wpp,country').in('wpp', ['16505551234','34611223344','351912345678'])

const COUNTRY_TO_CURRENCY = { BR: 'brl', PT: 'eur', ES: 'eur', US: 'usd', GB: 'usd' }
const localeByCountry = { BR: 'pt-BR', PT: 'pt', ES: 'es', US: 'en' }

for (const u of users) {
  const currency = COUNTRY_TO_CURRENCY[u.country] ?? 'usd'
  const lookupKey = `mpp_mensal_${currency}_v1`
  const prices = await stripe.prices.list({ lookup_keys: [lookupKey], active: true, limit: 1 })
  if (prices.data.length === 0) {
    console.log(`✗ ${u.name} (${u.country}): preço ${lookupKey} não existe`)
    continue
  }
  const price = prices.data[0]
  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    line_items: [{ price: price.id, quantity: 1 }],
    success_url: 'https://agentempp.vercel.app/users/'+u.id+'?stripe=success',
    cancel_url: 'https://agentempp.vercel.app/users/'+u.id+'?stripe=cancel',
    locale: localeByCountry[u.country] ?? 'auto',
    metadata: { user_id: u.id, wpp: u.wpp, country: u.country },
    subscription_data: { metadata: { user_id: u.id, wpp: u.wpp } },
  })
  const symbol = currency==='brl'?'R$':currency==='usd'?'US$':'€'
  const amount = (price.unit_amount/100).toFixed(2)
  console.log(`✓ ${u.name.padEnd(20)} (${u.country}) → ${currency.toUpperCase()} ${symbol} ${amount}`)
  console.log(`  ${session.url.slice(0, 90)}...`)
}
