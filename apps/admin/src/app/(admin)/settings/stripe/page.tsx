import { CheckCircle2, ExternalLink, XCircle } from 'lucide-react'
import { ContentCard, PageHeader } from '@/components/page-header'
import { STRIPE_CATALOG, getStripeStatus } from '@/lib/stripe'
import { SetupProductsButton } from './setup-button'

export const dynamic = 'force-dynamic'

export default async function StripeSettingsPage() {
  const status = await getStripeStatus()

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Stripe' }]}
        title="Stripe"
        description="Configuração de billing, produtos e webhook."
      />

      {/* === Status das credenciais === */}
      <ContentCard
        title="Credenciais"
        description="Lidas em runtime de service_credentials"
      >
        <ul className="space-y-2">
          <CredRow
            label="stripe.publishable_key"
            ok={status.hasPublishable}
            hint="usada no frontend para Stripe Elements"
          />
          <CredRow
            label="stripe.secret_key"
            ok={status.hasSecret}
            hint="usada pelo admin (server) e webhook"
          />
          <CredRow
            label="stripe.webhook_secret"
            ok={status.hasWebhookSecret}
            hint="usada pra validar assinatura HMAC dos eventos do Stripe"
          />
        </ul>
        {!status.hasWebhookSecret && (
          <div className="mt-4 p-3 rounded bg-amber-500/10 border border-amber-500/30 text-xs text-foreground/80">
            <strong className="font-medium">⚠️ webhook_secret faltando:</strong> No Stripe
            Dashboard, vá em <em>Developers → Webhooks → Add endpoint</em>, cole a URL{' '}
            <code className="font-mono bg-background/60 px-1.5 py-0.5 rounded">
              https://xuxehkhdvjivitduarvb.supabase.co/functions/v1/webhook-stripe
            </code>
            , selecione os eventos{' '}
            <code className="font-mono bg-background/60 px-1.5 py-0.5 rounded">
              checkout.session.completed
            </code>
            ,{' '}
            <code className="font-mono bg-background/60 px-1.5 py-0.5 rounded">
              customer.subscription.*
            </code>
            ,{' '}
            <code className="font-mono bg-background/60 px-1.5 py-0.5 rounded">
              invoice.payment_*
            </code>{' '}
            e copie o <code className="font-mono">whsec_*</code> em{' '}
            <a href="/settings/api-keys" className="underline">
              /settings/api-keys
            </a>{' '}
            como <code className="font-mono">stripe.webhook_secret</code>.
          </div>
        )}
      </ContentCard>

      {/* === Catálogo de produtos === */}
      <ContentCard
        title="Catálogo de produtos"
        description="Produtos+preços que serão criados no Stripe (idempotente por lookup_key)"
      >
        <div className="space-y-2">
          {STRIPE_CATALOG.map((item) => (
            <div
              key={item.lookup_key}
              className="glass-subtle p-3 flex items-center gap-4"
            >
              <div className="flex-1 min-w-0">
                <div className="font-medium text-sm">{item.name}</div>
                <div className="text-xs text-muted-foreground mt-0.5">{item.description}</div>
                <code className="text-[10px] font-mono text-muted-foreground/70 mt-1 inline-block">
                  lookup_key: {item.lookup_key}
                </code>
              </div>
              <div className="text-right shrink-0">
                <div className="font-display text-lg tracking-tight">
                  R$ {(item.price_brl_cents / 100).toFixed(2)}
                </div>
                <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
                  /{item.interval} · trial {item.trial_days}d
                </div>
              </div>
            </div>
          ))}
        </div>
        <div className="mt-4">
          <SetupProductsButton enabled={status.hasSecret} />
          <p className="text-xs text-muted-foreground mt-2">
            Idempotente: roda quantas vezes quiser. Se um preço com a mesma{' '}
            <code className="font-mono">lookup_key</code> já existe, é reaproveitado.
          </p>
        </div>
      </ContentCard>

      {/* === Links úteis === */}
      <ContentCard title="Atalhos" description="Stripe Dashboard">
        <div className="grid gap-2 md:grid-cols-2">
          <ExtLink href="https://dashboard.stripe.com/test/dashboard" label="Dashboard (test mode)" />
          <ExtLink
            href="https://dashboard.stripe.com/test/products"
            label="Produtos no Stripe"
          />
          <ExtLink
            href="https://dashboard.stripe.com/test/webhooks"
            label="Webhooks no Stripe"
          />
          <ExtLink href="https://dashboard.stripe.com/test/customers" label="Customers" />
        </div>
      </ContentCard>
    </div>
  )
}

function CredRow({ label, ok, hint }: { label: string; ok: boolean; hint: string }) {
  return (
    <li className="flex items-center gap-3 py-1.5">
      {ok ? (
        <CheckCircle2 className="h-4 w-4 text-moss-600 shrink-0" />
      ) : (
        <XCircle className="h-4 w-4 text-rose-500 shrink-0" />
      )}
      <code className="font-mono text-sm text-foreground">{label}</code>
      <span className="text-xs text-muted-foreground ml-auto">{hint}</span>
    </li>
  )
}

function ExtLink({ href, label }: { href: string; label: string }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="glass-subtle p-3 flex items-center justify-between gap-2 hover:bg-muted/40 transition-colors"
    >
      <span className="text-sm">{label}</span>
      <ExternalLink className="h-3.5 w-3.5 text-muted-foreground" />
    </a>
  )
}
