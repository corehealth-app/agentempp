import {
  extractPlanDocument,
  PLAN_DOCUMENT_MAX_PAGES,
  PLAN_DOCUMENT_MAX_TEXT_LENGTH,
  PLAN_DOCUMENT_MIN_TEXT_LENGTH,
  PLAN_DOCUMENT_PROMPT_VERSION,
  PLAN_DOCUMENT_STRUCTURE_MODEL,
  PLAN_DOCUMENT_TRANSCRIPTION_PROMPT,
  PlanDocumentNothingRecognizedError,
  type PlanDocumentStructurer,
  type PlanDraftDomain,
  type PlanDraftUncertainField,
} from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { OpenRouterLLM } from '@mpp/providers'
import { loadVisionConfig } from '../lib/runtime-config.js'

// A plan document becomes a DRAFT for the patient to review, never a plan.
// Nothing of the document is executed: its text is data for a model without
// tools, and what comes back is checked field by field (see
// @mpp/agent plan-document-extractor).

export type PlanDocumentFailure =
  | 'document_without_text'
  | 'document_too_long'
  | 'document_unreadable'
  | 'nothing_recognized'
  | 'extraction_failed'

export interface PlanDocumentDraftOutcome {
  userId: string
  draftId: string
  status: 'needs_completion' | 'ready_for_review' | 'failed'
  payload: Record<string, unknown> | null
  extractionPayload: Record<string, unknown> | null
  uncertainFields: PlanDraftUncertainField[]
  unrecognizedSegments: string[]
  originDetail: Record<string, unknown>
  failureCode: PlanDocumentFailure | null
}

export interface PlanDocumentDependencies {
  drafts: {
    /** Drafts of this patient still waiting for this document. */
    findWaiting(
      assetId: string,
      userId: string,
    ): Promise<Array<{ id: string; domain: PlanDraftDomain }>>
    resolve(outcome: PlanDocumentDraftOutcome): Promise<void>
  }
  readers: {
    /** Text layer of a PDF; an empty text means a scanned document. */
    pdfText(bytes: Uint8Array): Promise<{ text: string; pages: number }>
    /** What is written in a photo, transcribed without interpretation. */
    transcribeImage(input: { bytes: Uint8Array; mimeType: string; userId: string }): Promise<string>
    structurer: PlanDocumentStructurer
  }
}

export interface PlanDocumentSummary {
  kind: 'plan_document'
  method: 'pdf_text' | 'image_transcription'
  drafts: number
  /** Drafts that got content to review (complete or to be completed). */
  ready: number
  failed: number
}

/**
 * Every draft still waiting for this document ends as failed, with the
 * reason. Called whenever the document will not be read (refused file,
 * download failure, lost claim…), so no draft stays "extracting" forever.
 * Never throws: it runs on failure paths.
 */
export async function failWaitingPlanDrafts(
  deps: PlanDocumentDependencies,
  input: { assetId: string; userId: string },
  failureCode: PlanDocumentFailure,
): Promise<number> {
  try {
    const waiting = await deps.drafts.findWaiting(input.assetId, input.userId)
    let failed = 0
    for (const draft of waiting) {
      try {
        await deps.drafts.resolve({
          userId: input.userId,
          draftId: draft.id,
          status: 'failed',
          payload: null,
          extractionPayload: null,
          uncertainFields: [],
          unrecognizedSegments: [],
          originDetail: { method: 'not_read', prompt_version: PLAN_DOCUMENT_PROMPT_VERSION },
          failureCode,
        })
        failed += 1
      } catch {
        // The next delivery of the same work tries again.
      }
    }
    return failed
  } catch {
    return 0
  }
}

async function readDocument(
  deps: PlanDocumentDependencies,
  input: { mimeType: string; bytes: Uint8Array; userId: string },
): Promise<{ text: string } | { failure: PlanDocumentFailure }> {
  let text: string
  try {
    if (input.mimeType === 'application/pdf') {
      const pdf = await deps.readers.pdfText(input.bytes)
      if (pdf.pages > PLAN_DOCUMENT_MAX_PAGES) return { failure: 'document_too_long' }
      text = pdf.text
    } else {
      text = await deps.readers.transcribeImage(input)
    }
  } catch {
    return { failure: 'document_unreadable' }
  }
  const clean = text.replace(/\u0000/g, '').trim()
  if (clean.length < PLAN_DOCUMENT_MIN_TEXT_LENGTH) {
    // A scanned PDF has no text layer; the app asks for photos of the pages.
    return {
      failure: input.mimeType === 'application/pdf' ? 'document_without_text' : 'nothing_recognized',
    }
  }
  if (clean.length > PLAN_DOCUMENT_MAX_TEXT_LENGTH) return { failure: 'document_too_long' }
  return { text: clean }
}

// The structurer (Anthropic via OpenRouter) ignores json_object and may fence
// its answer (audit 2026-09-29). Only a whole object, fenced or bare, is read.
export class PlanDocumentAnswerError extends Error {
  override name = 'PlanDocumentAnswerError'
  constructor(readonly code: 'empty_content' | 'invalid_json' | 'truncated') {
    super(`plan document structuring returned ${code}`)
  }
}

export function parseStructuredAnswer(content: string | null, finishReason?: string): unknown {
  const trimmed = (content ?? '').trim()
  if (!trimmed) throw new PlanDocumentAnswerError('empty_content')
  const fenced = /^```[a-z]*[ \t]*\n?([\s\S]*?)\s*```$/i.exec(trimmed)
  try {
    return JSON.parse(fenced ? fenced[1]! : trimmed)
  } catch {
    throw new PlanDocumentAnswerError(finishReason === 'length' ? 'truncated' : 'invalid_json')
  }
}

const SAFE_ERROR_NAMES = new Set([
  'Error',
  'TypeError',
  'ZodError',
  'PlanDocumentAnswerError',
  'APIError',
  'APIConnectionError',
  'APIConnectionTimeoutError',
  'BadRequestError',
  'AuthenticationError',
  'PermissionDeniedError',
  'NotFoundError',
  'UnprocessableEntityError',
  'RateLimitError',
  'InternalServerError',
])

// Class, a fixed code and the provider status only: never the document text,
// the model answer or the provider message (it may name medications).
function logExtractionFailure(error: unknown): void {
  const className = error instanceof Error ? error.constructor.name : ''
  const name =
    error instanceof Error && SAFE_ERROR_NAMES.has(className)
      ? className
      : error instanceof Error && SAFE_ERROR_NAMES.has(error.name)
        ? error.name
        : 'UnknownError'
  const rawCode = (error as { code?: unknown } | null)?.code
  const code = rawCode === 'empty_content' || rawCode === 'invalid_json' || rawCode === 'truncated' ? rawCode : 'unknown'
  const rawStatus = (error as { status?: unknown } | null)?.status
  console.error('[plan-document] extraction_failed', {
    error_name: name,
    error_code: code,
    provider_status: typeof rawStatus === 'number' && Number.isInteger(rawStatus) ? rawStatus : null,
  })
}

export async function processPlanDocument(
  deps: PlanDocumentDependencies,
  input: { assetId: string; userId: string; mimeType: string; bytes: Uint8Array },
): Promise<PlanDocumentSummary> {
  const method = input.mimeType === 'application/pdf' ? 'pdf_text' : 'image_transcription'
  const summary: PlanDocumentSummary = {
    kind: 'plan_document',
    method,
    drafts: 0,
    ready: 0,
    failed: 0,
  }
  const waiting = await deps.drafts.findWaiting(input.assetId, input.userId)
  // Nothing waits for this document: it is not read (and nothing is paid).
  if (waiting.length === 0) return summary
  summary.drafts = waiting.length

  const document = await readDocument(deps, input)
  for (const draft of waiting) {
    const base = {
      userId: input.userId,
      draftId: draft.id,
      originDetail: { method, prompt_version: PLAN_DOCUMENT_PROMPT_VERSION } as Record<
        string,
        unknown
      >,
    }
    const fail = async (failureCode: PlanDocumentFailure) => {
      summary.failed += 1
      await deps.drafts.resolve({
        ...base,
        status: 'failed',
        payload: null,
        extractionPayload: null,
        uncertainFields: [],
        unrecognizedSegments: [],
        failureCode,
      })
    }
    if ('failure' in document) {
      await fail(document.failure)
      continue
    }
    try {
      const extraction = await extractPlanDocument(deps.readers.structurer, {
        domain: draft.domain,
        document: document.text,
        userId: input.userId,
      })
      await deps.drafts.resolve({
        ...base,
        status: extraction.complete ? 'ready_for_review' : 'needs_completion',
        payload: extraction.payload,
        extractionPayload: extraction.extraction_payload,
        uncertainFields: extraction.uncertain_fields,
        unrecognizedSegments: extraction.unrecognized_segments,
        originDetail: { ...base.originDetail, model: extraction.model },
        failureCode: null,
      })
      summary.ready += 1
    } catch (error) {
      if (!(error instanceof PlanDocumentNothingRecognizedError)) logExtractionFailure(error)
      await fail(
        error instanceof PlanDocumentNothingRecognizedError
          ? 'nothing_recognized'
          : 'extraction_failed',
      )
    }
  }
  return summary
}

// biome-ignore lint/suspicious/noExplicitAny: cliente sem tipos gerados para as tabelas novas
type Untyped = any

export function createDefaultPlanDocumentDependencies(
  supabase: ServiceClient,
): PlanDocumentDependencies {
  const llm = () => {
    const apiKey = process.env.OPENROUTER_API_KEY
    if (!apiKey) throw new Error('OPENROUTER_API_KEY ausente')
    // No observability proxy here: the request carries the whole document
    // (it may name medications) and must not be logged by a third party.
    return new OpenRouterLLM({ apiKey, appName: 'Performe AI Plan Import' })
  }
  return {
    drafts: {
      async findWaiting(assetId, userId) {
        const { data, error } = await (supabase as Untyped)
          .from('plan_drafts')
          .select('id, domain')
          .eq('user_id', userId)
          .eq('source_media_asset_id', assetId)
          .eq('status', 'extracting')
          .order('created_at', { ascending: true })
          .limit(5)
        if (error) throw new Error('plan draft lookup failed')
        return ((data ?? []) as Array<{ id: string; domain: string }>).flatMap((row) =>
          row.domain === 'training' || row.domain === 'nutrition'
            ? [{ id: row.id, domain: row.domain as PlanDraftDomain }]
            : [],
        )
      },
      async resolve(outcome) {
        const { error } = await (supabase as Untyped).rpc('resolve_plan_draft_work_atomic', {
          p_user_id: outcome.userId,
          p_draft_id: outcome.draftId,
          p_status: outcome.status,
          p_payload: outcome.payload,
          p_extraction_payload: outcome.extractionPayload,
          p_uncertain_fields: outcome.uncertainFields,
          p_unrecognized_segments: outcome.unrecognizedSegments,
          p_origin_detail: outcome.originDetail,
          p_failure_code: outcome.failureCode,
        })
        if (error) throw new Error('plan draft outcome was not stored')
      },
    },
    readers: {
      async pdfText(bytes) {
        const { extractText, getDocumentProxy } = await import('unpdf')
        const pdf = await getDocumentProxy(new Uint8Array(bytes))
        const { totalPages, text } = await extractText(pdf, { mergePages: true })
        return { text: typeof text === 'string' ? text : '', pages: totalPages }
      },
      async transcribeImage(input) {
        const config = await loadVisionConfig(supabase)
        const result = await llm().complete({
          model: config.model,
          systemPrompt: PLAN_DOCUMENT_TRANSCRIPTION_PROMPT,
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'image_url',
                  image_url: {
                    url: `data:${input.mimeType};base64,${Buffer.from(input.bytes).toString('base64')}`,
                  },
                },
              ],
            },
          ],
          temperature: 0,
          maxTokens: 4000,
          userId: input.userId,
        })
        return result.content ?? ''
      },
      structurer: {
        async structure(input) {
          const result = await llm().complete({
            model: PLAN_DOCUMENT_STRUCTURE_MODEL,
            systemPrompt: input.prompt,
            messages: [{ role: 'user', content: input.document }],
            temperature: 0,
            maxTokens: 6000,
            responseFormat: { type: 'json_object' },
            userId: input.userId,
          })
          const content = parseStructuredAnswer(result.content, result.finishReason)
          return { content, model: result.model ?? PLAN_DOCUMENT_STRUCTURE_MODEL }
        },
      },
    },
  }
}
