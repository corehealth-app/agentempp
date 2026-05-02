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
            {group === 'rate_limit'
              ? 'Rate Limits'
              : group === 'alerts'
                ? 'Alertas'
                : group === 'tts'
                  ? 'TTS (voz)'
                  : group}
          </h3>
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
      ) : (
        <Input value={String(value)} onChange={(e) => onChange(e.target.value)} disabled={disabled} />
      )}
    </div>
  )
}
