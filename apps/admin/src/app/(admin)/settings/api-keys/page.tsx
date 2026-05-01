import { PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { CredentialEditor } from './credential-editor'
import { TestCredentialButton } from './test-button'
import { formatDateTime, maskKey } from '@/lib/utils'
import { AlertTriangle, Check, X } from 'lucide-react'

interface ServiceDefinition {
  service: string
  label: string
  description: string
  fields: Array<{
    key_name: string
    label: string
    placeholder?: string
    type?: 'text' | 'password' | 'select' | 'textarea'
    options?: string[]
    required?: boolean
    default_value?: string
  }>
  testable?: boolean
}

const SERVICE_CATALOG: ServiceDefinition[] = [
  {
    service: 'openrouter',
    label: 'OpenRouter',
    description: 'LLM principal, batch e vision via OpenRouter (Grok, DeepSeek, Gemini Flash).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 'sk-or-v1-…', type: 'password', required: true },
    ],
    testable: true,
  },
  {
    service: 'groq',
    label: 'Groq',
    description: 'STT (Whisper-large-v3-turbo) e classifier de intent (Llama 3.3).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 'gsk_…', type: 'password', required: true },
    ],
    testable: true,
  },
  {
    service: 'elevenlabs',
    label: 'ElevenLabs',
    description: 'TTS de mensagens-âncora (voz custom Dr. Roberto).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 'sk_…', type: 'password', required: true },
      { key_name: 'voice_id', label: 'Voice ID', placeholder: 'oArP4WehPe3qjqvCwHNo', type: 'text' },
    ],
    testable: true,
  },
  {
    service: 'cartesia',
    label: 'Cartesia',
    description: 'TTS operacional (mensagens de alta frequência).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 'sk_…', type: 'password', required: true },
      { key_name: 'voice_id', label: 'Voice ID', placeholder: 'pt-BR voice ID', type: 'text' },
    ],
    testable: true,
  },
  {
    service: 'helicone',
    label: 'Helicone',
    description: 'Proxy de observability LLM (logs custo + tokens + latência).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 'sk-helicone-…', type: 'password' },
    ],
  },
  {
    service: 'sentry',
    label: 'Sentry',
    description: 'Tracking de erros em Edge Functions e Next.js admin.',
    fields: [
      { key_name: 'dsn', label: 'DSN', placeholder: 'https://…@sentry.io/…', type: 'text' },
    ],
  },
  {
    service: 'inngest',
    label: 'Inngest',
    description: 'Workers durables: process-message, daily-closer, engagement-sender.',
    fields: [
      { key_name: 'event_key', label: 'Event Key', placeholder: 'xxx', type: 'password' },
      { key_name: 'signing_key', label: 'Signing Key', placeholder: 'signkey-prod-…', type: 'password' },
    ],
  },
  {
    service: 'meta_whatsapp',
    label: 'Meta WhatsApp Cloud',
    description:
      'Canal oficial WhatsApp. Quando preenchido, troque MESSAGING_PROVIDER=whatsapp_cloud.',
    fields: [
      { key_name: 'app_secret', label: 'App Secret', type: 'password' },
      { key_name: 'phone_number_id', label: 'Phone Number ID', type: 'text' },
      { key_name: 'waba_id', label: 'WABA ID', type: 'text' },
      { key_name: 'access_token', label: 'Permanent Access Token', type: 'password' },
      { key_name: 'verify_token', label: 'Webhook Verify Token', type: 'text' },
    ],
    testable: true,
  },
  {
    service: 'stripe',
    label: 'Stripe',
    description: 'Pagamentos recorrentes (Trial / Mensal / Anual).',
    fields: [
      { key_name: 'secret_key', label: 'Secret Key', placeholder: 'sk_test_… / sk_live_…', type: 'password' },
      { key_name: 'publishable_key', label: 'Publishable Key', placeholder: 'pk_test_…', type: 'text' },
      { key_name: 'webhook_secret', label: 'Webhook Secret', placeholder: 'whsec_…', type: 'password' },
    ],
  },
  {
    service: 'resend',
    label: 'Resend',
    description: 'Email transacional (recibos, magic links de admin).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 're_…', type: 'password' },
    ],
  },
]

export default async function ApiKeysPage() {
  const supabase = createServiceClient()
  const { data: rows } = await supabase.from('service_credentials').select('*')
  const lookup = new Map<string, NonNullable<typeof rows>[number]>()
  for (const row of rows ?? []) {
    lookup.set(`${row.service}:${row.key_name}`, row)
  }

  return (
    <div className="px-10 py-12 max-w-[1100px]">
      <PageHeader
        chapter="07"
        eyebrow="Sistema · credenciais"
        title="API Keys"
        description="Credenciais lidas em runtime pelos workers e Edge Functions. Mudanças têm efeito em até 60s (cache em memória)."
      />

      {/* Aviso de segurança */}
      <div className="mb-8 border-l-2 border-bronze bg-cream-50 px-5 py-4 rounded-sm">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-4 w-4 text-bronze shrink-0 mt-1" />
          <div className="text-sm text-ink-700 leading-relaxed">
            <strong className="text-ink-900">Aviso de segurança.</strong> Credenciais ficam em texto puro
            na tabela <code className="font-mono text-xs bg-cream-200 px-1 rounded">service_credentials</code>{' '}
            (RLS estrita: apenas role <code className="font-mono text-xs bg-cream-200 px-1 rounded">admin</code> lê).
            Para produção, considere migrar para Supabase Vault (requer plano Pro). As keys também
            continuam disponíveis via <code className="font-mono text-xs bg-cream-200 px-1 rounded">.env.local</code> como
            fallback até serem cadastradas aqui.
          </div>
        </div>
      </div>

      {/* Catálogo */}
      <div className="space-y-3">
        {SERVICE_CATALOG.map((svc, idx) => {
          const allConfigured = svc.fields.every((f) => lookup.has(`${svc.service}:${f.key_name}`))
          const someConfigured = svc.fields.some((f) =>
            lookup.has(`${svc.service}:${f.key_name}`),
          )
          const status = allConfigured ? 'ok' : someConfigured ? 'partial' : 'empty'

          return (
            <article
              key={svc.service}
              className="border border-border bg-cream-50 rounded-sm overflow-hidden"
            >
              {/* Header da config */}
              <div className="border-b border-border px-6 py-5 flex items-start justify-between gap-4">
                <div className="flex items-start gap-4">
                  <span className="font-mono text-xs text-ink-400 tabular-nums mt-1">
                    {String(idx + 1).padStart(2, '0')}
                  </span>
                  <div>
                    <h2 className="font-display text-xl text-ink-900 tracking-tight mb-1">
                      {svc.label}
                    </h2>
                    <p className="text-sm text-ink-600 max-w-xl">{svc.description}</p>
                  </div>
                </div>
                <div className="flex flex-col items-end gap-2 shrink-0">
                  <span
                    className={`inline-flex items-center gap-1.5 text-[10px] uppercase tracking-widest font-mono px-2 py-1 rounded-sm ${
                      status === 'ok'
                        ? 'bg-moss-100 text-moss-700'
                        : status === 'partial'
                          ? 'bg-cream-300 text-ink-700'
                          : 'bg-cream-200 text-ink-500'
                    }`}
                  >
                    {status === 'ok' ? (
                      <Check className="h-3 w-3" />
                    ) : status === 'partial' ? (
                      <Circle className="h-3 w-3" />
                    ) : (
                      <X className="h-3 w-3" />
                    )}
                    {status === 'ok' ? 'configurado' : status === 'partial' ? 'parcial' : 'vazio'}
                  </span>
                  {svc.testable && <TestCredentialButton service={svc.service} />}
                </div>
              </div>

              {/* Campos */}
              <div className="px-6 py-5 space-y-5">
                {svc.fields.map((field) => {
                  const existing = lookup.get(`${svc.service}:${field.key_name}`)
                  return (
                    <div key={field.key_name}>
                      <div className="flex items-center justify-between mb-2">
                        <label className="section-eyebrow">{field.label}</label>
                        {existing && (
                          <span className="text-[10px] font-mono text-ink-500">
                            atual:{' '}
                            <code className="text-ink-700 bg-cream-200 px-1.5 py-0.5 rounded">
                              {maskKey(existing.value)}
                            </code>
                            {existing.last_tested_at && (
                              <>
                                {' · testado '}
                                {formatDateTime(existing.last_tested_at)}{' '}
                                {existing.last_test_result === 'ok' ? '✓' : '✗'}
                              </>
                            )}
                          </span>
                        )}
                      </div>
                      <CredentialEditor
                        service={svc.service}
                        keyName={field.key_name}
                        label={field.label}
                        placeholder={field.placeholder}
                        type={field.type ?? 'text'}
                        options={field.options}
                        hasValue={!!existing}
                      />
                    </div>
                  )
                })}
              </div>
            </article>
          )
        })}
      </div>
    </div>
  )
}

function Circle({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 12 12" fill="none">
      <circle cx="6" cy="6" r="4" stroke="currentColor" strokeWidth="2" />
    </svg>
  )
}
