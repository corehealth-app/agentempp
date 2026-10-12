import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { OnboardingCompletionInput } from './contracts'
import { MobileApiError } from './http'
import type { MobileRouteContext } from './route'
import { disposeSignupBodyPhotos } from './signup-body-photo-disposition'
import {
  deferSignupBodyPhotoCandidate,
  type FinalizationDependencies,
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

export async function repairCompletedSignupBodyPhotos(
  client: ServiceClient,
  userId: string,
): Promise<{ completed: boolean; newlyDeleted: number }> {
  if (!signupBodyPhotoFinalizationTargetAllowed()) {
    throw new MobileApiError(404, 'body_photos_unavailable', 'Body photos are not available')
  }
  const outcome = await disposeSignupBodyPhotos(client, userId, { drainAllGenerations: true })
  if (outcome.state !== 'empty' && outcome.state !== 'complete') {
    throw new MobileApiError(
      503,
      'body_photo_cleanup_pending',
      'Body photo cleanup is pending; try again',
    )
  }
  return { completed: outcome.completed, newlyDeleted: outcome.newlyDeleted }
}

export async function finalizeSignupBodyPhotosAfterOnboarding(
  context: MobileRouteContext,
  _input: OnboardingCompletionInput,
  generation: string,
): Promise<void> {
  if (!signupBodyPhotoFinalizationTargetAllowed()) return
  await disposeSignupBodyPhotos(context.supabase, context.auth.userId, {
    generation,
    drainAllGenerations: false,
  })
}
