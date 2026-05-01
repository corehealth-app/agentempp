/**
 * Stripe helper: lazy-load do client + leitura de credenciais do DB.
 * Server-only (não importar no client).
 */
import 'server-only'
import Stripe from 'stripe'
import { createServiceClient } from './supabase/server'

let cached: Stripe | null = null

async function loadCredential(service: string, keyName: string): Promise<string | null> {
  const svc = createServiceClient()
  const { data } = await svc
    .from('service_credentials')
    .select('value')
    .eq('service', service)
    .eq('key_name', keyName)
    .eq('is_active', true)
    .maybeSingle()
  return (data as { value: string } | null)?.value ?? null
}

export async function getStripe(): Promise<Stripe | null> {
  if (cached) return cached
  const key = await loadCredential('stripe', 'secret_key')
  if (!key) return null
  cached = new Stripe(key)
  return cached
}

export async function getStripeStatus(): Promise<{
  hasSecret: boolean
  hasPublishable: boolean
  hasWebhookSecret: boolean
  publishableKey: string | null
}> {
  const [secret, publishable, webhook] = await Promise.all([
    loadCredential('stripe', 'secret_key'),
    loadCredential('stripe', 'publishable_key'),
    loadCredential('stripe', 'webhook_secret'),
  ])
  return {
    hasSecret: !!secret,
    hasPublishable: !!publishable,
    hasWebhookSecret: !!webhook,
    publishableKey: publishable,
  }
}

/**
 * Catálogo de produtos do MPP.
 * lookup_key é a "chave estável" usada pelo webhook pra mapear price→plan.
 */
export const STRIPE_CATALOG = [
  {
    name: 'Agente MPP — Mensal',
    description: 'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto.',
    plan: 'mensal' as const,
    price_brl_cents: 19700,
    interval: 'month' as const,
    interval_count: 1,
    lookup_key: 'mpp_mensal_v1',
    trial_days: 7,
  },
  {
    name: 'Agente MPP — Anual',
    description:
      'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto. Plano anual com desconto de ~50%.',
    plan: 'anual' as const,
    price_brl_cents: 116400, // 12×9700 = R$1.164/ano
    interval: 'year' as const,
    interval_count: 1,
    lookup_key: 'mpp_anual_v1',
    trial_days: 7,
  },
]

/**
 * Cria/atualiza produtos+preços no Stripe segundo STRIPE_CATALOG.
 * Idempotente: usa lookup_key como chave estável.
 */
export async function setupStripeProducts(): Promise<
  Array<{ lookup_key: string; product_id: string; price_id: string; created: boolean }>
> {
  const stripe = await getStripe()
  if (!stripe) throw new Error('Stripe não configurado (stripe.secret_key ausente)')

  const results: Array<{
    lookup_key: string
    product_id: string
    price_id: string
    created: boolean
  }> = []

  for (const item of STRIPE_CATALOG) {
    // Procura preço por lookup_key (idempotência)
    const existing = await stripe.prices.list({
      lookup_keys: [item.lookup_key],
      active: true,
      expand: ['data.product'],
      limit: 1,
    })

    if (existing.data.length > 0) {
      const price = existing.data[0]!
      const product = price.product as Stripe.Product
      results.push({
        lookup_key: item.lookup_key,
        product_id: product.id,
        price_id: price.id,
        created: false,
      })
      continue
    }

    // Cria produto + price
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

    results.push({
      lookup_key: item.lookup_key,
      product_id: product.id,
      price_id: price.id,
      created: true,
    })
  }

  return results
}

/**
 * Cria uma Checkout Session pra um user dado.
 */
export async function createCheckoutSession(opts: {
  lookup_key: string
  user_id: string
  user_wpp: string
  user_email?: string | null
  user_name?: string | null
  success_url: string
  cancel_url: string
}): Promise<{ url: string; session_id: string }> {
  const stripe = await getStripe()
  if (!stripe) throw new Error('Stripe não configurado')

  const prices = await stripe.prices.list({
    lookup_keys: [opts.lookup_key],
    active: true,
    limit: 1,
  })
  const price = prices.data[0]
  if (!price) throw new Error(`Preço com lookup_key=${opts.lookup_key} não existe. Rode setup-products.`)

  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    line_items: [{ price: price.id, quantity: 1 }],
    customer_email: opts.user_email ?? undefined,
    success_url: opts.success_url,
    cancel_url: opts.cancel_url,
    locale: 'pt-BR',
    metadata: {
      user_id: opts.user_id,
      wpp: opts.user_wpp,
      ...(opts.user_name ? { user_name: opts.user_name } : {}),
    },
    subscription_data: {
      metadata: {
        user_id: opts.user_id,
        wpp: opts.user_wpp,
      },
    },
  })

  if (!session.url) throw new Error('Stripe não retornou URL de checkout')
  return { url: session.url, session_id: session.id }
}
