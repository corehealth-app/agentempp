'use client'
import { Save } from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { updateGlobalConfig } from './actions'

interface ConfigItem {
  key: string
  value: unknown
  description: string | null
}

const GROUP_LABELS: Record<string, string> = {
  rate_limit: 'Rate Limits',
  alerts: 'Alertas (thresholds)',
  tts: 'TTS — Voz (ElevenLabs)',
  vision: 'Vision — Reconhecimento de imagens',
  engagement: 'Engajamento — Janelas e slots',
  humanizer: 'Humanizer — Delay de envio',
  buffer: 'Buffer — Debounce de mensagens',
  attention: 'Atenção — Detecção de pacientes silenciosos',
  numeric_validator: 'Validador anti-alucinação numérica',
  persona: 'Persona — Nomes/títulos por país',
  country_to_language: 'Mapping país → idioma',
}

const GROUP_DESCRIPTIONS: Record<string, string> = {
  engagement:
    'Engajamento proativo (3-5x/dia). bed_offset_min: minutos antes de bedtime que para. wake_offset_min: minutos depois de wake_time que começa. fallbacks pra paciente sem horário no perfil. slots: array de janelas com hint de meal_type.',
  attention:
    'Configura alertas pra paciente que ficou silencioso, travou em onboarding, ou teve pagamento falho. Aparece em /audit ou /attention.',
  humanizer:
    'Simula tempo de digitação humano antes de enviar resposta. chars_per_second + min/max delay define o ritmo.',
  numeric_validator:
    'Validador pós-resposta que detecta alucinação numérica. enabled (on/off) + threshold_pct (% de erro tolerado).',
  vision: 'Modelo de vision (default gemini-2.5-flash) e threshold de confiança pra meal logging.',
  tts: 'Configurações ElevenLabs pra text-to-speech (similarity, speed, stability, style + se rewriter está ativo).',
  rate_limit: 'Limites por usuário (msgs/min e custo/dia em USD).',
  alerts:
    'Thresholds que disparam alertas em /audit (custo 24h, latência p95, taxa de falha de tools).',
  persona: 'Nome e título do agente por país (BR/PT/ES/US). Ex: "Dr. Roberto Menescal" pra BR.',
}

export function GlobalConfigForm({ items }: { items: ConfigItem[] }) {
  const [values, setValues] = useState<Record<string, unknown>>(
    Object.fromEntries(items.map((i) => [i.key, i.value])),
  )
  const [pending, startTransition] = useTransition()

  function save(key: string) {
    startTransition(async () => {
      const r = await updateGlobalConfig(key, values[key])
      if (r.error) toast.error(r.error)
      else toast.success(`${key} atualizado`)
    })
  }

  // Agrupa por prefixo (rate_limit, alerts, tts)
  const groups: Record<string, ConfigItem[]> = {}
  for (const item of items) {
    const prefix = item.key.split('.')[0] ?? 'outros'
    groups[prefix] = groups[prefix] ?? []
    groups[prefix].push(item)
  }

  return (
    <div className="space-y-6">
      {Object.entries(groups).map(([group, list]) => (
        <div key={group} className="content-card p-5 space-y-3">
          <h3 className="font-display text-lg tracking-tight">
            {GROUP_LABELS[group] ?? group}
          </h3>
          {GROUP_DESCRIPTIONS[group] && (
            <p className="text-xs text-muted-foreground -mt-2">{GROUP_DESCRIPTIONS[group]}</p>
          )}
          <div className="grid gap-3 md:grid-cols-2">
            {list.map((item) => (
              <ConfigField
                key={item.key}
                item={item}
                value={values[item.key]}
                onChange={(v) => setValues((prev) => ({ ...prev, [item.key]: v }))}
                onSave={() => save(item.key)}
                disabled={pending}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

function ConfigField({
  item,
  value,
  onChange,
  onSave,
  disabled,
}: {
  item: ConfigItem
  value: unknown
  onChange: (v: unknown) => void
  onSave: () => void
  disabled: boolean
}) {
  const isBoolean = typeof item.value === 'boolean'
  const isNumber = typeof item.value === 'number'
  const isComplex =
    typeof item.value === 'object' && item.value !== null

  return (
    <div className="glass-subtle p-3 space-y-2">
      <div className="flex items-start justify-between gap-2">
        <Label className="text-xs font-mono">{item.key}</Label>
        <Button size="sm" variant="outline" onClick={onSave} disabled={disabled}>
          <Save className="h-3 w-3 mr-1" />
          Salvar
        </Button>
      </div>
      {item.description && <p className="text-[11px] text-muted-foreground">{item.description}</p>}
      {isBoolean ? (
        <div className="flex items-center gap-2">
          <Switch
            checked={Boolean(value)}
            onCheckedChange={(v) => onChange(v)}
            disabled={disabled}
          />
          <span className="text-xs font-mono">{value ? 'ativo' : 'inativo'}</span>
        </div>
      ) : isNumber ? (
        <Input
          type="number"
          step="0.01"
          value={Number(value)}
          onChange={(e) => onChange(Number(e.target.value))}
          disabled={disabled}
        />
      ) : isComplex ? (
        <JsonField value={value} onChange={onChange} disabled={disabled} />
      ) : (
        <Input value={String(value)} onChange={(e) => onChange(e.target.value)} disabled={disabled} />
      )}
    </div>
  )
}

function JsonField({
  value,
  onChange,
  disabled,
}: {
  value: unknown
  onChange: (v: unknown) => void
  disabled: boolean
}) {
  const [text, setText] = useState(JSON.stringify(value, null, 2))
  const [error, setError] = useState<string | null>(null)

  return (
    <div className="space-y-1">
      <textarea
        value={text}
        onChange={(e) => {
          setText(e.target.value)
          try {
            const parsed = JSON.parse(e.target.value)
            onChange(parsed)
            setError(null)
          } catch (err) {
            setError(err instanceof Error ? err.message : 'JSON inválido')
          }
        }}
        disabled={disabled}
        spellCheck={false}
        className="w-full h-32 text-xs font-mono p-2 rounded border border-border bg-background resize-y"
      />
      {error && <p className="text-[11px] text-destructive font-mono">{error}</p>}
    </div>
  )
}
