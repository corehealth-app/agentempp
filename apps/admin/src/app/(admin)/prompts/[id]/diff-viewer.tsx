'use client'

import { ChevronDown, ChevronRight, GitCompare } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { createClient } from '@/lib/supabase/client'

interface Version {
  version_num: number
  status: string
  content?: string
  change_reason: string | null
  changed_at: string
}

/**
 * Diff viewer simples: line-by-line, sem dependência externa.
 * Algoritmo Myers simplificado — bom o suficiente pra prompts curtos.
 */
function diffLines(
  a: string,
  b: string,
): Array<{ kind: 'eq' | 'add' | 'del'; text: string }> {
  const aLines = a.split('\n')
  const bLines = b.split('\n')
  const aSet = new Set(aLines)
  const bSet = new Set(bLines)
  const result: Array<{ kind: 'eq' | 'add' | 'del'; text: string }> = []

  // Algoritmo simples: marca linhas presentes só em a (del), só em b (add)
  // ou em ambas (eq). Não preserva ordem perfeitamente em mudanças complexas
  // mas é OK pra ler diferenças semânticas.
  let aIdx = 0
  let bIdx = 0

  while (aIdx < aLines.length || bIdx < bLines.length) {
    const aLine = aLines[aIdx]
    const bLine = bLines[bIdx]
    if (aLine === bLine) {
      if (aLine !== undefined) result.push({ kind: 'eq', text: aLine })
      aIdx++
      bIdx++
      continue
    }
    if (aLine !== undefined && !bSet.has(aLine)) {
      result.push({ kind: 'del', text: aLine })
      aIdx++
      continue
    }
    if (bLine !== undefined && !aSet.has(bLine)) {
      result.push({ kind: 'add', text: bLine })
      bIdx++
      continue
    }
    // Ambas existem mas não nesta posição — avança a (heurística)
    if (aLine !== undefined) {
      result.push({ kind: 'del', text: aLine })
      aIdx++
    }
    if (bLine !== undefined) {
      result.push({ kind: 'add', text: bLine })
      bIdx++
    }
  }
  return result
}

export function DiffViewer({
  ruleId,
  versions,
  currentContent,
}: {
  ruleId: string
  versions: Version[]
  currentContent: string
}) {
  const [open, setOpen] = useState(false)
  const [versionA, setVersionA] = useState<number | null>(null)
  const [contentA, setContentA] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function loadVersion(num: number) {
    setLoading(true)
    setVersionA(num)
    const supabase = createClient()
    const { data } = await supabase
      .from('agent_rules_versions')
      .select('content')
      .eq('rule_id', ruleId)
      .eq('version_num', num)
      .maybeSingle()
    setContentA((data as { content: string } | null)?.content ?? null)
    setLoading(false)
  }

  if (versions.length < 1) return null

  return (
    <div className="content-card">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between p-4 hover:bg-muted/40 transition-colors"
      >
        <span className="flex items-center gap-2 text-sm font-medium">
          {open ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
          <GitCompare className="h-4 w-4" />
          Diff entre versões
        </span>
        <span className="text-[10px] font-mono text-muted-foreground">
          {versions.length} versões disponíveis
        </span>
      </button>

      {open && (
        <div className="border-t border-border p-4 space-y-3">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs text-muted-foreground">Comparar versão:</span>
            {versions.slice(0, 10).map((v) => (
              <Button
                key={v.version_num}
                size="sm"
                variant={versionA === v.version_num ? 'default' : 'outline'}
                onClick={() => loadVersion(v.version_num)}
                disabled={loading}
                className="h-7 text-xs"
              >
                v{v.version_num}
              </Button>
            ))}
            <span className="text-xs text-muted-foreground">→ atual</span>
          </div>

          {loading && (
            <div className="text-xs text-muted-foreground py-4">carregando v{versionA}...</div>
          )}

          {!loading && contentA !== null && (
            <DiffPanel oldContent={contentA} newContent={currentContent} oldLabel={`v${versionA}`} />
          )}

          {!loading && versionA && contentA === null && (
            <div className="text-xs text-rose-500 py-4">
              Versão v{versionA} sem snapshot de conteúdo (criada antes do versionamento).
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function DiffPanel({
  oldContent,
  newContent,
  oldLabel,
}: {
  oldContent: string
  newContent: string
  oldLabel: string
}) {
  const diff = diffLines(oldContent, newContent)
  const adds = diff.filter((d) => d.kind === 'add').length
  const dels = diff.filter((d) => d.kind === 'del').length

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-3 text-xs font-mono">
        <span className="text-muted-foreground">{oldLabel} → atual</span>
        <span className="text-moss-700">+{adds} linhas</span>
        <span className="text-rose-500">-{dels} linhas</span>
      </div>
      <div className="border border-border rounded font-mono text-[11px] bg-muted/20 max-h-[400px] overflow-y-auto">
        {diff.length === 0 ? (
          <div className="p-3 text-muted-foreground italic">Sem diferenças.</div>
        ) : (
          diff.map((line, i) => (
            <div
              key={i}
              className={`px-3 py-0.5 whitespace-pre-wrap break-words ${
                line.kind === 'add'
                  ? 'bg-moss-500/10 text-moss-700 border-l-2 border-moss-500'
                  : line.kind === 'del'
                    ? 'bg-rose-500/10 text-rose-700 border-l-2 border-rose-500 line-through'
                    : 'text-foreground/60'
              }`}
            >
              <span className="select-none mr-2 text-muted-foreground">
                {line.kind === 'add' ? '+' : line.kind === 'del' ? '-' : ' '}
              </span>
              {line.text || ' '}
            </div>
          ))
        )}
      </div>
    </div>
  )
}
