'use client'

import { ImagePlus, Loader2, Upload } from 'lucide-react'
import { useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import type { SafeContentAsset } from '@/lib/content/admin-service'
import { completeContentCoverAction, createContentCoverAction } from '../actions'

type UploadPhase = 'idle' | 'preparing' | 'uploading' | 'completing' | 'success' | 'error'

const PHASE_LABELS: Record<UploadPhase, string> = {
  idle: 'Nenhum envio em andamento',
  preparing: 'Preparando envio...',
  uploading: 'Enviando arquivo...',
  completing: 'Confirmando capa...',
  success: 'Capa enviada',
  error: 'Falha no envio',
}

export function CoverUploader({
  cover,
  disabled,
  onAssetChange,
}: {
  cover: SafeContentAsset | null
  disabled: boolean
  onAssetChange: (assetId: string | null) => void
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [phase, setPhase] = useState<UploadPhase>('idle')
  const [error, setError] = useState<string | null>(null)
  const busy = phase === 'preparing' || phase === 'uploading' || phase === 'completing'

  async function upload(file: File) {
    setError(null)
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      setPhase('error')
      setError('Use uma imagem JPEG, PNG ou WebP.')
      return
    }
    if (file.size < 1 || file.size > 10 * 1024 * 1024) {
      setPhase('error')
      setError('A capa deve ter no maximo 10 MB.')
      return
    }

    setPhase('preparing')
    const createResult = await createContentCoverAction({
      mimeType: file.type,
      sizeBytes: file.size,
    })
    if (!createResult.ok) {
      setPhase('error')
      setError(createResult.error)
      return
    }

    let assetId = ''
    let uploadUrl = ''
    {
      const capability = createResult.data as {
        asset: SafeContentAsset
        upload: { signedUrl: string }
      }
      assetId = capability.asset.assetId
      uploadUrl = capability.upload.signedUrl
    }
    try {
      setPhase('uploading')
      const response = await fetch(uploadUrl, {
        method: 'PUT',
        headers: { 'Content-Type': file.type },
        body: file,
      })
      if (!response.ok) throw new Error('upload_failed')
    } catch {
      setPhase('error')
      setError('Nao foi possivel enviar a capa agora.')
      return
    } finally {
      uploadUrl = ''
    }

    setPhase('completing')
    const completeResult = await completeContentCoverAction({ assetId })
    if (!completeResult.ok) {
      setPhase('error')
      setError(completeResult.error)
      return
    }
    const asset = completeResult.data as SafeContentAsset
    onAssetChange(asset.assetId)
    setPhase('success')
    if (inputRef.current) inputRef.current.value = ''
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
            disabled={busy}
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
        disabled={disabled || busy}
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
      {!disabled && cover && (
        <Button type="button" size="sm" variant="ghost" onClick={() => onAssetChange(null)}>
          Remover do rascunho
        </Button>
      )}
    </div>
  )
}

function formatBytes(value: number): string {
  if (value < 1024 * 1024) return `${Math.ceil(value / 1024)} KB`
  return `${(value / (1024 * 1024)).toFixed(1)} MB`
}
