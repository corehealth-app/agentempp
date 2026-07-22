import { describe, expect, it, vi } from 'vitest'
import {
  beginCoverUpload,
  type ConfirmedDraftCover,
  confirmedCoverAssetForLocale,
  coverAttemptBlocked,
  coverPublicationLocked,
  type PendingCoverResolution,
  resolvePendingCover,
  transitionConfirmedDraftCover,
} from './cover-flow'

const ASSET_ID = '00000000-0000-0000-0000-000000000701'
const SIGNED_URL = 'https://storage.example.test/upload?token=secret-capability'
const FILE = { type: 'image/png', size: 128 }
const ASSET = {
  assetId: ASSET_ID,
  mimeType: 'image/png' as const,
  sizeBytes: 128,
  status: 'uploaded' as const,
}

function createSuccess() {
  return Promise.resolve({
    ok: true as const,
    data: {
      asset: { ...ASSET, status: 'pending_upload' as const },
      upload: { signedUrl: SIGNED_URL },
    },
  })
}

describe('cover flow', () => {
  it('best-effort deletes the pending asset after a failed or aborted PUT', async () => {
    const discard = vi.fn().mockResolvedValue({ ok: true })

    const result = await beginCoverUpload(FILE, {
      create: createSuccess,
      upload: vi.fn().mockRejectedValue(new DOMException('aborted', 'AbortError')),
      complete: vi.fn(),
      discard,
    })

    expect(discard).toHaveBeenCalledWith(ASSET_ID)
    expect(result).toEqual({
      status: 'failed',
      error: 'Nao foi possivel enviar a capa agora.',
      pending: null,
    })
    expect(JSON.stringify(result)).not.toContain(SIGNED_URL)
  })

  it('retains only a safe asset ID when upload cleanup fails and blocks another attempt', async () => {
    const result = await beginCoverUpload(FILE, {
      create: createSuccess,
      upload: vi.fn().mockRejectedValue(new Error('put failed')),
      complete: vi.fn(),
      discard: vi.fn().mockResolvedValue({ ok: false, error: 'storage_unavailable' }),
    })

    expect(result).toEqual({
      status: 'failed',
      error: 'O envio falhou e a capa pendente ainda precisa ser descartada.',
      pending: { kind: 'discard', assetId: ASSET_ID },
    })
    expect(coverAttemptBlocked(result.pending)).toBe(true)
    expect(Object.keys(result.pending ?? {})).toEqual(['kind', 'assetId'])
    expect(JSON.stringify(result)).not.toMatch(/signedUrl|secret-capability/)
  })

  it('retains the asset ID for completion retry after PUT succeeds', async () => {
    const discard = vi.fn()
    const upload = vi.fn().mockResolvedValue(undefined)

    const result = await beginCoverUpload(FILE, {
      create: createSuccess,
      upload,
      complete: vi.fn().mockResolvedValue({ ok: false, error: 'storage_unavailable' }),
      discard,
    })

    expect(upload).toHaveBeenCalledWith(SIGNED_URL, FILE)
    expect(discard).not.toHaveBeenCalled()
    expect(result).toEqual({
      status: 'failed',
      error: 'storage_unavailable',
      pending: { kind: 'complete', assetId: ASSET_ID },
    })
    expect(JSON.stringify(result)).not.toContain(SIGNED_URL)
  })

  it('retries completion without another upload and clears the pending state on success', async () => {
    const pending: PendingCoverResolution = { kind: 'complete', assetId: ASSET_ID }
    const complete = vi.fn().mockResolvedValue({ ok: true, data: ASSET })

    const result = await resolvePendingCover(pending, 'complete', {
      complete,
      discard: vi.fn(),
    })

    expect(complete).toHaveBeenCalledWith(ASSET_ID)
    expect(result).toEqual({ status: 'completed', asset: ASSET, pending: null })
  })

  it('offers discard for either recovery state and retains the safe ID when retry fails', async () => {
    const pending: PendingCoverResolution = { kind: 'complete', assetId: ASSET_ID }
    const discard = vi
      .fn()
      .mockResolvedValueOnce({ ok: false, error: 'storage_unavailable' })
      .mockResolvedValueOnce({ ok: true })

    const failed = await resolvePendingCover(pending, 'discard', {
      complete: vi.fn(),
      discard,
    })
    if (!failed.pending) throw new Error('Expected a retained pending asset')
    const discarded = await resolvePendingCover(failed.pending, 'discard', {
      complete: vi.fn(),
      discard,
    })

    expect(failed).toEqual({
      status: 'failed',
      error: 'Nao foi possivel descartar a capa pendente.',
      pending: { kind: 'discard', assetId: ASSET_ID },
    })
    expect(discarded).toEqual({ status: 'discarded', pending: null })
    expect(coverAttemptBlocked(discarded.pending)).toBe(false)
  })

  it('locks the publication across locales while an upload is busy or resolution is pending', () => {
    const confirmed: ConfirmedDraftCover = { assetId: ASSET_ID, locale: 'pt-BR' }

    expect(coverPublicationLocked(null, false, null)).toBe(false)
    expect(coverPublicationLocked(null, true, null)).toBe(true)
    expect(coverPublicationLocked({ kind: 'complete', assetId: ASSET_ID }, false, null)).toBe(true)
    expect(coverPublicationLocked({ kind: 'discard', assetId: ASSET_ID }, false, null)).toBe(true)
    expect(coverPublicationLocked(null, false, confirmed)).toBe(true)
  })

  it('exposes a confirmed cover only to its owning locale', () => {
    const confirmed: ConfirmedDraftCover = { assetId: ASSET_ID, locale: 'pt-BR' }

    expect(confirmedCoverAssetForLocale(confirmed, 'pt-BR')).toBe(ASSET_ID)
    expect(confirmedCoverAssetForLocale(confirmed, 'en-US')).toBeNull()
    expect(Object.keys(confirmed)).toEqual(['assetId', 'locale'])
    expect(JSON.stringify(confirmed)).not.toMatch(/signedUrl|secret-capability/)
  })

  it('clears a confirmed cover only after a successful save for its locale', () => {
    const confirmed: ConfirmedDraftCover = { assetId: ASSET_ID, locale: 'pt-BR' }

    expect(
      transitionConfirmedDraftCover(confirmed, {
        type: 'save',
        locale: 'pt-BR',
        succeeded: false,
      }),
    ).toEqual(confirmed)
    expect(
      transitionConfirmedDraftCover(confirmed, {
        type: 'save',
        locale: 'en-US',
        succeeded: true,
      }),
    ).toEqual(confirmed)
    expect(
      transitionConfirmedDraftCover(confirmed, {
        type: 'save',
        locale: 'pt-BR',
        succeeded: true,
      }),
    ).toBeNull()
  })

  it('clears a confirmed cover only after its discard succeeds', () => {
    const confirmed: ConfirmedDraftCover = { assetId: ASSET_ID, locale: 'pt-BR' }

    expect(
      transitionConfirmedDraftCover(confirmed, {
        type: 'discard',
        assetId: ASSET_ID,
        succeeded: false,
      }),
    ).toEqual(confirmed)
    expect(
      transitionConfirmedDraftCover(confirmed, {
        type: 'discard',
        assetId: '00000000-0000-0000-0000-000000000702',
        succeeded: true,
      }),
    ).toEqual(confirmed)
    expect(
      transitionConfirmedDraftCover(confirmed, {
        type: 'discard',
        assetId: ASSET_ID,
        succeeded: true,
      }),
    ).toBeNull()
  })
})
