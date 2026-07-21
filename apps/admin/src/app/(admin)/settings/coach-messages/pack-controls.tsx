'use client'

import {
  Archive,
  CalendarClock,
  CheckCircle2,
  CopyPlus,
  Play,
  RotateCcw,
  ShieldCheck,
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useState, useTransition } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import type { AdminRole } from '@/lib/admin-rbac'
import type {
  CoachCatalogValidationResult,
  CoachContentPackSummary,
} from '@/lib/coach-messages/admin-service'
import {
  activateCoachContentPackAction,
  archiveCoachContentPackAction,
  cloneCoachContentPackAction,
  rollbackCoachContentPackAction,
  scheduleCoachContentPackAction,
  validateCoachContentPackAction,
} from './actions'
import { packControlAvailability, summarizeValidationIssues } from './catalog-presenter'

type ActionResponse<T> = { ok: true; data: T } | { ok: false; error: string }

const STATUS_LABELS: Record<CoachContentPackSummary['status'], string> = {
  draft: 'Rascunho',
  scheduled: 'Agendado',
  active: 'Ativo',
  archived: 'Arquivado',
}

export function PackControls({ pack, role }: { pack: CoachContentPackSummary; role: AdminRole }) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [pendingAction, setPendingAction] = useState<string | null>(null)
  const [feedback, setFeedback] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [validation, setValidation] = useState<CoachCatalogValidationResult | null>(null)
  const [cloneOpen, setCloneOpen] = useState(false)
  const [cloneLabel, setCloneLabel] = useState('')
  const [cloneSlug, setCloneSlug] = useState('')
  const [effectiveAt, setEffectiveAt] = useState('')
  const availability = packControlAvailability(pack.status, role)

  function execute<T>(
    actionName: string,
    request: () => Promise<ActionResponse<T>>,
    onSuccess: (data: T) => void,
  ) {
    setPendingAction(actionName)
    setFeedback(null)
    setError(null)
    startTransition(async () => {
      try {
        const result = await request()
        if (!result.ok) {
          setError(result.error)
          return
        }
        onSuccess(result.data)
        router.refresh()
      } finally {
        setPendingAction(null)
      }
    })
  }

  function validatePack() {
    execute(
      'validate',
      () => validateCoachContentPackAction({ packId: pack.id }),
      (result) => {
        const catalogValidation = result as CoachCatalogValidationResult
        setValidation(catalogValidation)
        setFeedback(
          catalogValidation.valid ? 'Catálogo validado' : 'Validação encontrou pendências',
        )
      },
    )
  }

  function schedulePack() {
    if (!effectiveAt) {
      setError('Informe a data e hora de ativação')
      return
    }
    const parsed = new Date(effectiveAt)
    if (Number.isNaN(parsed.getTime())) {
      setError('Data de ativação inválida')
      return
    }
    execute(
      'schedule',
      () =>
        scheduleCoachContentPackAction({
          packId: pack.id,
          effectiveAt: parsed.toISOString(),
        }),
      () => setFeedback('Ativação agendada'),
    )
  }

  function runLifecycle(
    name: 'activate' | 'archive' | 'rollback',
    request: () => Promise<ActionResponse<unknown>>,
    message: string,
  ) {
    if (
      (name === 'archive' || name === 'rollback') &&
      !window.confirm(
        name === 'archive'
          ? `Arquivar o pack “${pack.label}”?`
          : `Restaurar o pack “${pack.label}” como ativo?`,
      )
    ) {
      return
    }
    execute(name, request, () => setFeedback(message))
  }

  const masterOnlyTitle =
    role === 'master_admin' ? undefined : 'Disponível apenas para master admin'

  return (
    <section className="content-card" aria-label="Ciclo de vida do pack">
      <div className="flex flex-col gap-3 border-b border-border bg-muted/20 px-4 py-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="truncate font-display text-base text-foreground">{pack.label}</h2>
            <Badge variant={pack.status === 'active' ? 'default' : 'outline'}>
              {STATUS_LABELS[pack.status]}
            </Badge>
          </div>
          <p className="mt-0.5 truncate font-mono text-[11px] text-muted-foreground">{pack.slug}</p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <Button
            size="sm"
            variant="outline"
            disabled={!availability.canClone || pending}
            onClick={() => setCloneOpen(true)}
            className="active:scale-[0.98]"
          >
            <CopyPlus />
            Clonar
          </Button>
          <Button
            size="sm"
            variant="outline"
            disabled={!availability.canValidate || pending}
            onClick={validatePack}
            className="active:scale-[0.98]"
          >
            <ShieldCheck />
            {pendingAction === 'validate' ? 'Validando' : 'Validar'}
          </Button>
          <Button
            size="sm"
            variant="outline"
            disabled={!availability.canActivate || pending}
            title={masterOnlyTitle}
            onClick={() =>
              runLifecycle(
                'activate',
                () => activateCoachContentPackAction({ packId: pack.id }),
                'Pack ativado',
              )
            }
            className="active:scale-[0.98]"
          >
            <Play />
            Ativar
          </Button>
          <Button
            size="sm"
            variant="ghost"
            disabled={!availability.canArchive || pending}
            title={masterOnlyTitle}
            onClick={() =>
              runLifecycle(
                'archive',
                () => archiveCoachContentPackAction({ packId: pack.id }),
                'Pack arquivado',
              )
            }
            className="active:scale-[0.98]"
          >
            <Archive />
            Arquivar
          </Button>
          <Button
            size="sm"
            variant="ghost"
            disabled={!availability.canRollback || pending}
            title={masterOnlyTitle}
            onClick={() =>
              runLifecycle(
                'rollback',
                () => rollbackCoachContentPackAction({ packId: pack.id }),
                'Pack restaurado',
              )
            }
            className="active:scale-[0.98]"
          >
            <RotateCcw />
            Restaurar
          </Button>
        </div>
      </div>

      {pack.status === 'draft' && (
        <div className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-end">
          <div className="w-full sm:max-w-xs">
            <Label htmlFor="coach-pack-effective-at" className="text-xs">
              Ativação programada
            </Label>
            <Input
              id="coach-pack-effective-at"
              type="datetime-local"
              value={effectiveAt}
              onChange={(event) => setEffectiveAt(event.target.value)}
              disabled={!availability.canSchedule || pending}
              className="mt-1 font-mono"
            />
          </div>
          <Button
            size="sm"
            disabled={!availability.canSchedule || pending || !effectiveAt}
            title={masterOnlyTitle}
            onClick={schedulePack}
            className="active:scale-[0.98]"
          >
            <CalendarClock />
            {pendingAction === 'schedule' ? 'Agendando' : 'Agendar'}
          </Button>
        </div>
      )}

      {(feedback || error || validation) && (
        <div className="border-t border-border px-4 py-3 text-sm" aria-live="polite">
          {feedback && !error && (
            <p className="flex items-center gap-2 text-emerald-700 dark:text-emerald-400">
              <CheckCircle2 className="h-4 w-4" />
              {feedback}
            </p>
          )}
          {error && <p className="text-destructive">{error}</p>}
          {validation && !validation.valid && <ValidationResult validation={validation} />}
        </div>
      )}

      <Dialog open={cloneOpen} onOpenChange={setCloneOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Clonar pack ativo</DialogTitle>
            <DialogDescription>
              O novo pack nasce como rascunho e mantém as versões atuais até receber revisões.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-3 py-2">
            <div>
              <Label htmlFor="coach-clone-label">Nome operacional</Label>
              <Input
                id="coach-clone-label"
                value={cloneLabel}
                onChange={(event) => setCloneLabel(event.target.value)}
                placeholder="Catálogo agosto 2026"
              />
            </div>
            <div>
              <Label htmlFor="coach-clone-slug">Slug</Label>
              <Input
                id="coach-clone-slug"
                value={cloneSlug}
                onChange={(event) => setCloneSlug(event.target.value.toLowerCase())}
                placeholder="bodyflow-2026-08"
                className="font-mono"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setCloneOpen(false)}>
              Cancelar
            </Button>
            <Button
              disabled={pending || !cloneLabel.trim() || !cloneSlug.trim()}
              onClick={() =>
                execute(
                  'clone',
                  () =>
                    cloneCoachContentPackAction({
                      label: cloneLabel.trim(),
                      slug: cloneSlug.trim(),
                    }),
                  () => {
                    setCloneOpen(false)
                    setFeedback('Rascunho criado')
                  },
                )
              }
            >
              <CopyPlus />
              {pendingAction === 'clone' ? 'Clonando' : 'Criar rascunho'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </section>
  )
}

function ValidationResult({ validation }: { validation: CoachCatalogValidationResult }) {
  const summary = summarizeValidationIssues(validation.issues)
  return (
    <div className="mt-3 border-l-2 border-amber-500 pl-3">
      <p className="font-medium text-foreground">{summary.total} pendência(s)</p>
      <div className="mt-1 flex flex-wrap gap-1.5">
        {summary.byCode.map((item) => (
          <Badge key={item.code} variant="outline" className="font-mono text-[10px]">
            {item.code}: {item.count}
          </Badge>
        ))}
      </div>
      <ul className="mt-2 space-y-1 text-xs text-muted-foreground">
        {summary.messages.slice(0, 5).map((message) => (
          <li key={message}>{message}</li>
        ))}
      </ul>
    </div>
  )
}
