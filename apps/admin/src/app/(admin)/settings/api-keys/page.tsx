import { ContentCard, PageHeader } from '@/components/page-header'
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
  }>
  testable?: boolean
}

const SERVICE_CATALOG: ServiceDefinition[] = [
  {
    service: 'openrouter',
    label: 'OpenRouter',
    description: 'LLM principal, batch e vision (Grok, DeepSeek, Gemini Flash).',
    fields: [{ key_name: 'api_key', label: 'API Key', placeholder: 'sk-or-v1-…', type: 'password' }],
    testable: true,
  },
  {
    service: 'groq',
    label: 'Groq',
    description: 'STT (Whisper-large-v3-turbo) e classifier de intent.',
    fields: [{ key_name: 'api_key', label: 'API Key', placeholder: 'gsk_…', type: 'password' }],
    testable: true,
  },
  {
    service: 'elevenlabs',
    label: 'ElevenLabs',
    description: 'TTS de mensagens-âncora (voz custom Dr. Roberto).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 'sk_…', type: 'password' },
      { key_name: 'voice_id', label: 'Voice ID', placeholder: 'oArP4WehPe3qjqvCwHNo', type: 'text' },
    ],
    testable: true,
  },
  {
    service: 'cartesia',
    label: 'Cartesia',
    description: 'TTS operacional (mensagens de alta frequência).',
    fields: [
      { key_name: 'api_key', label: 'API Key', placeholder: 'sk_…', type: 'password' },
      { key_name: 'voice_id', label: 'Voice ID', placeholder: 'pt-BR voice ID', type: 'text' },
    ],
    testable: true,
  },
  {
    service: 'helicone',
    label: 'Helicone',
    description: 'Proxy de observability LLM (logs custo + tokens + latência).',
    fields: [{ key_name: 'api_key', label: 'API Key', type: 'password' }],
  },
  {
    service: 'sentry',
    label: 'Sentry',
    description: 'Tracking de erros em Edge Functions e Next.js admin.',
    fields: [{ key_name: 'dsn', label: 'DSN', placeholder: 'https://…@sentry.io/…', type: 'text' }],
  },
  {
    service: 'inngest',
    label: 'Inngest',
    description: 'Workers durables: process-message, daily-closer, engagement.',
    fields: [
      { key_name: 'event_key', label: 'Event Key', type: 'password' },
      { key_name: 'signing_key', label: 'Signing Key', type: 'password' },
    ],
  },
  {
    service: 'meta_whatsapp',
    label: 'Meta WhatsApp Cloud',
    description: 'Canal oficial WhatsApp.',
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
      { key_name: 'secret_key', label: 'Secret Key', type: 'password' },
      { key_name: 'publishable_key', label: 'Publishable Key', type: 'text' },
      { key_name: 'webhook_secret', label: 'Webhook Secret', type: 'password' },
    ],
  },
  {
    service: 'resend',
    label: 'Resend',
    description: 'Email transacional (recibos, magic links).',
    fields: [{ key_name: 'api_key', label: 'API Key', type: 'password' }],
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
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'API Keys' }]}
        title="API Keys"
        description="Credenciais lidas em runtime pelos workers e Edge Functions. Mudanças têm efeito em até 60s."
      />

      <div className="glass-card border-l-4 border-l-bronze p-4 flex items-start gap-3">
        <AlertTriangle className="h-4 w-4 text-bronze shrink-0 mt-0.5" />
        <div className="text-sm text-foreground/80 leading-relaxed">
          <strong className="text-foreground">Aviso de segurança.</strong> Credenciais ficam em
          texto puro na tabela{' '}
          <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">
            service_credentials
          </code>{' '}
          (RLS estrita: apenas role <code className="font-mono text-xs">admin</code> lê).
        </div>
      </div>

      <div className="space-y-4">
        {SERVICE_CATALOG.map((svc) => {
          const allConfigured = svc.fields.every((f) => lookup.has(`${svc.service}:${f.key_name}`))
          const someConfigured = svc.fields.some((f) =>
            lookup.has(`${svc.service}:${f.key_name}`),
          )
          const status = allConfigured ? 'ok' : someConfigured ? 'partial' : 'empty'

          return (
            <ContentCard
              key={svc.service}
              title={svc.label}
              description={svc.description}
              actions={
                <div className="flex items-center gap-2">
                  <span
                    className={`inline-flex items-center gap-1.5 text-[10px] uppercase tracking-widest font-mono px-2 py-1 rounded-full ${
                      status === 'ok'
                        ? 'bg-moss-100 text-moss-700'
                        : status === 'partial'
                          ? 'bg-cream-300 text-foreground/80'
                          : 'bg-muted text-muted-foreground'
                    }`}
                  >
                    {status === 'ok' ? (
                      <Check className="h-3 w-3" />
                    ) : status === 'partial' ? (
                      <CircleIcon />
                    ) : (
                      <X className="h-3 w-3" />
                    )}
                    {status === 'ok' ? 'configurado' : status === 'partial' ? 'parcial' : 'vazio'}
                  </span>
                  {svc.testable && <TestCredentialButton service={svc.service} />}
                </div>
              }
            >
              <div className="space-y-4">
                {svc.fields.map((field) => {
                  const existing = lookup.get(`${svc.service}:${field.key_name}`)
                  return (
                    <div key={field.key_name}>
                      <div className="flex items-center justify-between mb-2">
                        <label className="text-xs font-medium text-foreground">
                          {field.label}
                        </label>
                        {existing && (
                          <span className="text-[10px] font-mono text-muted-foreground">
                            atual:{' '}
                            <code className="text-foreground/80 bg-muted px-1.5 py-0.5 rounded">
                              {maskKey(existing.value)}
                            </code>
                            {existing.last_tested_at && (
                              <>
                                {' · '}
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
            </ContentCard>
          )
        })}
      </div>
    </div>
  )
}

function CircleIcon() {
  return (
    <svg className="h-3 w-3" viewBox="0 0 12 12" fill="none">
      <circle cx="6" cy="6" r="4" stroke="currentColor" strokeWidth="2" />
    </svg>
  )
}
