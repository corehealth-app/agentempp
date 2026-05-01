/**
 * Stripe webhook — processa eventos de billing.
 *
 * Eventos tratados:
 *   - checkout.session.completed     → cria/atualiza subscription
 *   - customer.subscription.updated  → atualiza status + period
 *   - customer.subscription.deleted  → marca como canceled
 *   - invoice.payment_succeeded      → renew
 *   - invoice.payment_failed         → past_due
 *
 * Idempotência: provider_event_id UNIQUE em subscription_events.
 *
 * Configuração necessária:
 *   - STRIPE_SECRET_KEY (env)
 *   - STRIPE_WEBHOOK_SECRET (env)
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@17?target=deno'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
)

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-12-18.acacia',
  // @ts-expect-error — Deno fetch
  httpClient: Stripe.createFetchHttpClient(),
})

const cryptoProvider = Stripe.createSubtleCryptoProvider()

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 })
  }

  const signature = req.headers.get('Stripe-Signature')
  if (!signature) return new Response('missing signature', { status: 400 })

  const rawBody = await req.text()
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? ''

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

  // Idempotência
  const { error: dupErr } = await supabase.from('subscription_events').insert({
    provider_event_id: event.id,
    event_type: event.type,
    payload: event,
  })

  if (dupErr?.code === '23505') {
    // já processado
    return new Response('ok (duplicate)', { status: 200 })
  }

  // Processa por tipo
  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        await handleCheckoutCompleted(session)
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
            typeof invoice.subscription === 'string' ? invoice.subscription : invoice.subscription.id
          await markSubscriptionStatus(subId, 'active')
        }
        break
      }
      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        if (invoice.subscription) {
          const subId =
            typeof invoice.subscription === 'string' ? invoice.subscription : invoice.subscription.id
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

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  if (!session.customer || !session.subscription) return

  // Procura user por email ou metadata.user_id
  let userId = session.metadata?.user_id ?? null

  if (!userId && session.customer_email) {
    const { data: user } = await supabase
      .from('users')
      .select('id')
      .eq('email', session.customer_email)
      .maybeSingle()
    userId = user?.id ?? null
  }

  if (!userId) {
    console.warn('checkout.completed without user_id mapping', session.id)
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
  const planLookup = sub.items.data[0]?.price?.lookup_key ?? 'mensal'
  const plan = planLookup.includes('anual')
    ? 'anual'
    : planLookup.includes('trial')
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

  await supabase
    .from('subscription_events')
    .update({ subscription_id: null, user_id: userId })
    .eq('provider_event_id', sub.latest_invoice as string)
}

async function markSubscriptionStatus(providerSubId: string, status: string) {
  await supabase
    .from('subscriptions')
    .update({ status, updated_at: new Date().toISOString() })
    .eq('provider_subscription_id', providerSubId)
}
