'use client'

import { Check, ImagePlus, Loader2, RotateCcw, Trash2, Upload } from 'lucide-react'
import { useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import type { SafeContentAsset } from '@/lib/content/admin-service'
import {
  completeContentCoverAction,
  createContentCoverAction,
  deleteContentCoverAction,
} from '../actions'
import {
  beginCoverUpload,
  type CoverFlowResult,
  coverAttemptBlocked,
  type PendingCoverResolution,
  resolvePendingCover,
} from '../cover-flow'

type UploadPhase =
  | 'idle'
  | 'preparing'
  | 'uploading'
  | 'completing'
  | 'discarding'
  | 'success'
  | 'error'

const PHASE_LABELS: Record<UploadPhase, string> = {
  idle: 'Nenhum envio em andamento',
  preparing: 'Preparando envio...',
  uploading: 'Enviando arquivo...',
  completing: 'Confirmando capa...',
  discarding: 'Descartando capa pendente...',
  success: 'Capa enviada',
  error: 'Falha no envio',
}

export function CoverUploader({
  cover,
  disabled,
  publicationLocked,
  pendingResolution,
  onAssetChange,
  onPendingResolutionChange,
  onBusyChange,
}: {
  cover: SafeContentAsset | null
  disabled: boolean
  publicationLocked: boolean
  pendingResolution: PendingCoverResolution | null
  onAssetChange: (assetId: string | null) => void
  onPendingResolutionChange: (pending: PendingCoverResolution | null) => void
  onBusyChange: (busy: boolean) => void
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [phase, setPhase] = useState<UploadPhase>('idle')
  const [error, setError] = useState<string | null>(null)
  const busy =
    phase === 'preparing' ||
    phase === 'uploading' ||
    phase === 'completing' ||
    phase === 'discarding'
  const attemptBlocked = coverAttemptBlocked(pendingResolution)

  function updatePhase(nextPhase: UploadPhase) {
    setPhase(nextPhase)
    onBusyChange(
      nextPhase === 'preparing' ||
        nextPhase === 'uploading' ||
        nextPhase === 'completing' ||
        nextPhase === 'discarding',
    )
  }

  async function upload(file: File) {
    if (publicationLocked || busy || attemptBlocked) return
    setError(null)
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      updatePhase('error')
      setError('Use uma imagem JPEG, PNG ou WebP.')
      return
    }
    if (file.size < 1 || file.size > 10 * 1024 * 1024) {
      updatePhase('error')
      setError('A capa deve ter no maximo 10 MB.')
      return
    }

    const result = await beginCoverUpload(file, {
      async create() {
        const created = await createContentCoverAction({
          mimeType: file.type,
          sizeBytes: file.size,
        })
        if (!created.ok) return created
        return {
          ok: true,
          data: created.data as {
            asset: SafeContentAsset
            upload: { signedUrl: string }
          },
        }
      },
      async upload(signedUrl, selectedFile) {
        const response = await fetch(signedUrl, {
          method: 'PUT',
          headers: { 'Content-Type': selectedFile.type },
          body: selectedFile,
        })
        if (!response.ok) throw new Error('upload_failed')
      },
      async complete(assetId) {
        const completed = await completeContentCoverAction({ assetId })
        if (!completed.ok) return completed
        return { ok: true, data: completed.data as SafeContentAsset }
      },
      discard: discardAsset,
      onPhase: updatePhase,
    })
    if (inputRef.current) inputRef.current.value = ''
    applyResult(result)
  }

  async function retry(command: 'complete' | 'discard') {
    if (!pendingResolution) return
    setError(null)
    updatePhase(command === 'complete' ? 'completing' : 'discarding')
    const result = await resolvePendingCover(pendingResolution, command, {
      async complete(assetId) {
        const completed = await completeContentCoverAction({ assetId })
        if (!completed.ok) return completed
        return { ok: true, data: completed.data as SafeContentAsset }
      },
      discard: discardAsset,
    })
    applyResult(result)
  }

  function applyResult(result: CoverFlowResult) {
    onPendingResolutionChange(result.pending)
    if (result.status === 'completed') {
      onAssetChange(result.asset.assetId)
      updatePhase('success')
      setError(null)
      return
    }
    if (result.status === 'discarded') {
      updatePhase('idle')
      setError(null)
      return
    }
    updatePhase('error')
    setError(result.error)
  }

  return (
    <div className="space-y-3 rounded-md border border-border p-3">
      <div className="flex min-w-0 items-center gap-3">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground">
          <ImagePlus className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium">Capa</p>
          <p className="truncate text-xs text-muted-foreground">
            {cover
              ? `${cover.mimeType} · ${formatBytes(cover.sizeBytes)} · ${cover.status}`
              : 'Sem capa vinculada'}
          </p>
        </div>
        {!disabled && (
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={publicationLocked || busy || attemptBlocked}
            onClick={() => inputRef.current?.click()}
          >
            {busy ? <Loader2 className="animate-spin" /> : <Upload />}
            Enviar
          </Button>
        )}
      </div>
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="sr-only"
        disabled={disabled || publicationLocked || busy || attemptBlocked}
        onChange={(event) => {
          const file = event.target.files?.[0]
          if (file) void upload(file)
        }}
      />
      <div className="min-h-5" aria-live="polite">
        <p className={`text-xs ${error ? 'text-destructive' : 'text-muted-foreground'}`}>
          {error ?? PHASE_LABELS[phase]}
        </p>
      </div>
      {!disabled && pendingResolution && (
        <div className="flex flex-wrap gap-2 border-t border-border pt-3">
          {pendingResolution.kind === 'complete' && (
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={busy}
              onClick={() => void retry('complete')}
            >
              {phase === 'completing' ? <Loader2 className="animate-spin" /> : <Check />}
              Tentar confirmar
            </Button>
          )}
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={() => void retry('discard')}
          >
            {phase === 'discarding' ? (
              <Loader2 className="animate-spin" />
            ) : pendingResolution.kind === 'discard' ? (
              <RotateCcw />
            ) : (
              <Trash2 />
            )}
            {pendingResolution.kind === 'discard' ? 'Tentar descartar' : 'Descartar'}
          </Button>
        </div>
      )}
      {!disabled && cover && (
        <Button
          type="button"
          size="sm"
          variant="ghost"
          disabled={publicationLocked}
          onClick={() => onAssetChange(null)}
        >
          Remover do rascunho
        </Button>
      )}
    </div>
  )
}

async function discardAsset(assetId: string) {
  return deleteContentCoverAction({ assetId })
}

function formatBytes(value: number): string {
  if (value < 1024 * 1024) return `${Math.ceil(value / 1024)} KB`
  return `${(value / (1024 * 1024)).toFixed(1)} MB`
}
