'use client'

import { Loader2, Save } from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { updateGlobalConfig } from '../global/actions'

interface ConfigItem {
  key: string
  value: unknown
  description: string | null
}

const GROUPS: Record<
  string,
  { title: string; description: string; keys: string[] }
> = {
  bmr: {
    title: 'BMR — Metabolismo Basal',
    description:
      'Mifflin-St Jeor (sem %BF) e Katch-McArdle (com %BF). Constantes científicas: alterar com cuidado.',
    keys: ['calc.bmr_mifflin', 'calc.bmr_katch'],
  },
  factors: {
    title: 'Fatores de atividade e proteína',
    description: 'Multiplicador BMR→TDEE e proteína g/kg corporal por nível de fome.',
    keys: ['calc.activity_factors', 'calc.protein_factors'],
  },
  formulas: {
    title: 'Fórmulas de meta calórica (doc MPP)',
    description:
      'Multiplicadores e déficits oficiais MPP por protocolo. Recomposição usa BMR × 1.2 fixo (não usa activity_factor — atividade NÃO entra no cálculo principal). Ganho aplica superávit leve sobre TDEE.',
    keys: [
      'calc.recomp_bmr_multiplier',
      'calc.ganho_massa_surplus_multiplier',
      'calc.deficit_by_hunger',
    ],
  },
  protocol: {
    title: 'Roteamento de protocolo',
    description: 'Limites IMC/BF e treino mínimo que decidem recomposição vs ganho_massa.',
    keys: [
      'calc.imc_limit_recomp',
      'calc.training_min',
      'calc.bf_limits',
      'calc.imc_goal_steps',
      'calc.bf_goal_rules',
    ],
  },
  gamification: {
    title: 'Gamificação',
    description: 'Bloco 7700, níveis XP, badges e regras de XP diário.',
    keys: ['calc.kcal_block', 'calc.levels', 'calc.badges', 'calc.xp_rules'],
  },
}

export function CalcConfigForm({ items }: { items: ConfigItem[] }) {
  const map = new Map(items.map((i) => [i.key, i]))
  return (
    <div className="space-y-4">
      {Object.entries(GROUPS).map(([groupKey, group]) => (
        <div key={groupKey} className="content-card p-5 space-y-3">
          <div>
            <h3 className="font-display text-lg tracking-tight">{group.title}</h3>
            <p className="text-xs text-muted-foreground mt-0.5">{group.description}</p>
          </div>
          <div className="space-y-3">
            {group.keys.map((k) => {
              const item = map.get(k)
              if (!item) return null
              return <CalcField key={k} item={item} />
            })}
          </div>
        </div>
      ))}
    </div>
  )
}

function CalcField({ item }: { item: ConfigItem }) {
  // Decide visualização baseada no shape do valor
  const isNumber = typeof item.value === 'number'
  const isObject =
    typeof item.value === 'object' && item.value !== null && !Array.isArray(item.value)
  const isArray = Array.isArray(item.value)

  return (
    <div className="glass-subtle p-3 space-y-2">
      <div className="flex items-baseline justify-between gap-2">
        <Label className="text-xs font-mono">{item.key.replace(/^calc\./, '')}</Label>
      </div>
      {item.description && (
        <p className="text-[11px] text-muted-foreground">{item.description}</p>
      )}
      {isNumber ? (
        <ScalarEditor item={item} />
      ) : isObject ? (
        <ObjectEditor item={item} />
      ) : isArray ? (
        <JsonEditor item={item} />
      ) : (
        <JsonEditor item={item} />
      )}
    </div>
  )
}

function ScalarEditor({ item }: { item: ConfigItem }) {
  const [value, setValue] = useState(String(item.value))
  const [pending, startTransition] = useTransition()

  function save() {
    const num = Number(value)
    if (!Number.isFinite(num)) {
      toast.error('Valor inválido — precisa ser número')
      return
    }
    startTransition(async () => {
      const r = await updateGlobalConfig(item.key, num)
      if (r.error) toast.error(r.error)
      else toast.success(`${item.key} = ${num}`)
    })
  }

  return (
    <div className="flex items-center gap-2">
      <Input
        type="number"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        className="h-8 max-w-[180px] text-sm font-mono"
        step="any"
      />
      <Button size="sm" onClick={save} disabled={pending} className="h-8">
        {pending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Save className="h-3 w-3" />}
      </Button>
    </div>
  )
}

function ObjectEditor({ item }: { item: ConfigItem }) {
  const initial = item.value as Record<string, unknown>
  const [values, setValues] = useState<Record<string, string>>(
    Object.fromEntries(
      Object.entries(initial).map(([k, v]) => [
        k,
        typeof v === 'object' ? JSON.stringify(v) : String(v),
      ]),
    ),
  )
  const [pending, startTransition] = useTransition()

  function save() {
    try {
      const parsed: Record<string, unknown> = {}
      for (const [k, v] of Object.entries(values)) {
        const orig = initial[k]
        if (typeof orig === 'number') {
          const n = Number(v)
          if (!Number.isFinite(n)) throw new Error(`${k}: precisa ser número`)
          parsed[k] = n
        } else if (typeof orig === 'object') {
          parsed[k] = JSON.parse(v)
        } else {
          parsed[k] = v
        }
      }
      startTransition(async () => {
        const r = await updateGlobalConfig(item.key, parsed)
        if (r.error) toast.error(r.error)
        else toast.success(`${item.key} salvo`)
      })
    } catch (e) {
      toast.error(e instanceof Error ? e.message : String(e))
    }
  }

  return (
    <div className="space-y-2">
      <div className="grid gap-2 md:grid-cols-2">
        {Object.entries(values).map(([k, v]) => {
          const orig = initial[k]
          const isNested = typeof orig === 'object'
          return (
            <div key={k} className="space-y-1">
              <Label className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
                {k}
              </Label>
              {isNested ? (
                <textarea
                  value={v}
                  onChange={(e) => setValues((p) => ({ ...p, [k]: e.target.value }))}
                  className="w-full h-16 text-xs font-mono p-2 rounded border border-border bg-background"
                />
              ) : (
                <Input
                  type="number"
                  value={v}
                  onChange={(e) => setValues((p) => ({ ...p, [k]: e.target.value }))}
                  className="h-8 text-sm font-mono"
                  step="any"
                />
              )}
            </div>
          )
        })}
      </div>
      <Button size="sm" onClick={save} disabled={pending} className="h-8">
        {pending ? (
          <Loader2 className="h-3 w-3 mr-1 animate-spin" />
        ) : (
          <Save className="h-3 w-3 mr-1" />
        )}
        Salvar
      </Button>
    </div>
  )
}

function JsonEditor({ item }: { item: ConfigItem }) {
  const [text, setText] = useState(JSON.stringify(item.value, null, 2))
  const [pending, startTransition] = useTransition()

  function save() {
    let parsed: unknown
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      toast.error(`JSON inválido: ${e instanceof Error ? e.message : String(e)}`)
      return
    }
    startTransition(async () => {
      const r = await updateGlobalConfig(item.key, parsed)
      if (r.error) toast.error(r.error)
      else toast.success(`${item.key} salvo`)
    })
  }

  return (
    <div className="space-y-2">
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        className="w-full h-32 text-xs font-mono p-2 rounded border border-border bg-background resize-y"
        spellCheck={false}
      />
      <Button size="sm" onClick={save} disabled={pending} className="h-8">
        {pending ? (
          <Loader2 className="h-3 w-3 mr-1 animate-spin" />
        ) : (
          <Save className="h-3 w-3 mr-1" />
        )}
        Salvar JSON
      </Button>
    </div>
  )
}
