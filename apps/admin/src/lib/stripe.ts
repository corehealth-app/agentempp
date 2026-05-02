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
export interface CatalogPlan {
  name: string
  description: string
  plan: 'mensal' | 'anual'
  interval: 'month' | 'year'
  interval_count: number
  trial_days: number
  /** lookup_keys por moeda. Cada moeda vira 1 price separado, mesmo product. */
  prices: Array<{
    currency: 'brl' | 'usd' | 'eur'
    unit_amount: number
    lookup_key: string // ex: mpp_mensal_brl_v1, mpp_mensal_usd_v1
  }>
}

/**
 * Catálogo MPP multi-moeda. Stripe permite N preços por produto, 1 por moeda.
 * Pipeline escolhe a moeda baseado em user.country.
 */
export const STRIPE_CATALOG: CatalogPlan[] = [
  {
    name: 'Agente MPP — Mensal',
    description: 'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto.',
    plan: 'mensal',
    interval: 'month',
    interval_count: 1,
    trial_days: 7,
    prices: [
      { currency: 'brl', unit_amount: 19700, lookup_key: 'mpp_mensal_brl_v1' },
      { currency: 'usd', unit_amount: 3900, lookup_key: 'mpp_mensal_usd_v1' },
      { currency: 'eur', unit_amount: 3700, lookup_key: 'mpp_mensal_eur_v1' },
    ],
  },
  {
    name: 'Agente MPP — Anual',
    description:
      'Acompanhamento nutricional contínuo via WhatsApp com Dr. Roberto. Plano anual com desconto.',
    plan: 'anual',
    interval: 'year',
    interval_count: 1,
    trial_days: 7,
    prices: [
      { currency: 'brl', unit_amount: 116400, lookup_key: 'mpp_anual_brl_v1' },
      { currency: 'usd', unit_amount: 23900, lookup_key: 'mpp_anual_usd_v1' },
      { currency: 'eur', unit_amount: 22900, lookup_key: 'mpp_anual_eur_v1' },
    ],
  },
]

/**
 * Country → currency. Fallback: USD pra qualquer país desconhecido.
 */
const COUNTRY_TO_CURRENCY: Record<string, 'brl' | 'usd' | 'eur'> = {
  BR: 'brl',
  PT: 'eur',
  ES: 'eur',
  DE: 'eur',
  FR: 'eur',
  IT: 'eur',
  NL: 'eur',
  IE: 'eur',
  AT: 'eur',
  // Tudo no resto, principalmente LATAM/US/UK → USD
}
export function currencyForCountry(country: string | null | undefined): 'brl' | 'usd' | 'eur' {
  if (!country) return 'brl'
  return COUNTRY_TO_CURRENCY[country] ?? 'usd'
}

/**
 * Backward-compat alias: lookup_key legacy ('mpp_mensal_v1') → BRL price.
 * Webhook recebe lookup_key e mapeia pra plan; suportamos ambos formatos.
 */
export function planFromLookupKey(lookup_key: string): 'mensal' | 'anual' {
  if (lookup_key.includes('anual')) return 'anual'
  return 'mensal'
}

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
    currency: string
    product_id: string
    price_id: string
    created: boolean
  }> = []

  for (const item of STRIPE_CATALOG) {
    // 1 produto compartilhado por plano (mensal ou anual). Preços são variantes.
    let productId: string | null = null

    // Tenta achar o produto pelo metadata.plan
    const products = await stripe.products.list({ limit: 100, active: true })
    const existingProduct = products.data.find(
      (p) => p.metadata.plan === item.plan && p.metadata.source === 'mpp_admin_setup',
    )
    if (existingProduct) {
      productId = existingProduct.id
    } else {
      const created = await stripe.products.create({
        name: item.name,
        description: item.description,
        metadata: { plan: item.plan, source: 'mpp_admin_setup' },
      })
      productId = created.id
    }

    // Pra cada moeda, garante 1 price com lookup_key estável
    for (const variant of item.prices) {
      const existing = await stripe.prices.list({
        lookup_keys: [variant.lookup_key],
        active: true,
        limit: 1,
      })

      if (existing.data.length > 0) {
        results.push({
          lookup_key: variant.lookup_key,
          currency: variant.currency,
          product_id: productId,
          price_id: existing.data[0]!.id,
          created: false,
        })
        continue
      }

      const price = await stripe.prices.create({
        product: productId,
        unit_amount: variant.unit_amount,
        currency: variant.currency,
        recurring: {
          interval: item.interval,
          interval_count: item.interval_count,
          trial_period_days: item.trial_days,
        },
        lookup_key: variant.lookup_key,
        metadata: { plan: item.plan, currency: variant.currency },
      })

      results.push({
        lookup_key: variant.lookup_key,
        currency: variant.currency,
        product_id: productId,
        price_id: price.id,
        created: true,
      })
    }
  }

  return results
}

/**
 * Cria uma Checkout Session pra um user dado.
 *
 * lookup_key pode ser legacy (ex: 'mpp_mensal_v1') ou multi-currency
 * (ex: 'mpp_mensal_brl_v1'). Se for legacy, usa user_country pra escolher
 * variante de moeda automaticamente.
 */
export async function createCheckoutSession(opts: {
  lookup_key: string
  user_id: string
  user_wpp: string
  user_email?: string | null
  user_name?: string | null
  user_country?: string | null
  success_url: string
  cancel_url: string
}): Promise<{ url: string; session_id: string }> {
  const stripe = await getStripe()
  if (!stripe) throw new Error('Stripe não configurado')

  // Se vier lookup_key legacy ('mpp_mensal_v1'), upgrada pra variante por moeda
  let resolvedLookup = opts.lookup_key
  if (!/_brl_|_usd_|_eur_/.test(opts.lookup_key)) {
    const plan = planFromLookupKey(opts.lookup_key)
    const currency = currencyForCountry(opts.user_country)
    const planEntry = STRIPE_CATALOG.find((p) => p.plan === plan)
    const variant = planEntry?.prices.find((v) => v.currency === currency)
    if (variant) {
      resolvedLookup = variant.lookup_key
    }
    // Se não achar variante na moeda do país, mantém o lookup original (BRL)
  }

  const prices = await stripe.prices.list({
    lookup_keys: [resolvedLookup],
    active: true,
    limit: 1,
  })
  const price = prices.data[0]
  if (!price)
    throw new Error(
      `Preço com lookup_key=${resolvedLookup} não existe. Rode setup-products.`,
    )

  const localeByCountry: Record<string, string> = {
    BR: 'pt-BR',
    PT: 'pt',
    ES: 'es',
    MX: 'es',
    AR: 'es',
    CL: 'es',
    CO: 'es',
    PE: 'es',
    UY: 'es',
    PY: 'es',
    BO: 'es',
    EC: 'es',
    VE: 'es',
    US: 'en',
    GB: 'en',
    CA: 'en',
    AU: 'en',
    FR: 'fr',
    DE: 'de',
    IT: 'it',
  }
  const locale = localeByCountry[opts.user_country ?? 'BR'] ?? 'auto'

  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    line_items: [{ price: price.id, quantity: 1 }],
    customer_email: opts.user_email ?? undefined,
    success_url: opts.success_url,
    cancel_url: opts.cancel_url,
    // biome-ignore lint/suspicious/noExplicitAny: Stripe.Locale string union too restrictive
    locale: locale as never,
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
