/**
 * Database adapter of the body photos of the sign-up
 * (docs/mobile/api-v1.md, "Fotos do corpo no cadastro").
 *
 * The consent is read and accepted through the two generic functions of the
 * legal documents (`get_mobile_legal_document`, `accept_mobile_legal_document`:
 * 20260722191125_bodyflow_routine_items_api.sql), with the key of the body
 * photos. Nothing here touches the client until a method is called, so a
 * request answered with the switch off makes no query at all.
 *
 * The photos are rows of the media catalogue: body photos whose private
 * context is one of the three pose sentences. Creating one and completing its
 * upload go through the generic media service and its adapter; what is here
 * is what that service does not have — listing the photos of the sign-up of
 * an account (the ones not deleted, or every one ever created), counting them
 * for the limit, and removing several at once. A reading is projected to
 * its finite numeric body value only; free fields are never returned.
 *
 * The pose sentence is compared HERE, in code, not in the query: the queries
 * filter by account and kind only, with the plain filters the rest of the
 * app server already uses. A filter that silently matched nothing would make
 * "delete everything" delete nothing.
 *
 * A failure is logged with the request id, the name of the operation and a
 * database code from a closed list: never the account, a date or a text of
 * the database.
 */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'
import {
  BODY_PHOTO_CONSENT_KEY,
  SIGNUP_BODY_PHOTO_KIND,
  type SignupBodyPhotoCatalogue,
  type SignupBodyPhotoConsentRepository,
  type SignupBodyPhotoDependencies,
  type SignupBodyPhotoRow,
  signupBodyPhotoPoseOf,
  signupBodyPhotoReadingPercent,
  signupBodyPhotosUnavailable,
} from './signup-body-photo-service'
import { createSupabaseMediaDependencies } from './supabase-media'
import { repairCompletedSignupBodyPhotos } from './supabase-signup-body-photo-finalization'

interface DatabaseError {
  code?: string
  message?: string
}

interface QueryResult {
  data: unknown
  error: DatabaseError | null
}

type UntypedRpc = (
  functionName: string,
  params: Record<string, unknown>,
) => PromiseLike<QueryResult>

type SafeOperation =
  | 'get_consent'
  | 'get_acceptance'
  | 'accept_consent'
  | 'list_photos'
  | 'count_photos'
  | 'delete_photos'
  | 'get_onboarding'

interface UntypedQuery extends PromiseLike<QueryResult> {
  select(columns: string): UntypedQuery
  eq(column: string, value: unknown): UntypedQuery
  maybeSingle(): PromiseLike<QueryResult>
}

// `onboarding_completed_at` is not in the generated database types.
interface UntypedClient {
  from(table: string): UntypedQuery
}

/**
 * Far more body photos than an account holds: with photos of the sign-up
 * alone, limited to 9 in 24 hours, an account takes 112 days at the limit to
 * have more rows than this. A list is one page: what does not fit in it is
 * not looked at (see `list` for which rows come first).
 */
const PHOTOS_PAGE = 1000

/** Processing result is read internally and reduced before leaving this adapter. */
const PHOTO_COLUMNS =
  'id, bucket_id, object_path, status, failure_stage, context_text, created_at, uploaded_at, processing_result'

const dateTimeSchema = z.string().datetime({ offset: true })

const consentDocumentSchema = z
  .object({
    document_key: z.literal(BODY_PHOTO_CONSENT_KEY),
    version: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),
    locale: z.enum(['pt-BR', 'en-US']),
    body: z.string().refine((value) => {
      const trimmedLength = value.trim().length
      return trimmedLength >= 1 && trimmedLength <= 4000
    }),
    body_hash: z.string().regex(/^[0-9a-f]{64}$/),
    required_from: dateTimeSchema,
  })
  .strict()

const consentAcceptanceSchema = z
  .object({
    document_key: z.literal(BODY_PHOTO_CONSENT_KEY),
    accepted_version: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),
    accepted_at: dateTimeSchema,
  })
  .strict()

const acceptedAtRowSchema = z.object({ accepted_at: dateTimeSchema })

const photoRowSchema = z.object({
  id: z.string().uuid(),
  bucket_id: z.string().min(1),
  object_path: z.string().min(1),
  status: z.enum(['pending_upload', 'uploaded', 'processing', 'processed', 'failed', 'deleted']),
  failure_stage: z.enum(['upload', 'processing']).nullable(),
  context_text: z.string().nullable(),
  created_at: dateTimeSchema,
  uploaded_at: dateTimeSchema.nullable(),
  processing_result: z.unknown().optional(),
})

const createdRowSchema = z.object({ context_text: z.string().nullable() })

const onboardingRowSchema = z.object({
  onboarding_completed: z.boolean(),
  onboarding_completed_at: dateTimeSchema.nullable(),
})

const safeDatabaseCodes = new Set(['22023', '23505', '23514', '40001', 'P0002'])

function safeRequestId(requestId: string | undefined): string {
  return requestId && /^[A-Za-z0-9._:-]{8,128}$/.test(requestId) ? requestId : 'unknown'
}

function operationFailure(
  requestId: string,
  operation: SafeOperation,
  error?: DatabaseError | null,
): never {
  const rawCode = error?.code ?? 'invalid_response'
  console.error('[mobile-signup-body-photos] operation_failed', {
    request_id: requestId,
    operation,
    database_code: safeDatabaseCodes.has(rawCode) ? rawCode : 'unknown_error',
  })
  throw new MobileApiError(500, 'data_access_failed', 'Body photo data access failed')
}

function createConsentRepository(
  supabase: ServiceClient,
  requestId: string,
): SignupBodyPhotoConsentRepository {
  const rpc: UntypedRpc = (functionName, params) =>
    (supabase.rpc as unknown as UntypedRpc).call(supabase, functionName, params)

  return {
    async currentDocument(userId) {
      const { data, error } = await rpc('get_mobile_legal_document', {
        p_user_id: userId,
        p_document_key: BODY_PHOTO_CONSENT_KEY,
      })
      if (error) {
        // No text in force for the account's language (or an account the
        // function does not serve): the photos are not available to it.
        if (error.message === 'legal_document_not_available') return null
        operationFailure(requestId, 'get_consent', error)
      }
      const parsed = consentDocumentSchema.safeParse(data)
      if (!parsed.success) operationFailure(requestId, 'get_consent')
      return {
        documentKey: parsed.data.document_key,
        version: parsed.data.version,
        locale: parsed.data.locale,
        body: parsed.data.body,
        bodyHash: parsed.data.body_hash,
      }
    },

    async acceptedAt(userId, version) {
      const { data, error } = await supabase
        .from('user_legal_acceptances')
        .select('accepted_at')
        .eq('user_id', userId)
        .eq('document_key', BODY_PHOTO_CONSENT_KEY)
        .eq('version', version)
        .maybeSingle()
      if (error) operationFailure(requestId, 'get_acceptance', error)
      if (data === null) return null
      const parsed = acceptedAtRowSchema.safeParse(data)
      if (!parsed.success) operationFailure(requestId, 'get_acceptance')
      return parsed.data.accepted_at
    },

    async accept(input) {
      const { data, error } = await rpc('accept_mobile_legal_document', {
        p_user_id: input.userId,
        p_document_key: BODY_PHOTO_CONSENT_KEY,
        p_version: input.version,
        p_body_hash: input.bodyHash,
        p_idempotency_key: input.idempotencyKey,
      })
      if (error) {
        if (error.message === 'legal_document_not_available') throw signupBodyPhotosUnavailable()
        if (
          error.message === 'legal_document_version_mismatch' ||
          error.message === 'invalid_legal_acceptance'
        ) {
          throw new MobileApiError(
            409,
            'body_photo_consent_version_stale',
            'Body photo consent text changed; read it again',
          )
        }
        if (error.message === 'routine_mutation_idempotency_conflict') {
          throw new MobileApiError(
            409,
            'idempotency_key_conflict',
            'Idempotency-Key was already used for another request',
          )
        }
        operationFailure(requestId, 'accept_consent', error)
      }
      const parsed = consentAcceptanceSchema.safeParse(data)
      if (!parsed.success) operationFailure(requestId, 'accept_consent')
      return { version: parsed.data.accepted_version, acceptedAt: parsed.data.accepted_at }
    },
  }
}

function createCatalogue(supabase: ServiceClient, requestId: string): SignupBodyPhotoCatalogue {
  /**
   * The photos of the sign-up among the body photos of the account, one page.
   * `open`: the ones not deleted, newest first. `every`: the ones not deleted
   * FIRST (their deletion time is empty) and then the most recently deleted,
   * so a photo that is alive is never left out of the page by rows that were
   * already deleted.
   */
  async function list(userId: string, which: 'open' | 'every'): Promise<SignupBodyPhotoRow[]> {
    const ofTheAccount = supabase
      .from('media_assets')
      .select(PHOTO_COLUMNS)
      .eq('user_id', userId)
      .eq('kind', SIGNUP_BODY_PHOTO_KIND)
    const { data, error } = await (which === 'open'
      ? ofTheAccount.neq('status', 'deleted').order('created_at', { ascending: false })
      : ofTheAccount.order('deleted_at', { ascending: false, nullsFirst: true })
    ).limit(PHOTOS_PAGE)
    if (error || !Array.isArray(data)) operationFailure(requestId, 'list_photos', error)
    const photos: SignupBodyPhotoRow[] = []
    for (const row of data) {
      const parsed = photoRowSchema.safeParse(row)
      if (!parsed.success) operationFailure(requestId, 'list_photos')
      // A body photo whose context is not a pose sentence is not of the sign-up.
      const pose = signupBodyPhotoPoseOf(parsed.data.context_text)
      if (!pose) continue
      photos.push({
        id: parsed.data.id,
        bucketId: parsed.data.bucket_id,
        objectPath: parsed.data.object_path,
        pose,
        status: parsed.data.status,
        failureStage: parsed.data.failure_stage,
        createdAt: parsed.data.created_at,
        uploadedAt: parsed.data.uploaded_at,
        bodyFatPercent: signupBodyPhotoReadingPercent(parsed.data.processing_result),
      })
    }
    return photos
  }

  return {
    listOpen: (userId) => list(userId, 'open'),

    listEvery: (userId) => list(userId, 'every'),

    async countCreatedSince(userId, since) {
      const { data, error } = await supabase
        .from('media_assets')
        .select('context_text')
        .eq('user_id', userId)
        .eq('kind', SIGNUP_BODY_PHOTO_KIND)
        .gte('created_at', since)
        .limit(PHOTOS_PAGE)
      if (error || !Array.isArray(data)) operationFailure(requestId, 'count_photos', error)
      let created = 0
      for (const row of data) {
        const parsed = createdRowSchema.safeParse(row)
        if (!parsed.success) operationFailure(requestId, 'count_photos')
        if (signupBodyPhotoPoseOf(parsed.data.context_text)) created += 1
      }
      return created
    },

    async markDeleted(userId, photoIds, deletedAt) {
      const { data, error } = await supabase
        .from('media_assets')
        .update({
          status: 'deleted',
          deleted_at: deletedAt,
          failure_stage: null,
          failure_code: null,
          processing_result: null,
        })
        .eq('user_id', userId)
        .eq('kind', SIGNUP_BODY_PHOTO_KIND)
        .in('id', photoIds)
        .neq('status', 'deleted')
        .select('id')
      if (error || !Array.isArray(data)) operationFailure(requestId, 'delete_photos', error)
      return data.length
    },

    async removeObjects(bucketId, objectPaths) {
      const { error } = await supabase.storage.from(bucketId).remove(objectPaths)
      if (error) throw new MobileApiError(503, 'media_delete_failed', 'Media deletion failed')
    },

    async onboardingCompleted(userId) {
      const { data, error } = await (supabase as unknown as UntypedClient)
        .from('user_profiles')
        .select('onboarding_completed, onboarding_completed_at')
        .eq('user_id', userId)
        .maybeSingle()
      if (error) operationFailure(requestId, 'get_onboarding', error)
      // No profile row yet: nothing was completed.
      if (data === null) return false
      const parsed = onboardingRowSchema.safeParse(data)
      // Anything that is not a reading of the two columns is not "not completed".
      if (!parsed.success) operationFailure(requestId, 'get_onboarding')
      return parsed.data.onboarding_completed || parsed.data.onboarding_completed_at !== null
    },
  }
}

export function createSupabaseSignupBodyPhotoDependencies(
  supabase: ServiceClient,
  options: { enabled: boolean; requestId?: string },
): SignupBodyPhotoDependencies {
  const requestId = safeRequestId(options.requestId)
  return {
    enabled: options.enabled,
    consent: createConsentRepository(supabase, requestId),
    catalogue: createCatalogue(supabase, requestId),
    media: createSupabaseMediaDependencies(supabase),
    repairCompleted: (userId) => repairCompletedSignupBodyPhotos(supabase, userId),
  }
}
