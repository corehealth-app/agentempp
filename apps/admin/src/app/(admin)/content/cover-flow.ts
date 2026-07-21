import type { SafeContentAsset } from '@/lib/content/admin-service'

type ActionResult<T> = { ok: true; data: T } | { ok: false; error: string }
type DiscardResult = { ok: true; data?: unknown } | { ok: false; error: string }

export type CoverFlowPhase = 'preparing' | 'uploading' | 'completing' | 'discarding'

export type PendingCoverResolution = {
  kind: 'complete' | 'discard'
  assetId: string
}

export type CoverFlowResult =
  | { status: 'completed'; asset: SafeContentAsset; pending: null }
  | { status: 'discarded'; pending: null }
  | { status: 'failed'; error: string; pending: PendingCoverResolution | null }

interface CoverResolutionDependencies {
  complete(assetId: string): Promise<ActionResult<SafeContentAsset>>
  discard(assetId: string): Promise<DiscardResult>
}

interface CoverUploadDependencies<FileValue> extends CoverResolutionDependencies {
  create(): Promise<
    ActionResult<{
      asset: SafeContentAsset
      upload: { signedUrl: string }
    }>
  >
  upload(signedUrl: string, file: FileValue): Promise<void>
  onPhase?(phase: CoverFlowPhase): void
}

export function coverAttemptBlocked(pending: PendingCoverResolution | null): boolean {
  return pending !== null
}

export function coverPublicationLocked(
  pending: PendingCoverResolution | null,
  busy: boolean,
): boolean {
  return busy || coverAttemptBlocked(pending)
}

export async function beginCoverUpload<FileValue>(
  file: FileValue,
  dependencies: CoverUploadDependencies<FileValue>,
): Promise<CoverFlowResult> {
  dependencies.onPhase?.('preparing')
  let created: Awaited<ReturnType<CoverUploadDependencies<FileValue>['create']>>
  try {
    created = await dependencies.create()
  } catch {
    return { status: 'failed', error: 'Nao foi possivel preparar o envio da capa.', pending: null }
  }
  if (!created.ok) return { status: 'failed', error: created.error, pending: null }

  const assetId = created.data.asset.assetId
  try {
    dependencies.onPhase?.('uploading')
    await dependencies.upload(created.data.upload.signedUrl, file)
  } catch {
    dependencies.onPhase?.('discarding')
    const discarded = await bestEffortDiscard(assetId, dependencies.discard)
    if (discarded) {
      return {
        status: 'failed',
        error: 'Nao foi possivel enviar a capa agora.',
        pending: null,
      }
    }
    return {
      status: 'failed',
      error: 'O envio falhou e a capa pendente ainda precisa ser descartada.',
      pending: { kind: 'discard', assetId },
    }
  }

  dependencies.onPhase?.('completing')
  try {
    const completed = await dependencies.complete(assetId)
    if (completed.ok) return { status: 'completed', asset: completed.data, pending: null }
    return {
      status: 'failed',
      error: completed.error,
      pending: { kind: 'complete', assetId },
    }
  } catch {
    return {
      status: 'failed',
      error: 'Nao foi possivel confirmar a capa enviada.',
      pending: { kind: 'complete', assetId },
    }
  }
}

export async function resolvePendingCover(
  pending: PendingCoverResolution,
  command: 'complete' | 'discard',
  dependencies: CoverResolutionDependencies,
): Promise<CoverFlowResult> {
  if (command === 'complete' && pending.kind === 'complete') {
    try {
      const completed = await dependencies.complete(pending.assetId)
      if (completed.ok) return { status: 'completed', asset: completed.data, pending: null }
      return { status: 'failed', error: completed.error, pending }
    } catch {
      return { status: 'failed', error: 'Nao foi possivel confirmar a capa enviada.', pending }
    }
  }

  const discarded = await bestEffortDiscard(pending.assetId, dependencies.discard)
  if (discarded) return { status: 'discarded', pending: null }
  return {
    status: 'failed',
    error: 'Nao foi possivel descartar a capa pendente.',
    pending: { kind: 'discard', assetId: pending.assetId },
  }
}

async function bestEffortDiscard(
  assetId: string,
  discard: CoverResolutionDependencies['discard'],
): Promise<boolean> {
  try {
    const result = await discard(assetId)
    return result.ok
  } catch {
    return false
  }
}
