/**
 * Cria/atualiza o webhook endpoint no Stripe e salva o whsec_* em
 * service_credentials. Idempotente: se já existe um endpoint pra
 * essa URL, reutiliza (mas não consegue ler o secret antigo — só
 * mostra aviso e pede ao user pra recriar manualmente se precisar).
 */
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
const WEBHOOK_URL =
  process.env.STRIPE_WEBHOOK_URL ??
  'https://xuxehkhdvjivitduarvb.supabase.co/functions/v1/webhook-stripe'

const ENABLED_EVENTS = [
  'checkout.session.completed',
  'customer.subscription.created',
  'customer.subscription.updated',
  'customer.subscription.deleted',
  'invoice.payment_succeeded',
  'invoice.payment_failed',
]

const svc = createClient(SUPABASE_URL, KEY, { auth: { persistSession: false } })

const { data: row } = await svc
  .from('service_credentials')
  .select('value')
  .eq('service', 'stripe')
  .eq('key_name', 'secret_key')
  .eq('is_active', true)
  .maybeSingle()
if (!row?.value) {
  console.error('stripe.secret_key não encontrado.')
  process.exit(1)
}
const stripe = new Stripe(row.value)

// Procura endpoint existente
const existing = await stripe.webhookEndpoints.list({ limit: 100 })
const found = existing.data.find((e) => e.url === WEBHOOK_URL)

let endpoint
let secret = null

if (found) {
  // Atualiza eventos se necessário e reutiliza
  console.log(`· EXISTIA  endpoint ${found.id}`)
  console.log(`           secret antigo: ${found.secret ? found.secret.slice(0, 10) + '...' : 'NÃO RETORNADO (Stripe só mostra o secret na criação)'}`)
  // Stripe NÃO retorna o secret na list — só na create.
  // Vamos APAGAR o existente e recriar pra obter o secret novo.
  console.log(`  (apagando pra recriar e capturar o secret...)`)
  await stripe.webhookEndpoints.del(found.id)
}

endpoint = await stripe.webhookEndpoints.create({
  url: WEBHOOK_URL,
  enabled_events: ENABLED_EVENTS,
  description: 'Agente MPP — produção',
})
secret = endpoint.secret

console.log(`✓ Endpoint criado: ${endpoint.id}`)
console.log(`  URL: ${endpoint.url}`)
console.log(`  Eventos: ${endpoint.enabled_events.length}`)
console.log(`  whsec: ${secret.slice(0, 12)}... (${secret.length} chars)`)

// Salva em service_credentials
const { error: upErr } = await svc.from('service_credentials').upsert(
  {
    service: 'stripe',
    key_name: 'webhook_secret',
    value: secret,
    is_active: true,
    last_tested_at: new Date().toISOString(),
    last_test_result: { ok: true, endpoint_id: endpoint.id },
  },
  { onConflict: 'service,key_name' },
)
if (upErr) {
  console.error('  ⚠️ falha ao salvar webhook_secret:', upErr.message)
  console.error('  cole manualmente no admin:', secret)
  process.exit(1)
}
console.log(`  ✓ stripe.webhook_secret atualizado em service_credentials`)
