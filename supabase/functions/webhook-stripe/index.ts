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
 * Idempotência: claim/finalização atômicos em subscription_events. Eventos
 * falhos continuam elegíveis para retry; apenas `processed` vira duplicata.
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
  const { data, error } = await client
    .from('service_credentials')
    .select('value')
    .eq('service', service)
    .eq('key_name', keyName)
    .eq('is_active', true)
    .maybeSingle()
  if (error) throw new Error(`credential lookup failed: ${error.message}`)
  return (data as { value: string } | null)?.value ?? null
}

async function getStripeClient(): Promise<Stripe | null> {
  if (cachedStripe) return cachedStripe
  const key = await getCredential(supabase, 'stripe', 'secret_key')
  if (!key) return null
  cachedStripe = new Stripe(key, {
    apiVersion: '2024-12-18.acacia',
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

type BillingEventContext = {
  user_id?: string
  subscription_id?: string
  amount_cents?: number
  currency?: string
}

async function claimSubscriptionEvent(
  event: Stripe.Event,
): Promise<'claimed' | 'duplicate' | 'in_progress'> {
  const { data, error } = await supabase.rpc('claim_subscription_event', {
    p_provider_event_id: event.id,
    p_event_type: event.type,
    p_payload: JSON.parse(JSON.stringify(event)),
  })
  if (error) throw new Error(`subscription event claim failed: ${error.message}`)
  const status = (data as { status?: string } | null)?.status
  if (status !== 'claimed' && status !== 'duplicate' && status !== 'in_progress') {
    throw new Error(`invalid subscription event claim status: ${status ?? 'missing'}`)
  }
  return status
}

async function finishSubscriptionEvent(
  providerEventId: string,
  success: boolean,
  context: BillingEventContext,
  errorMessage?: string,
): Promise<void> {
  const { error } = await supabase.rpc('finish_subscription_event', {
    p_provider_event_id: providerEventId,
    p_success: success,
    p_context: context,
    p_error: errorMessage ?? null,
  })
  if (error) throw new Error(`subscription event finalization failed: ${error.message}`)
}

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

  let claim: 'claimed' | 'duplicate' | 'in_progress'
  try {
    claim = await claimSubscriptionEvent(event)
  } catch (err) {
    console.error('event claim failed:', err)
    return new Response('event claim failed', { status: 500 })
  }
  if (claim === 'duplicate') {
    return new Response('ok (duplicate)', { status: 200 })
  }
  if (claim === 'in_progress') {
    return new Response('event already in progress', { status: 500 })
  }

  let eventContext: BillingEventContext = {}
  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        eventContext = await handleCheckoutCompleted(stripe, session)
        break
      }
      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription
        eventContext = await handleSubscriptionUpsert(sub)
        break
      }
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription
        eventContext = await handleSubscriptionCanceled(sub)
        break
      }
      case 'invoice.payment_succeeded': {
        const invoice = event.data.object as Stripe.Invoice
        eventContext = {
          amount_cents: invoice.amount_paid,
          currency: invoice.currency,
        }
        if (invoice.subscription) {
          const subId =
            typeof invoice.subscription === 'string'
              ? invoice.subscription
              : invoice.subscription.id
          eventContext = {
            ...eventContext,
            ...(await markSubscriptionStatus(subId, 'active')),
          }
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
          eventContext = await markSubscriptionStatus(subId, 'past_due')
        }
        break
      }
      default:
        console.log('unhandled event type:', event.type)
    }
    await finishSubscriptionEvent(event.id, true, eventContext)
    return new Response('ok', { status: 200 })
  } catch (err) {
    console.error('handler error:', err)
    const message = err instanceof Error ? err.message : String(err)
    try {
      await finishSubscriptionEvent(event.id, false, {}, message)
    } catch (finishError) {
      console.error('failed to persist handler failure:', finishError)
    }
    return new Response('handler failed', { status: 500 })
  }
})

async function handleCheckoutCompleted(
  stripe: Stripe,
  session: Stripe.Checkout.Session,
): Promise<BillingEventContext> {
  if (!session.subscription) throw new Error('checkout session has no subscription')

  // Mapeia user: prioridade metadata.user_id > metadata.wpp > customer_email
  let userId = session.metadata?.user_id ?? null

  if (!userId && session.metadata?.wpp) {
    const { data: u, error } = await supabase
      .from('users')
      .select('id')
      .eq('wpp', session.metadata.wpp)
      .maybeSingle()
    if (error) throw new Error(`checkout user lookup by wpp failed: ${error.message}`)
    userId = (u as { id: string } | null)?.id ?? null
  }

  if (!userId && session.customer_email) {
    const { data: u, error } = await supabase
      .from('users')
      .select('id')
      .eq('email', session.customer_email)
      .maybeSingle()
    if (error) throw new Error(`checkout user lookup by email failed: ${error.message}`)
    userId = (u as { id: string } | null)?.id ?? null
  }

  if (!userId) {
    throw new Error(`checkout session ${session.id} has no mapped user`)
  }

  const subId =
    typeof session.subscription === 'string' ? session.subscription : session.subscription.id
  const subscription = await stripe.subscriptions.retrieve(subId)
  return await upsertSubscription(userId, subscription)
}

async function handleSubscriptionUpsert(sub: Stripe.Subscription): Promise<BillingEventContext> {
  let userId = sub.metadata?.user_id ?? null
  if (!userId) {
    const { data, error } = await supabase
      .from('subscriptions')
      .select('user_id')
      .eq('provider_subscription_id', sub.id)
      .maybeSingle()
    if (error) throw new Error(`subscription owner lookup failed: ${error.message}`)
    userId = (data as { user_id?: string } | null)?.user_id ?? null
  }
  if (!userId) throw new Error(`subscription ${sub.id} has no mapped user`)
  return await upsertSubscription(userId, sub)
}

async function handleSubscriptionCanceled(sub: Stripe.Subscription): Promise<BillingEventContext> {
  const { data, error } = await supabase
    .from('subscriptions')
    .update({
      status: 'canceled',
      cancel_at_period_end: false,
      updated_at: new Date().toISOString(),
    })
    .eq('provider_subscription_id', sub.id)
    .select('id, user_id')
    .maybeSingle()
  if (error) throw new Error(`subscription cancellation failed: ${error.message}`)
  if (!data) throw new Error(`subscription ${sub.id} not found for cancellation`)
  const row = data as { id: string; user_id: string }
  return { subscription_id: row.id, user_id: row.user_id }
}

function tsToIso(ts: number | null | undefined): string | null {
  if (!ts || typeof ts !== 'number' || !Number.isFinite(ts)) return null
  return new Date(ts * 1000).toISOString()
}

async function upsertSubscription(
  userId: string,
  sub: Stripe.Subscription,
): Promise<BillingEventContext> {
  const lookup = sub.items.data[0]?.price?.lookup_key ?? ''
  const plan = lookup.includes('anual') ? 'anual' : lookup.includes('trial') ? 'trial' : 'mensal'

  // Subscription pode estar 'incomplete' (sem first invoice paga ainda),
  // 'incomplete_expired', 'unpaid', etc. Mapeamos pro enum do nosso domínio.
  const status =
    sub.status === 'active'
      ? 'active'
      : sub.status === 'trialing'
        ? 'trial'
        : sub.status === 'past_due'
          ? 'past_due'
          : sub.status === 'canceled' || sub.status === 'incomplete_expired'
            ? 'canceled'
            : sub.status === 'incomplete' || sub.status === 'unpaid'
              ? 'past_due'
              : 'expired'

  const { data, error } = await supabase
    .from('subscriptions')
    .upsert(
      {
        user_id: userId,
        provider: 'stripe',
        provider_subscription_id: sub.id,
        plan,
        status,
        current_period_start: tsToIso(sub.current_period_start),
        current_period_end: tsToIso(sub.current_period_end),
        trial_ends_at: tsToIso(sub.trial_end),
        cancel_at_period_end: sub.cancel_at_period_end,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'provider_subscription_id' },
    )
    .select('id, user_id')
    .single()
  if (error) throw new Error(`subscription upsert failed: ${error.message}`)
  const row = data as { id: string; user_id: string }
  return { subscription_id: row.id, user_id: row.user_id }
}

async function markSubscriptionStatus(
  providerSubId: string,
  status: string,
): Promise<BillingEventContext> {
  const { data, error } = await supabase
    .from('subscriptions')
    .update({ status, updated_at: new Date().toISOString() })
    .eq('provider_subscription_id', providerSubId)
    .select('id, user_id')
    .maybeSingle()
  if (error) throw new Error(`subscription status update failed: ${error.message}`)
  if (!data) throw new Error(`subscription ${providerSubId} not found for status update`)
  const row = data as { id: string; user_id: string }
  return { subscription_id: row.id, user_id: row.user_id }
}
