import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createServiceClient } from '@/lib/supabase/server'
import { CredentialEditor } from './credential-editor'
import { TestCredentialButton } from './test-button'
import { formatDateTime, maskKey } from '@/lib/utils'
import { AlertTriangle } from 'lucide-react'

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
  const lookup = new Map<string, typeof rows extends (infer T)[] | null ? T : never>()
  for (const row of rows ?? []) {
    lookup.set(`${row.service}:${row.key_name}`, row)
  }

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-3xl font-bold">API Keys</h1>
        <p className="text-muted-foreground">
          Credenciais lidas em runtime pelos workers e Edge Functions. Mudanças têm efeito em
          até 60s (cache em memória).
        </p>
      </div>

      <div className="rounded-lg border-2 border-yellow-500/30 bg-yellow-500/10 p-4 text-sm">
        <div className="flex items-start gap-2">
          <AlertTriangle className="h-5 w-5 text-yellow-600 shrink-0 mt-0.5" />
          <div>
            <strong>Aviso de segurança:</strong> credenciais ficam em texto puro na tabela{' '}
            <code>service_credentials</code> (RLS estrita: apenas admin lê). Para produção,
            considere migrar para Supabase Vault (requer plano Pro). As keys também continuam
            disponíveis via <code>.env.local</code> como fallback até serem cadastradas aqui.
          </div>
        </div>
      </div>

      <div className="grid gap-4">
        {SERVICE_CATALOG.map((svc) => (
          <Card key={svc.service}>
            <CardHeader className="flex flex-row items-start justify-between space-y-0">
              <div className="space-y-1">
                <CardTitle className="text-lg">{svc.label}</CardTitle>
                <CardDescription>{svc.description}</CardDescription>
              </div>
              <div className="flex flex-col gap-2 items-end">
                {svc.fields.every((f) => lookup.has(`${svc.service}:${f.key_name}`)) ? (
                  <Badge variant="default">Configurado</Badge>
                ) : svc.fields.some((f) => lookup.has(`${svc.service}:${f.key_name}`)) ? (
                  <Badge variant="secondary">Parcial</Badge>
                ) : (
                  <Badge variant="outline">Não configurado</Badge>
                )}
                {svc.testable && <TestCredentialButton service={svc.service} />}
              </div>
            </CardHeader>
            <CardContent className="space-y-3">
              {svc.fields.map((field) => {
                const existing = lookup.get(`${svc.service}:${field.key_name}`)
                return (
                  <div key={field.key_name} className="grid gap-1.5">
                    <div className="flex items-center justify-between">
                      <label className="text-sm font-medium">{field.label}</label>
                      {existing && (
                        <span className="text-xs text-muted-foreground">
                          atual: <code>{maskKey(existing.value)}</code>
                          {existing.last_tested_at && (
                            <>
                              {' '}
                              · testado em {formatDateTime(existing.last_tested_at)}
                              {existing.last_test_result === 'ok' ? ' ✅' : ' ❌'}
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
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
