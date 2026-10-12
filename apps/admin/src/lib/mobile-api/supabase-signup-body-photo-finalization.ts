import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { OnboardingCompletionInput } from './contracts'
import { MobileApiError } from './http'
import type { MobileRouteContext } from './route'
import {
  deferSignupBodyPhotoCandidate,
  type FinalizationDependencies,
  finalizeSignupBodyPhotos,
} from './signup-body-photo-finalization'
import {
  SIGNUP_BODY_PHOTO_KIND,
  signupBodyPhotoPoseOf,
  signupBodyPhotoReadingPercent,
} from './signup-body-photo-service'
import { projectRefFromUrl } from './signup-body-photo-switch'

// The only database authorized for this delivery. Independent of the photo switch.
export function signupBodyPhotoFinalizationTargetAllowed(): boolean {
  return projectRefFromUrl(process.env.NEXT_PUBLIC_SUPABASE_URL) === 'xitugspwfxkcluxvrdeg'
}

const photoColumns =
  'id, bucket_id, object_path, status, failure_stage, context_text, created_at, uploaded_at, processing_result'
const dateTime = z.string().datetime({ offset: true })
const rowSchema = z.object({
  id: z.string().uuid(),
  bucket_id: z.literal('body-checkin-photos'),
  object_path: z.string().min(1),
  status: z.enum(['pending_upload', 'uploaded', 'processing', 'processed', 'failed', 'deleted']),
  failure_stage: z.enum(['upload', 'processing']).nullable(),
  context_text: z.string().nullable(),
  created_at: dateTime,
  uploaded_at: dateTime.nullable(),
  processing_result: z.unknown().optional(),
})

export function createSupabaseSignupBodyPhotoFinalizationDependencies(
  client: ServiceClient,
  options: { includeDeleted?: boolean } = {},
): FinalizationDependencies {
  return {
    repository: {
      async loadSnapshot(userId, signal) {
        const query = client
          .from('media_assets')
          .select(photoColumns)
          .eq('user_id', userId)
          .eq('kind', SIGNUP_BODY_PHOTO_KIND)
          .eq('signup_origin', true)
        const { data, error } = await (options.includeDeleted
          ? query.order('deleted_at', { ascending: false, nullsFirst: true })
          : query.neq('status', 'deleted').order('created_at', { ascending: false })
        )
          .limit(1000)
          .abortSignal(signal)
        if (error || !Array.isArray(data)) throw new Error('photo_snapshot_unavailable')
        return data.flatMap((raw) => {
          const row = rowSchema.parse(raw)
          const pose = signupBodyPhotoPoseOf(row.context_text)
          if (!pose) return []
          return [
            {
              id: row.id,
              userId,
              bucketId: row.bucket_id,
              objectPath: row.object_path,
              pose,
              status: row.status,
              failureStage: row.failure_stage,
              createdAt: row.created_at,
              uploadedAt: row.uploaded_at,
              bodyFatPercent: signupBodyPhotoReadingPercent(row.processing_result),
            },
          ]
        })
      },
      async persistProvenance(userId, patch, signal) {
        return await client
          .from('user_profiles')
          .update(patch)
          .eq('user_id', userId)
          .select('user_id, bf_percent_estimated, bf_source, bf_estimated_at')
          .abortSignal(signal)
      },
      async markDeleted(userId, ids, deletedAt, signal) {
        return await client
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
          .eq('signup_origin', true)
          .in('id', [...ids])
          .neq('status', 'deleted')
          .select('id, user_id, status, deleted_at, processing_result')
          .abortSignal(signal)
      },
    },
    storage: {
      async remove(bucket, paths) {
        const { error } = await client.storage.from(bucket).remove([...paths])
        if (error) throw new Error('photo_cleanup_unavailable')
      },
    },
    resolveCandidate: deferSignupBodyPhotoCandidate,
    now: () => performance.now(),
    warn: (event) => console.warn('[mobile-signup-body-photos] finalization_incomplete', event),
  }
}

const completionSchema = z.object({
  onboarding_completed: z.boolean(),
  onboarding_completed_at: dateTime.nullable(),
  sex: z.enum(['masculino', 'feminino']).nullable().optional(),
})

// This completion column predates the generated client types in this checkout.
interface CompletionQuery {
  select(columns: string): CompletionQuery
  eq(column: string, value: unknown): CompletionQuery
  abortSignal(signal: AbortSignal): CompletionQuery
  maybeSingle(): PromiseLike<{ data: unknown; error: unknown }>
}

export async function repairCompletedSignupBodyPhotos(
  client: ServiceClient,
  userId: string,
): Promise<{ completed: boolean }> {
  if (!signupBodyPhotoFinalizationTargetAllowed()) {
    throw new MobileApiError(404, 'body_photos_unavailable', 'Body photos are not available')
  }
  const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(client, {
    includeDeleted: true,
  })
  const deadline = dependencies.now() + 3000
  const loadPhotos = dependencies.repository.loadSnapshot
  let completed = false
  let sex: 'masculino' | 'feminino' | null = null
  dependencies.repository.loadSnapshot = async (owner, signal) => {
    const query = client.from('user_profiles') as unknown as CompletionQuery
    const { data, error } = await query
      .select('onboarding_completed, onboarding_completed_at, sex')
      .eq('user_id', owner)
      .abortSignal(signal)
      .maybeSingle()
    if (error) throw new Error('photo_completion_unavailable')
    if (signal.aborted || dependencies.now() >= deadline)
      throw new Error('photo_completion_stopped')
    // Auth bootstrap normally ensures this row exists. Missing data cannot
    // authorize erasing an account's photos via the open-signup path.
    if (data === null) throw new Error('photo_completion_unknown')
    const profile = completionSchema.parse(data)
    completed = profile.onboarding_completed || profile.onboarding_completed_at !== null
    sex = profile.sex ?? null
    if (signal.aborted || dependencies.now() >= deadline)
      throw new Error('photo_completion_stopped')
    return completed ? loadPhotos(owner, signal) : []
  }
  dependencies.resolveCandidate = async (snapshot, _sex, signal) =>
    deferSignupBodyPhotoCandidate(snapshot, sex, signal)
  const outcome = await finalizeSignupBodyPhotos(
    { userId, sex: null, cleanupDeletedObjects: true, deadline },
    dependencies,
  )
  if (outcome.state !== 'empty' && outcome.state !== 'complete') {
    throw new MobileApiError(
      503,
      'body_photo_cleanup_pending',
      'Body photo cleanup is pending; try again',
    )
  }
  return { completed }
}

export async function finalizeSignupBodyPhotosAfterOnboarding(
  context: MobileRouteContext,
  input: OnboardingCompletionInput,
): Promise<void> {
  if (!signupBodyPhotoFinalizationTargetAllowed()) return
  await finalizeSignupBodyPhotos(
    { userId: context.auth.userId, sex: input.sex },
    createSupabaseSignupBodyPhotoFinalizationDependencies(context.supabase),
  )
}
