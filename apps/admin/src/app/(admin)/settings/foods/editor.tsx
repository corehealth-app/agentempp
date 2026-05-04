'use client'

import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useState, useTransition } from 'react'
import { upsertFood } from './actions'
import type { FoodRow } from './page'

export function FoodEditor({
  initial,
  categories,
  onCloseAction,
}: {
  initial: FoodRow | null
  categories: string[]
  onCloseAction: () => void
}) {
  const onClose = onCloseAction
  const [form, setForm] = useState({
    name_pt: initial?.name_pt ?? '',
    category: initial?.category ?? '',
    kcal_per_100g: initial?.kcal_per_100g ?? 0,
    protein_g: initial?.protein_g ?? 0,
    carbs_g: initial?.carbs_g ?? 0,
    fat_g: initial?.fat_g ?? 0,
    fiber_g: initial?.fiber_g ?? 0,
    country_code: initial?.country_code ?? 'BR',
    source: initial?.source ?? 'alias',
  })
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  const submit = () => {
    setError(null)
    if (!form.name_pt.trim()) {
      setError('Nome é obrigatório')
      return
    }
    startTransition(async () => {
      const res = await upsertFood({
        ...(initial?.id ? { id: initial.id } : {}),
        name_pt: form.name_pt.trim(),
        category: form.category.trim() || null,
        kcal_per_100g: Number(form.kcal_per_100g),
        protein_g: Number(form.protein_g),
        carbs_g: Number(form.carbs_g),
        fat_g: Number(form.fat_g),
        fiber_g: Number(form.fiber_g),
        country_code: form.country_code,
        source: form.source.trim() || null,
      })
      if (res.ok) onClose()
      else setError(res.error ?? 'Falha ao salvar')
    })
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{initial ? 'Editar alimento' : 'Novo alimento'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-3 pt-2">
          <div>
            <Label htmlFor="name">Nome (PT-BR popular)</Label>
            <Input
              id="name"
              value={form.name_pt}
              onChange={(e) => setForm({ ...form, name_pt: e.target.value })}
              placeholder='ex: "ovo frito", "bacon", "feijão tropeiro"'
            />
            <p className="text-[11px] text-muted-foreground mt-1">
              Use o nome que um brasileiro usaria conversando, não termo científico. Match no
              banco usa trigram em name_pt.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="category">Categoria</Label>
              <Input
                id="category"
                value={form.category}
                onChange={(e) => setForm({ ...form, category: e.target.value })}
                list="cat-list"
                placeholder="ex: carnes, vegetais, frutas"
              />
              <datalist id="cat-list">
                {categories.map((c) => (
                  <option key={c} value={c} />
                ))}
              </datalist>
            </div>
            <div>
              <Label htmlFor="country">País (ISO)</Label>
              <Input
                id="country"
                maxLength={2}
                value={form.country_code}
                onChange={(e) =>
                  setForm({ ...form, country_code: e.target.value.toUpperCase() })
                }
              />
            </div>
          </div>

          <div className="space-y-1">
            <Label className="text-xs uppercase tracking-wide text-muted-foreground">
              Macros por 100g
            </Label>
            <div className="grid grid-cols-5 gap-2">
              <Field
                label="kcal"
                value={form.kcal_per_100g}
                onChange={(v) => setForm({ ...form, kcal_per_100g: v })}
              />
              <Field
                label="prot (g)"
                value={form.protein_g}
                onChange={(v) => setForm({ ...form, protein_g: v })}
              />
              <Field
                label="carb (g)"
                value={form.carbs_g}
                onChange={(v) => setForm({ ...form, carbs_g: v })}
              />
              <Field
                label="gord (g)"
                value={form.fat_g}
                onChange={(v) => setForm({ ...form, fat_g: v })}
              />
              <Field
                label="fibra (g)"
                value={form.fiber_g}
                onChange={(v) => setForm({ ...form, fiber_g: v })}
              />
            </div>
          </div>

          <div>
            <Label htmlFor="source">Fonte</Label>
            <Input
              id="source"
              value={form.source}
              onChange={(e) => setForm({ ...form, source: e.target.value })}
              placeholder="alias | TACO_4_seed_minimal | manual"
            />
          </div>

          {error && (
            <div className="text-sm text-destructive bg-destructive/10 rounded p-2">{error}</div>
          )}
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="ghost" onClick={onClose}>
            Cancelar
          </Button>
          <Button onClick={submit} disabled={pending}>
            {pending ? 'Salvando…' : 'Salvar'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function Field({
  label,
  value,
  onChange,
}: {
  label: string
  value: number
  onChange: (v: number) => void
}) {
  return (
    <div>
      <label className="text-[10px] uppercase tracking-wide text-muted-foreground block">
        {label}
      </label>
      <Input
        type="number"
        step="0.1"
        min="0"
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="font-mono text-sm"
      />
    </div>
  )
}
