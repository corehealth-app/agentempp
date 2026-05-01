/**
 * Stripe webhook — processa eventos de billing.
 *
 * Eventos tratados:
 *   - checkout.session.completed     → cria/atualiza subscription
 *   - customer.subscription.updated  → atualiza status + period
 *   - customer.subscription.deleted  → marca como canceled
 *   - invoice.payment_succeeded      → renew (active)
 *   - invoice.payment_failed         → past_due
 *
 * Idempotência: provider_event_id UNIQUE em subscription_events.
 *
 * Configuração: lê stripe.secret_key e stripe.webhook_secret de
 * service_credentials. Cache por instância da Edge Function.
 */
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@17?target=deno'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

let cachedStripe: Stripe | null = null
let cachedWebhookSecret: string | null = null

async function getCredential(
  client: SupabaseClient,
  service: string,
  keyName: string,
): Promise<string | null> {
  const { data } = await client
    .from('service_credentials')
    .select('value')
    .eq('service', service)
    .eq('key_name', keyName)
    .eq('is_active', true)
    .maybeSingle()
  return (data as { value: string } | null)?.value ?? null
}

async function getStripeClient(): Promise<Stripe | null> {
  if (cachedStripe) return cachedStripe
  const key = await getCredential(supabase, 'stripe', 'secret_key')
  if (!key) return null
  cachedStripe = new Stripe(key, {
    apiVersion: '2024-12-18.acacia',
    // @ts-expect-error — Deno fetch
    httpClient: Stripe.createFetchHttpClient(),
  })
  return cachedStripe
}

async function getWebhookSecret(): Promise<string | null> {
  if (cachedWebhookSecret) return cachedWebhookSecret
  const s = await getCredential(supabase, 'stripe', 'webhook_secret')
  if (s) cachedWebhookSecret = s
  return s
}

const cryptoProvider = Stripe.createSubtleCryptoProvider()

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 })
  }

  const stripe = await getStripeClient()
  if (!stripe) {
    return new Response('stripe.secret_key não configurado', { status: 500 })
  }

  const signature = req.headers.get('Stripe-Signature')
  if (!signature) return new Response('missing signature', { status: 400 })

  const webhookSecret = await getWebhookSecret()
  if (!webhookSecret) {
    return new Response('stripe.webhook_secret não configurado', { status: 500 })
  }

  const rawBody = await req.text()

  let event: Stripe.Event
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      webhookSecret,
      undefined,
      cryptoProvider,
    )
  } catch (err) {
    console.error('webhook signature failed:', err)
    return new Response('invalid signature', { status: 400 })
  }

  // Idempotência: tenta inserir o evento; UNIQUE em provider_event_id
  const { error: dupErr } = await supabase.from('subscription_events').insert({
    provider_event_id: event.id,
    event_type: event.type,
    payload: JSON.parse(JSON.stringify(event)),
  })
  if (dupErr?.code === '23505') {
    return new Response('ok (duplicate)', { status: 200 })
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        await handleCheckoutCompleted(stripe, session)
        break
      }
      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription
        await handleSubscriptionUpsert(sub)
        break
      }
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription
        await handleSubscriptionCanceled(sub)
        break
      }
      case 'invoice.payment_succeeded': {
        const invoice = event.data.object as Stripe.Invoice
        if (invoice.subscription) {
          const subId =
            typeof invoice.subscription === 'string'
              ? invoice.subscription
              : invoice.subscription.id
          await markSubscriptionStatus(subId, 'active')
          // grava o valor pago no event para MRR
          await supabase
            .from('subscription_events')
            .update({ amount_cents: invoice.amount_paid, currency: invoice.currency })
            .eq('provider_event_id', event.id)
        }
        break
      }
      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        if (invoice.subscription) {
          const subId =
            typeof invoice.subscription === 'string'
              ? invoice.subscription
              : invoice.subscription.id
          await markSubscriptionStatus(subId, 'past_due')
        }
        break
      }
      default:
        console.log('unhandled event type:', event.type)
    }
    return new Response('ok', { status: 200 })
  } catch (err) {
    console.error('handler error:', err)
    return new Response('handler failed', { status: 500 })
  }
})

async function handleCheckoutCompleted(stripe: Stripe, session: Stripe.Checkout.Session) {
  if (!session.subscription) return

  // Mapeia user: prioridade metadata.user_id > metadata.wpp > customer_email
  let userId = session.metadata?.user_id ?? null

  if (!userId && session.metadata?.wpp) {
    const { data: u } = await supabase
      .from('users')
      .select('id')
      .eq('wpp', session.metadata.wpp)
      .maybeSingle()
    userId = (u as { id: string } | null)?.id ?? null
  }

  if (!userId && session.customer_email) {
    const { data: u } = await supabase
      .from('users')
      .select('id')
      .eq('email', session.customer_email)
      .maybeSingle()
    userId = (u as { id: string } | null)?.id ?? null
  }

  if (!userId) {
    console.warn('checkout.completed sem user mapeado:', session.id)
    return
  }

  const subId =
    typeof session.subscription === 'string' ? session.subscription : session.subscription.id
  const subscription = await stripe.subscriptions.retrieve(subId)
  await upsertSubscription(userId, subscription)
}

async function handleSubscriptionUpsert(sub: Stripe.Subscription) {
  const userId = sub.metadata?.user_id ?? null
  if (!userId) return
  await upsertSubscription(userId, sub)
}

async function handleSubscriptionCanceled(sub: Stripe.Subscription) {
  await supabase
    .from('subscriptions')
    .update({
      status: 'canceled',
      cancel_at_period_end: false,
      updated_at: new Date().toISOString(),
    })
    .eq('provider_subscription_id', sub.id)
}

async function upsertSubscription(userId: string, sub: Stripe.Subscription) {
  const lookup = sub.items.data[0]?.price?.lookup_key ?? ''
  const plan = lookup.includes('anual')
    ? 'anual'
    : lookup.includes('trial')
      ? 'trial'
      : 'mensal'

  const status =
    sub.status === 'active'
      ? 'active'
      : sub.status === 'trialing'
        ? 'trial'
        : sub.status === 'past_due'
          ? 'past_due'
          : sub.status === 'canceled'
            ? 'canceled'
            : 'expired'

  await supabase.from('subscriptions').upsert(
    {
      user_id: userId,
      provider: 'stripe',
      provider_subscription_id: sub.id,
      plan,
      status,
      current_period_start: new Date(sub.current_period_start * 1000).toISOString(),
      current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
      trial_ends_at: sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : null,
      cancel_at_period_end: sub.cancel_at_period_end,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'provider_subscription_id' },
  )
}

async function markSubscriptionStatus(providerSubId: string, status: string) {
  await supabase
    .from('subscriptions')
    .update({ status, updated_at: new Date().toISOString() })
    .eq('provider_subscription_id', providerSubId)
}
