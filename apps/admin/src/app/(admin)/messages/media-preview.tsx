'use client'

import { Image as ImageIcon, Volume2, X } from 'lucide-react'
import { useState } from 'react'

/**
 * Preview compacto de mídia inline no balão.
 * Click → abre MediaViewerModal em fullscreen.
 *
 * Como o admin não tem acesso direto à URL do Meta (precisa baixar via
 * messaging.downloadMedia com access_token), fazemos download via uma
 * Edge Function proxy. Por enquanto, mostra ícone + ID e botão pra abrir
 * em nova aba via API endpoint.
 */
export function MediaPreview({
  userWpp,
  mediaId,
  kind,
  isOut,
}: {
  userWpp: string
  mediaId: string
  kind: 'image' | 'audio'
  isOut: boolean
}) {
  const [open, setOpen] = useState(false)
  const proxyUrl = `/api/media/${mediaId}`

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={`mt-2 flex items-center gap-2 px-3 py-2 rounded text-xs ${
          isOut ? 'bg-cream-100/10 hover:bg-cream-100/20' : 'bg-background/60 hover:bg-background'
        } transition-colors`}
      >
        {kind === 'image' ? (
          <ImageIcon className="h-3.5 w-3.5" />
        ) : (
          <Volume2 className="h-3.5 w-3.5" />
        )}
        <span className="font-mono">
          {kind === 'image' ? 'Foto' : 'Áudio'} ({mediaId.slice(0, 12)}…)
        </span>
        <span className={isOut ? 'opacity-60' : 'text-muted-foreground'}>↗</span>
      </button>

      {open && (
        <MediaViewerModal
          userWpp={userWpp}
          mediaId={mediaId}
          kind={kind}
          proxyUrl={proxyUrl}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  )
}

function MediaViewerModal({
  mediaId,
  kind,
  proxyUrl,
  onClose,
}: {
  userWpp: string
  mediaId: string
  kind: 'image' | 'audio'
  proxyUrl: string
  onClose: () => void
}) {
  return (
    <div
      className="fixed inset-0 z-[100] bg-background/90 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="relative max-w-4xl w-full glass-card overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-3 border-b border-border bg-muted/30">
          <div className="flex items-center gap-2">
            {kind === 'image' ? (
              <ImageIcon className="h-4 w-4" />
            ) : (
              <Volume2 className="h-4 w-4" />
            )}
            <span className="font-mono text-xs">{mediaId}</span>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="h-7 w-7 rounded hover:bg-muted flex items-center justify-center"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="p-6 flex items-center justify-center min-h-[300px]">
          {kind === 'image' ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={proxyUrl}
              alt="Foto enviada"
              className="max-h-[70vh] max-w-full rounded shadow-lg"
              onError={(e) => {
                ;(e.target as HTMLImageElement).style.display = 'none'
                ;(e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden')
              }}
            />
          ) : (
            <audio src={proxyUrl} controls className="w-full" />
          )}
          <div className="hidden text-sm text-muted-foreground text-center max-w-md">
            <p>Não foi possível baixar a mídia.</p>
            <p className="text-xs mt-2 font-mono">
              Pode ser: token Meta expirado, mediaId inválido, ou Edge Function indisponível.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
