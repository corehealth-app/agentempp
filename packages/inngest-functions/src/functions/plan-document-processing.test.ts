import { describe, expect, it, vi } from 'vitest'
import {
  type MediaProcessingDependencies,
  mediaSignatureMatches,
  processMediaAsset,
} from './media-asset-processing.js'
import {
  failWaitingPlanDrafts,
  type PlanDocumentDependencies,
  type PlanDocumentDraftOutcome,
  processPlanDocument,
} from './plan-document-processing.js'

// Documento sintético de QA; nenhum dado real.
const DOCUMENT = `TREINO A - Inferiores (60 min)
Agachamento livre 4x8-12 descanso 90s
Leg press 3 x 10 - descanso 1 min
Tomar creatina 5 g após o treino.`

const ANSWER = {
  payload: {
    weekly_schedule: [
      {
        day: 'Treino A',
        focus: 'Inferiores',
        duration_min: 60,
        exercises: [
          { name: 'Agachamento livre', muscle_group: 'pernas', sets: 4, reps_range: '8-12', rest_seconds: 90 },
          { name: 'Leg press', muscle_group: 'pernas', sets: 3, reps_range: '10', rest_seconds: 60 },
        ],
      },
    ],
  },
  unrecognized_segments: ['Tomar creatina 5 g após o treino.'],
}

const USER = '00000000-0000-4000-8000-00000000000a'
const ASSET = '22222222-2222-4222-8222-222222222222'
const PDF = new TextEncoder().encode('%PDF-1.7 synthetic')

function planDependencies(
  overrides: {
    waiting?: Array<{ id: string; domain: 'training' | 'nutrition' }>
    pdf?: { text: string; pages: number } | Error
    image?: string | Error
    answer?: unknown | Error
  } = {},
) {
  const outcomes: PlanDocumentDraftOutcome[] = []
  const pdfText = vi.fn(async () => {
    const value = overrides.pdf ?? { text: DOCUMENT, pages: 1 }
    if (value instanceof Error) throw value
    return value
  })
  const transcribeImage = vi.fn(async () => {
    const value = overrides.image ?? DOCUMENT
    if (value instanceof Error) throw value
    return value
  })
  const structure = vi.fn(async () => {
    const value = 'answer' in overrides ? overrides.answer : ANSWER
    if (value instanceof Error) throw value
    return { content: value, model: 'test/model' }
  })
  const deps: PlanDocumentDependencies = {
    drafts: {
      findWaiting: vi.fn(
        async () => overrides.waiting ?? [{ id: 'draft-1', domain: 'training' as const }],
      ),
      resolve: vi.fn(async (outcome) => {
        outcomes.push(outcome)
      }),
    },
    readers: { pdfText, transcribeImage, structurer: { structure } },
  }
  return { deps, outcomes, pdfText, transcribeImage, structure }
}

const input = { assetId: ASSET, userId: USER, mimeType: 'application/pdf', bytes: PDF }

describe('processPlanDocument', () => {
  it('a PDF with text becomes content to review, bound to the patient and the draft', async () => {
    const { deps, outcomes, transcribeImage } = planDependencies()

    const summary = await processPlanDocument(deps, input)

    expect(deps.drafts.findWaiting).toHaveBeenCalledWith(ASSET, USER)
    expect(transcribeImage).not.toHaveBeenCalled()
    expect(summary).toEqual({
      kind: 'plan_document', method: 'pdf_text', drafts: 1, ready: 1, failed: 0,
    })
    expect(outcomes).toHaveLength(1)
    expect(outcomes[0]).toMatchObject({
      userId: USER,
      draftId: 'draft-1',
      status: 'ready_for_review',
      failureCode: null,
      uncertainFields: [],
      unrecognizedSegments: ['Tomar creatina 5 g após o treino.'],
      originDetail: { method: 'pdf_text', prompt_version: 'plan-document-v1', model: 'test/model' },
    })
    // Nothing of the document's text is kept besides what became a field or
    // an unrecognized segment.
    expect(JSON.stringify(outcomes[0]?.originDetail)).not.toContain('Agachamento')
    expect(JSON.stringify(summary)).not.toContain('Agachamento')
  })

  it('a photo is transcribed and then read the same way', async () => {
    const { deps, outcomes, pdfText, transcribeImage } = planDependencies()

    const summary = await processPlanDocument(deps, { ...input, mimeType: 'image/jpeg' })

    expect(pdfText).not.toHaveBeenCalled()
    expect(transcribeImage).toHaveBeenCalledWith(
      expect.objectContaining({ mimeType: 'image/jpeg', userId: USER }),
    )
    expect(summary.method).toBe('image_transcription')
    expect(outcomes[0]?.status).toBe('ready_for_review')
  })

  it('an incomplete reading is a draft that needs completion, never a failure', async () => {
    const { deps, outcomes } = planDependencies({
      answer: {
        payload: { weekly_schedule: [{ day: 'Treino A', exercises: [{ name: 'Leg press', sets: 3 }] }] },
      },
    })

    await processPlanDocument(deps, input)

    expect(outcomes[0]?.status).toBe('needs_completion')
    expect(outcomes[0]?.uncertainFields.length).toBeGreaterThan(0)
  })

  it('a scanned PDF, a long document and an unreadable file say why, without calling the model', async () => {
    for (const [overrides, mimeType, failure] of [
      [{ pdf: { text: '  \n ', pages: 3 } }, 'application/pdf', 'document_without_text'],
      [{ pdf: { text: DOCUMENT, pages: 21 } }, 'application/pdf', 'document_too_long'],
      [{ pdf: { text: 'a'.repeat(60_001), pages: 2 } }, 'application/pdf', 'document_too_long'],
      [{ pdf: new Error('broken pdf') }, 'application/pdf', 'document_unreadable'],
      [{ image: '' }, 'image/jpeg', 'nothing_recognized'],
      [{ image: new Error('provider down') }, 'image/jpeg', 'document_unreadable'],
    ] as const) {
      const { deps, outcomes, structure } = planDependencies(overrides)
      const summary = await processPlanDocument(deps, { ...input, mimeType })
      expect(structure).not.toHaveBeenCalled()
      expect(summary).toMatchObject({ drafts: 1, ready: 0, failed: 1 })
      expect(outcomes).toEqual([
        expect.objectContaining({
          status: 'failed',
          failureCode: failure,
          payload: null,
          extractionPayload: null,
        }),
      ])
    }
  })

  it('a provider failure or an empty reading fails the draft and never invents content', async () => {
    for (const [answer, failure] of [
      [new Error('provider down'), 'extraction_failed'],
      [{ payload: { weekly_schedule: [] } }, 'nothing_recognized'],
      ['not json', 'nothing_recognized'],
    ] as const) {
      const { deps, outcomes } = planDependencies({ answer })
      await processPlanDocument(deps, input)
      expect(outcomes).toEqual([
        expect.objectContaining({ status: 'failed', failureCode: failure, payload: null }),
      ])
    }
  })

  it('without a draft waiting the document is not read and nothing is paid', async () => {
    const { deps, outcomes, pdfText, structure } = planDependencies({ waiting: [] })

    const summary = await processPlanDocument(deps, input)

    expect(summary).toMatchObject({ drafts: 0, ready: 0, failed: 0 })
    expect(pdfText).not.toHaveBeenCalled()
    expect(structure).not.toHaveBeenCalled()
    expect(outcomes).toEqual([])
  })

  it('reads the document once for every draft that waits for it', async () => {
    const { deps, outcomes, pdfText, structure } = planDependencies({
      waiting: [
        { id: 'draft-1', domain: 'training' },
        { id: 'draft-2', domain: 'training' },
      ],
    })

    await processPlanDocument(deps, input)

    expect(pdfText).toHaveBeenCalledTimes(1)
    expect(structure).toHaveBeenCalledTimes(2)
    expect(outcomes.map((outcome) => outcome.draftId)).toEqual(['draft-1', 'draft-2'])
  })
})

describe('plan documents in the media worker', () => {
  function mediaDependencies(planDocuments?: PlanDocumentDependencies) {
    const deps: MediaProcessingDependencies = {
      repository: {
        claim: vi.fn(async () => ({
          id: ASSET,
          user_id: USER,
          kind: 'plan_document' as const,
          bucket_id: 'plan-documents',
          object_path: `${USER}/${ASSET}.pdf`,
          mime_type: 'application/pdf',
          context_text: null,
          status: 'processing' as const,
          processing_request_id: 'a'.repeat(64),
        })),
        markProcessed: vi.fn(async () => undefined),
        markFailed: vi.fn(async () => undefined),
      },
      storage: { download: vi.fn(async () => PDF) },
      providers: {
        analyzeImage: vi.fn(async () => ({})),
        transcribeAudio: vi.fn(async () => ({})),
      },
      planDocuments,
    }
    return deps
  }
  const request = { assetId: ASSET, userId: USER, requestId: 'a'.repeat(64) }

  it('stores on the asset only a summary, never the content of the document', async () => {
    const plan = planDependencies()
    const deps = mediaDependencies(plan.deps)

    expect(await processMediaAsset(deps, request)).toEqual({ status: 'processed' })

    expect(deps.repository.markProcessed).toHaveBeenCalledWith(ASSET, USER, request.requestId, {
      kind: 'plan_document', method: 'pdf_text', drafts: 1, ready: 1, failed: 0,
    })
    expect(deps.providers.analyzeImage).not.toHaveBeenCalled()
    expect(deps.providers.transcribeAudio).not.toHaveBeenCalled()
    expect(plan.outcomes).toHaveLength(1)
  })

  it('a file that is not the PDF it claims to be is refused before any reading', async () => {
    const plan = planDependencies()
    const deps = mediaDependencies(plan.deps)
    deps.storage.download = vi.fn(async () => new TextEncoder().encode('<html>not a pdf</html>'))

    expect(await processMediaAsset(deps, request)).toEqual({
      status: 'failed', reason: 'invalid_file_signature',
    })
    expect(plan.pdfText).not.toHaveBeenCalled()
    expect(plan.structure).not.toHaveBeenCalled()
    // The draft that waited for it is told, instead of waiting forever.
    expect(plan.outcomes).toEqual([
      expect.objectContaining({
        draftId: 'draft-1', status: 'failed', failureCode: 'document_unreadable', payload: null,
      }),
    ])
  })

  it('a download failure and a lost claim also end the drafts that waited', async () => {
    const download = planDependencies()
    const failing = mediaDependencies(download.deps)
    failing.storage.download = vi.fn(async () => {
      throw new Error('storage down')
    })
    await expect(processMediaAsset(failing, request)).rejects.toThrow('storage down')
    expect(failing.repository.markFailed).toHaveBeenCalledWith(
      ASSET, USER, request.requestId, 'storage_download_error',
    )
    expect(download.outcomes.map((outcome) => outcome.failureCode)).toEqual([
      'document_unreadable',
    ])

    const lost = planDependencies()
    const skipped = mediaDependencies(lost.deps)
    skipped.repository.claim = vi.fn(async () => null)
    expect(await processMediaAsset(skipped, request)).toEqual({ status: 'skipped' })
    expect(lost.deps.drafts.findWaiting).toHaveBeenCalledWith(ASSET, USER)
    expect(lost.outcomes.map((outcome) => outcome.status)).toEqual(['failed'])
  })

  it('when no outcome can be stored the asset does not stay processing', async () => {
    const plan = planDependencies()
    plan.deps.drafts.resolve = vi.fn(async () => {
      throw new Error('database down')
    })
    const deps = mediaDependencies(plan.deps)

    await expect(processMediaAsset(deps, request)).rejects.toThrow('database down')

    expect(deps.repository.markProcessed).not.toHaveBeenCalled()
    expect(deps.repository.markFailed).toHaveBeenCalledWith(
      ASSET, USER, request.requestId, 'plan_document_error',
    )
  })

  it('an outcome refused once becomes a failed draft, not a lost one', async () => {
    const plan = planDependencies()
    const stored: string[] = []
    let calls = 0
    plan.deps.drafts.resolve = vi.fn(async (outcome) => {
      calls += 1
      if (calls === 1) throw new Error('payload refused')
      stored.push(`${outcome.status}:${outcome.failureCode}`)
    })
    const deps = mediaDependencies(plan.deps)

    expect(await processMediaAsset(deps, request)).toEqual({ status: 'processed' })
    expect(stored).toEqual(['failed:extraction_failed'])
  })

  it('failing the drafts never throws, whatever the database does', async () => {
    const plan = planDependencies()
    plan.deps.drafts.findWaiting = vi.fn(async () => {
      throw new Error('database down')
    })
    await expect(
      failWaitingPlanDrafts(plan.deps, { assetId: ASSET, userId: USER }, 'document_unreadable'),
    ).resolves.toBe(0)

    const other = planDependencies()
    other.deps.drafts.resolve = vi.fn(async () => {
      throw new Error('database down')
    })
    await expect(
      failWaitingPlanDrafts(other.deps, { assetId: ASSET, userId: USER }, 'document_unreadable'),
    ).resolves.toBe(0)
  })

  it('without the reader the kind is refused instead of going to the meal analysis', async () => {
    const deps = mediaDependencies(undefined)

    expect(await processMediaAsset(deps, request)).toEqual({
      status: 'failed', reason: 'plan_document_unsupported',
    })
    expect(deps.providers.analyzeImage).not.toHaveBeenCalled()
  })

  it('recognizes the PDF signature', () => {
    expect(mediaSignatureMatches(PDF, 'application/pdf')).toBe(true)
    expect(mediaSignatureMatches(new Uint8Array([0xff, 0xd8, 0xff]), 'application/pdf')).toBe(false)
    expect(mediaSignatureMatches(PDF, 'image/jpeg')).toBe(false)
  })
})
