import {
  assessPlanDraftPayload,
  confirmablePlanDraftPayload,
  mentionsMedication,
  type PlanDraftDomain,
  type PlanDraftOrigin,
  type PlanDraftUncertainField,
  planDraftValidUntil,
  sanitizeUnrecognizedSegments,
} from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { createHash } from 'node:crypto'
import { z } from 'zod'
import type {
  PlanDraftConfirmInput,
  PlanDraftListQuery,
  PlanDraftPatchInput,
  PlanImportInput,
} from './contracts'
import { MobileApiError } from './http'
import type { MediaAssetRecord } from './media-service'

// Plan drafts: what Flow proposed or a document said, waiting for the
// patient. This service never turns a draft into a plan by itself — that is
// confirmPlanDraft, called only by the confirmation route with the patient's
// token, the reviewed payload_version and an idempotency key.

export type PlanDraftStatus =
  | 'extracting'
  | 'generating'
  | 'needs_completion'
  | 'ready_for_review'
  | 'confirmed'
  | 'discarded'
  | 'expired'
  | 'failed'

const OPEN_STATUSES: PlanDraftStatus[] = [
  'extracting',
  'generating',
  'needs_completion',
  'ready_for_review',
]

export interface PlanDraftRecord {
  id: string
  user_id: string
  domain: PlanDraftDomain
  origin: PlanDraftOrigin
  status: PlanDraftStatus
  source_media_asset_id: string | null
  payload?: unknown
  payload_version: number
  uncertain_fields?: unknown
  unrecognized_segments?: unknown
  base_active_plan_id: string | null
  base_latest_prescription_id: string | null
  failure_code: string | null
  confirmed_plan_id: string | null
  created_at: string
  updated_at: string
  expires_at: string
  resolved_at: string | null
}

export interface PlanDraftOutcome {
  id: string
  status: PlanDraftStatus
  payload_version: number
  confirmed_plan_id: string | null
  already_confirmed?: boolean
  inserted?: boolean
}

export interface PlanDraftRepository {
  list(userId: string, statuses: PlanDraftStatus[]): Promise<PlanDraftRecord[]>
  findOwned(userId: string, draftId: string): Promise<PlanDraftRecord | null>
  update(input: {
    userId: string
    draftId: string
    expectedVersion: number
    payload: Record<string, unknown>
    uncertainFields: PlanDraftUncertainField[]
    complete: boolean
  }): Promise<PlanDraftOutcome>
  confirm(input: {
    userId: string
    draftId: string
    payloadVersion: number
    validUntil: string | null
    idempotencyKey: string
  }): Promise<PlanDraftOutcome>
  discard(userId: string, draftId: string): Promise<PlanDraftOutcome>
  /** The draft this document already produced, unless it failed or was dropped. */
  findImportOfMedia(userId: string, mediaAssetId: string): Promise<PlanDraftRecord | null>
  createImport(input: {
    userId: string
    domain: PlanDraftDomain
    origin: PlanDraftOrigin
    mediaAssetId: string
    requestKey: string
  }): Promise<PlanDraftOutcome>
}

export interface PlanDraftDependencies {
  repository: PlanDraftRepository
  media: { findOwned(userId: string, assetId: string): Promise<MediaAssetRecord | null> }
  events: {
    sendProcessingRequested(input: {
      assetId: string
      userId: string
      requestId: string
    }): Promise<void>
  }
}

function notFound(): MobileApiError {
  return new MobileApiError(404, 'plan_draft_not_found', 'Plan draft was not found')
}

function effectiveStatus(draft: PlanDraftRecord, now: Date): PlanDraftStatus {
  return OPEN_STATUSES.includes(draft.status) && new Date(draft.expires_at).getTime() <= now.getTime()
    ? 'expired'
    : draft.status
}

function uncertainFields(value: unknown): PlanDraftUncertainField[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((entry) => {
    if (typeof entry !== 'object' || entry === null) return []
    const { pointer, reason } = entry as Record<string, unknown>
    return typeof pointer === 'string' &&
      (reason === 'missing' ||
        reason === 'out_of_range' ||
        reason === 'invalid' ||
        reason === 'not_in_document')
      ? [{ pointer: pointer.slice(0, 300), reason }]
      : []
  })
}

function summaryDto(draft: PlanDraftRecord, now: Date) {
  return {
    id: draft.id,
    domain: draft.domain,
    origin: draft.origin,
    status: effectiveStatus(draft, now),
    payload_version: draft.payload_version,
    failure_code: draft.status === 'failed' ? draft.failure_code : null,
    created_at: draft.created_at,
    updated_at: draft.updated_at,
    expires_at: draft.expires_at,
    resolved_at: draft.resolved_at,
    confirmed_plan_id: draft.confirmed_plan_id,
  }
}

export function planDraftDto(draft: PlanDraftRecord, now = new Date()) {
  const segments = sanitizeUnrecognizedSegments(draft.unrecognized_segments)
  const status = effectiveStatus(draft, now)
  return {
    ...summaryDto(draft, now),
    source_media_asset_id: draft.source_media_asset_id,
    payload:
      typeof draft.payload === 'object' && draft.payload !== null && !Array.isArray(draft.payload)
        ? draft.payload
        : null,
    uncertain_fields: uncertainFields(draft.uncertain_fields),
    unrecognized_segments: segments,
    // Confirming a training draft replaces the plan in force; a nutrition
    // draft is added and earlier prescriptions stay.
    replaces_current_plan: draft.domain === 'training' && draft.base_active_plan_id !== null,
    can_confirm: status === 'ready_for_review',
    notices: [
      // The patient's confirmation is never presented as a clinical review.
      'not_professionally_reviewed',
      ...(segments.some(mentionsMedication) ? ['medications_not_imported'] : []),
    ],
  }
}

export async function listPlanDrafts(
  deps: PlanDraftDependencies,
  userId: string,
  query: PlanDraftListQuery,
  now = new Date(),
) {
  const statuses: PlanDraftStatus[] = query.status === 'open' ? OPEN_STATUSES : [query.status]
  const drafts = await deps.repository.list(userId, statuses)
  return {
    items: drafts
      .map((draft) => summaryDto(draft, now))
      .filter((draft) => draft.status !== 'expired'),
  }
}

async function requireOwned(
  deps: PlanDraftDependencies,
  userId: string,
  draftId: string,
): Promise<PlanDraftRecord> {
  const draft = await deps.repository.findOwned(userId, draftId)
  if (!draft) throw notFound()
  return draft
}

export async function getPlanDraft(
  deps: PlanDraftDependencies,
  userId: string,
  draftId: string,
  now = new Date(),
) {
  return planDraftDto(await requireOwned(deps, userId, draftId), now)
}

function requireReviewable(draft: PlanDraftRecord, now: Date): void {
  const status = effectiveStatus(draft, now)
  if (status === 'expired') {
    throw new MobileApiError(410, 'plan_draft_expired', 'Plan draft has expired')
  }
  if (status !== 'ready_for_review' && status !== 'needs_completion') {
    throw new MobileApiError(409, 'plan_draft_not_reviewable', 'Plan draft cannot be changed')
  }
}

export async function updatePlanDraft(
  deps: PlanDraftDependencies,
  userId: string,
  draftId: string,
  input: PlanDraftPatchInput,
  now = new Date(),
) {
  const draft = await requireOwned(deps, userId, draftId)
  requireReviewable(draft, now)
  if (draft.payload_version !== input.payload_version) {
    throw new MobileApiError(409, 'draft_changed', 'Plan draft changed since it was read')
  }
  const assessment = assessPlanDraftPayload(draft.domain, input.payload)
  await deps.repository.update({
    userId,
    draftId,
    expectedVersion: input.payload_version,
    payload: assessment.payload,
    uncertainFields: assessment.uncertain_fields,
    complete: assessment.complete,
  })
  return planDraftDto(await requireOwned(deps, userId, draftId), now)
}

export async function confirmPlanDraft(
  deps: PlanDraftDependencies,
  userId: string,
  draftId: string,
  input: PlanDraftConfirmInput,
  idempotencyKey: string,
  now = new Date(),
) {
  const draft = await requireOwned(deps, userId, draftId)
  if (draft.status !== 'confirmed') {
    const status = effectiveStatus(draft, now)
    if (status === 'expired') {
      throw new MobileApiError(410, 'plan_draft_expired', 'Plan draft has expired')
    }
    if (status === 'needs_completion') {
      throw new MobileApiError(422, 'plan_draft_incomplete', 'Plan draft has missing fields')
    }
    if (status !== 'ready_for_review') {
      throw new MobileApiError(409, 'plan_draft_not_reviewable', 'Plan draft cannot be confirmed')
    }
    if (draft.payload_version !== input.payload_version) {
      throw new MobileApiError(409, 'draft_changed', 'Plan draft changed since it was reviewed')
    }
    // The stored content is checked again by the strict rules right before
    // the confirmation, whatever its status says.
    if (!confirmablePlanDraftPayload(draft.domain, draft.payload)) {
      throw new MobileApiError(422, 'plan_draft_incomplete', 'Plan draft has missing fields')
    }
  }

  const outcome = await deps.repository.confirm({
    userId,
    draftId,
    payloadVersion: input.payload_version,
    validUntil: planDraftValidUntil(draft.domain, draft.origin, draft.payload, now),
    idempotencyKey,
  })
  return {
    ...planDraftDto(await requireOwned(deps, userId, draftId), now),
    already_confirmed: outcome.already_confirmed === true,
  }
}

export async function discardPlanDraft(
  deps: PlanDraftDependencies,
  userId: string,
  draftId: string,
  now = new Date(),
) {
  await requireOwned(deps, userId, draftId)
  await deps.repository.discard(userId, draftId)
  return planDraftDto(await requireOwned(deps, userId, draftId), now)
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex')
}

export async function createPlanImport(
  deps: PlanDraftDependencies,
  userId: string,
  input: PlanImportInput,
  idempotencyKey: string,
) {
  const asset = await deps.media.findOwned(userId, input.media_asset_id)
  if (!asset || asset.status === 'deleted') {
    throw new MobileApiError(404, 'media_asset_not_found', 'Media asset was not found')
  }
  if (asset.kind !== 'plan_document') {
    throw new MobileApiError(422, 'media_kind_not_supported', 'Media is not a plan document')
  }
  // A document is imported once: asking again answers with the draft it
  // already produced, whatever the request key.
  const existing = await deps.repository.findImportOfMedia(userId, asset.id)
  if (existing) {
    if (existing.domain !== input.domain) {
      throw new MobileApiError(
        409,
        'plan_document_already_imported',
        'This document was already imported as another kind of plan',
      )
    }
    return { draft_id: existing.id, status: existing.status }
  }
  // Read before: a new draft would wait for a reading that already happened.
  if (asset.status === 'processing' || asset.status === 'processed') {
    throw new MobileApiError(
      409,
      'plan_document_already_read',
      'This document was already read; send it again to import it',
    )
  }
  const retryable = asset.status === 'failed' && asset.failure_stage === 'processing'
  if (asset.status !== 'uploaded' && !retryable) {
    throw new MobileApiError(409, 'media_not_uploaded', 'Media asset is not uploaded yet')
  }

  const requestHash = sha256(`${userId}:${idempotencyKey}`)
  const outcome = await deps.repository.createImport({
    userId,
    domain: input.domain,
    origin: asset.mime_type === 'application/pdf' ? 'imported_pdf' : 'imported_photo',
    mediaAssetId: asset.id,
    requestKey: `plan-import:${requestHash}`,
  })
  // The document is read by the worker; the draft stays "extracting" until
  // its outcome arrives. A repeated request sends the same event id.
  await deps.events.sendProcessingRequested({
    assetId: asset.id,
    userId,
    requestId: sha256(`plan-import:${outcome.id}`),
  })
  return { draft_id: outcome.id, status: outcome.status }
}

// --- Supabase ---------------------------------------------------------------

const outcomeSchema = z.object({
  id: z.string().uuid(),
  status: z.enum([
    'extracting',
    'generating',
    'needs_completion',
    'ready_for_review',
    'confirmed',
    'discarded',
    'expired',
    'failed',
  ]),
  payload_version: z.number().int().min(1),
  confirmed_plan_id: z.string().uuid().nullable(),
  already_confirmed: z.boolean().optional(),
  inserted: z.boolean().optional(),
})

const recordSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  domain: z.enum(['training', 'nutrition']),
  origin: z.enum(['flow_generated', 'imported_photo', 'imported_pdf']),
  status: outcomeSchema.shape.status,
  source_media_asset_id: z.string().uuid().nullable(),
  payload: z.unknown(),
  payload_version: z.number().int().min(1),
  uncertain_fields: z.unknown(),
  unrecognized_segments: z.unknown(),
  base_active_plan_id: z.string().uuid().nullable(),
  base_latest_prescription_id: z.string().uuid().nullable(),
  failure_code: z.string().nullable(),
  confirmed_plan_id: z.string().uuid().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
  expires_at: z.string(),
  resolved_at: z.string().nullable(),
})

const RECORD_COLUMNS =
  'id, user_id, domain, origin, status, source_media_asset_id, payload, payload_version, uncertain_fields, unrecognized_segments, base_active_plan_id, base_latest_prescription_id, failure_code, confirmed_plan_id, created_at, updated_at, expires_at, resolved_at'

interface DatabaseError {
  code?: string
  message: string
}

/** Codes raised by the plan draft RPCs (supabase/migrations/…_plan_drafts.sql). */
export function planDraftDatabaseError(error: DatabaseError): MobileApiError {
  switch (error.code) {
    case 'PD404':
      return notFound()
    case 'PD409':
      return new MobileApiError(409, 'draft_changed', 'Plan draft changed since it was reviewed')
    case 'PD410':
      return new MobileApiError(410, 'plan_draft_expired', 'Plan draft has expired')
    case 'PD412':
      return new MobileApiError(
        409,
        'plan_changed_during_review',
        'The current plan changed while this draft was under review',
      )
    case 'PD422':
      return new MobileApiError(409, 'plan_draft_not_reviewable', 'Plan draft cannot be changed')
    case 'PD423':
      return new MobileApiError(
        409,
        'prescribed_plan_protected',
        'A plan prescribed by a professional cannot be replaced by a draft',
      )
    case 'PD429':
      return new MobileApiError(429, 'plan_draft_limit_reached', 'Too many open plan drafts')
    case '22023':
      return new MobileApiError(422, 'plan_draft_invalid', 'Plan draft request is invalid')
    case '23505':
      return new MobileApiError(409, 'idempotency_key_conflict', 'Request key was already used')
    default:
      console.error('[mobile-plan-drafts] database_failure', {
        error_code: error.code ?? 'unknown',
      })
      return new MobileApiError(500, 'plan_draft_storage_failed', 'Plan draft operation failed')
  }
}

type UntypedRpc = (
  functionName: string,
  params: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: DatabaseError | null }>

interface UntypedQuery extends PromiseLike<{ data: unknown; error: DatabaseError | null }> {
  eq(column: string, value: string): UntypedQuery
  in(column: string, values: string[]): UntypedQuery
  order(column: string, options: { ascending: boolean }): UntypedQuery
  limit(count: number): UntypedQuery
  maybeSingle(): PromiseLike<{ data: unknown; error: DatabaseError | null }>
}

export function createSupabasePlanDraftRepository(supabase: ServiceClient): PlanDraftRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as UntypedRpc
  const table = () =>
    (supabase.from('plan_drafts' as never) as unknown as {
      select(columns: string): UntypedQuery
    }).select(RECORD_COLUMNS)

  async function call(functionName: string, params: Record<string, unknown>) {
    const { data, error } = await rpc(functionName, params)
    if (error) throw planDraftDatabaseError(error)
    const parsed = outcomeSchema.safeParse(data)
    if (!parsed.success) throw planDraftDatabaseError({ code: 'parse_result', message: '' })
    return parsed.data
  }

  return {
    async list(userId, statuses) {
      const { data, error } = await table()
        .eq('user_id', userId)
        .in('status', statuses)
        .order('created_at', { ascending: false })
        .limit(20)
      if (error) throw planDraftDatabaseError(error)
      const parsed = z.array(recordSchema).safeParse(data ?? [])
      if (!parsed.success) throw planDraftDatabaseError({ code: 'parse_result', message: '' })
      return parsed.data
    },
    async findOwned(userId, draftId) {
      const { data, error } = await table().eq('id', draftId).eq('user_id', userId).maybeSingle()
      if (error) throw planDraftDatabaseError(error)
      if (!data) return null
      const parsed = recordSchema.safeParse(data)
      if (!parsed.success) throw planDraftDatabaseError({ code: 'parse_result', message: '' })
      return parsed.data
    },
    update(input) {
      return call('update_plan_draft_atomic', {
        p_user_id: input.userId,
        p_draft_id: input.draftId,
        p_expected_version: input.expectedVersion,
        p_payload: input.payload,
        p_uncertain_fields: input.uncertainFields,
        p_complete: input.complete,
      })
    },
    confirm(input) {
      return call('confirm_plan_draft_atomic', {
        p_user_id: input.userId,
        p_draft_id: input.draftId,
        p_payload_version: input.payloadVersion,
        p_valid_until: input.validUntil,
        p_idempotency_key: input.idempotencyKey,
      })
    },
    discard(userId, draftId) {
      return call('discard_plan_draft_atomic', { p_user_id: userId, p_draft_id: draftId })
    },
    async findImportOfMedia(userId, mediaAssetId) {
      const { data, error } = await table()
        .eq('user_id', userId)
        .eq('source_media_asset_id', mediaAssetId)
        .in('status', ['extracting', 'needs_completion', 'ready_for_review', 'confirmed'])
        .order('created_at', { ascending: false })
        .limit(1)
      if (error) throw planDraftDatabaseError(error)
      const parsed = z.array(recordSchema).safeParse(data ?? [])
      if (!parsed.success) throw planDraftDatabaseError({ code: 'parse_result', message: '' })
      return parsed.data[0] ?? null
    },
    createImport(input) {
      return call('create_plan_draft_atomic', {
        p_user_id: input.userId,
        p_domain: input.domain,
        p_origin: input.origin,
        p_status: 'extracting',
        p_payload: null,
        p_extraction_payload: null,
        p_uncertain_fields: null,
        p_unrecognized_segments: null,
        p_source_media_asset_id: input.mediaAssetId,
        p_source_message_id: null,
        p_origin_detail: { method: 'pending' },
        p_request_key: input.requestKey,
      })
    },
  }
}
