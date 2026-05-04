'use client'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Pencil, Plus, Search, Trash2 } from 'lucide-react'
import { useRouter, useSearchParams } from 'next/navigation'
import { useState, useTransition } from 'react'
import { deleteFood } from './actions'
import { FoodEditor } from './editor'
import type { FoodRow } from './page'

export function FoodsTable({
  rows,
  categories,
  searchParams,
}: {
  rows: FoodRow[]
  categories: string[]
  searchParams: { q?: string; category?: string; country?: string; source?: string }
}) {
  const router = useRouter()
  const sp = useSearchParams()
  const [editing, setEditing] = useState<FoodRow | 'new' | null>(null)
  const [deleting, setDeleting] = useState<number | null>(null)
  const [, startTransition] = useTransition()

  const updateFilter = (key: string, value: string | undefined) => {
    const params = new URLSearchParams(sp.toString())
    if (value && value !== '__all__') params.set(key, value)
    else params.delete(key)
    router.push(`/settings/foods?${params.toString()}`)
  }

  const onDelete = (id: number, name: string) => {
    if (!confirm(`Excluir "${name}" do banco?`)) return
    setDeleting(id)
    startTransition(async () => {
      const res = await deleteFood(id)
      setDeleting(null)
      if (!res.ok) alert(`Falha: ${res.error}`)
    })
  }

  return (
    <div className="space-y-3">
      <div className="content-card p-3 flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[220px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Buscar por nome (ex: ovo, bacon)…"
            defaultValue={searchParams.q ?? ''}
            className="pl-9"
            onKeyDown={(e) => {
              if (e.key === 'Enter') updateFilter('q', e.currentTarget.value)
            }}
          />
        </div>

        <Select
          value={searchParams.category ?? '__all__'}
          onValueChange={(v) => updateFilter('category', v)}
        >
          <SelectTrigger className="w-[180px]">
            <SelectValue placeholder="Categoria" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="__all__">Todas categorias</SelectItem>
            {categories.map((c) => (
              <SelectItem key={c} value={c}>
                {c}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Select
          value={searchParams.source ?? '__all__'}
          onValueChange={(v) => updateFilter('source', v)}
        >
          <SelectTrigger className="w-[140px]">
            <SelectValue placeholder="Fonte" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="__all__">Todas</SelectItem>
            <SelectItem value="alias">Alias</SelectItem>
            <SelectItem value="TACO_4_seed_minimal">TACO</SelectItem>
          </SelectContent>
        </Select>

        <Button size="sm" onClick={() => setEditing('new')}>
          <Plus className="h-4 w-4 mr-1" />
          Adicionar
        </Button>
      </div>

      <div className="content-card overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-muted/40 text-xs uppercase tracking-wide text-muted-foreground">
            <tr>
              <th className="text-left px-3 py-2">Nome</th>
              <th className="text-left px-3 py-2">Categoria</th>
              <th className="text-right px-3 py-2">kcal</th>
              <th className="text-right px-3 py-2">Prot</th>
              <th className="text-right px-3 py-2">Carb</th>
              <th className="text-right px-3 py-2">Gord</th>
              <th className="text-right px-3 py-2">Fib</th>
              <th className="text-left px-3 py-2">País</th>
              <th className="text-left px-3 py-2">Fonte</th>
              <th className="text-right px-3 py-2 w-24">Ações</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border/40">
            {rows.length === 0 ? (
              <tr>
                <td colSpan={10} className="text-center py-12 text-muted-foreground">
                  Nenhum alimento encontrado
                </td>
              </tr>
            ) : (
              rows.map((r) => (
                <tr key={r.id} className="hover:bg-muted/30">
                  <td className="px-3 py-2 font-medium">{r.name_pt}</td>
                  <td className="px-3 py-2 text-muted-foreground">{r.category ?? '—'}</td>
                  <td className="px-3 py-2 text-right font-mono">{r.kcal_per_100g}</td>
                  <td className="px-3 py-2 text-right font-mono">{r.protein_g}</td>
                  <td className="px-3 py-2 text-right font-mono">{r.carbs_g}</td>
                  <td className="px-3 py-2 text-right font-mono">{r.fat_g}</td>
                  <td className="px-3 py-2 text-right font-mono">{r.fiber_g}</td>
                  <td className="px-3 py-2 text-xs">{r.country_code}</td>
                  <td className="px-3 py-2 text-xs text-muted-foreground">
                    {r.source === 'alias' ? (
                      <span className="text-bronze">alias</span>
                    ) : (
                      r.source ?? '—'
                    )}
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => setEditing(r)}
                      className="h-7 w-7 p-0"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={deleting === r.id}
                      onClick={() => onDelete(r.id, r.name_pt)}
                      className="h-7 w-7 p-0 text-destructive hover:text-destructive"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {editing && (
        <FoodEditor
          initial={editing === 'new' ? null : editing}
          categories={categories}
          onCloseAction={() => setEditing(null)}
        />
      )}
    </div>
  )
}
