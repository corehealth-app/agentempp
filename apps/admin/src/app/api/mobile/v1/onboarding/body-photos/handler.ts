/**
 * Handlers of the three routes of the body photos of the sign-up
 * (docs/mobile/api-v1.md, "Fotos do corpo no cadastro"):
 *
 *   GET    /onboarding/body-photos               the state
 *   POST   /onboarding/body-photos               create one photo of a pose
 *   DELETE /onboarding/body-photos               delete every photo
 *   POST   /onboarding/body-photos/consent       accept the consent
 *   POST   /onboarding/body-photos/:id/complete  complete an upload
 *
 * With the switch off, the state says "not available" and the three POSTs
 * answer 404 before anything of the request is read; deleting never depends
 * on the switch, but is confined to known staging before its claim. GET is
 * also unavailable on other targets. Completion requests a reading only with the switch on,
 * current consent accepted and the sign-up still open.
 */
import {
  resourceIdSchema,
  signupBodyPhotoConsentInputSchema,
  signupBodyPhotoUploadInputSchema,
} from '@/lib/mobile-api/contracts'
import {
  MobileApiError,
  mobileErrorResponse,
  mobileSuccess,
  readJsonBody,
} from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent, requireIdempotencyKey } from '@/lib/mobile-api/idempotency'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import {
  acceptSignupBodyPhotoConsent,
  assertSignupBodyPhotoAge,
  BODY_PHOTO_CONSENT_KEY,
  completeSignupBodyPhoto,
  createSignupBodyPhoto,
  deleteSignupBodyPhotos,
  getSignupBodyPhotoState,
  type SignupBodyPhotoDependencies,
  signupBodyPhotosUnavailable,
} from '@/lib/mobile-api/signup-body-photo-service'
import { signupBodyPhotosEnabled } from '@/lib/mobile-api/signup-body-photo-switch'
import { signupBodyPhotoFinalizationTargetAllowed } from '@/lib/mobile-api/supabase-signup-body-photo-finalization'
import { createSupabaseSignupBodyPhotoDependencies } from '@/lib/mobile-api/supabase-signup-body-photos'

export interface SignupBodyPhotoRouteDependencies {
  /** Builds the service over the request's database client. It queries nothing by itself. */
  createService(context: MobileRouteContext): SignupBodyPhotoDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
  now(): Date
}

export interface SignupBodyPhotoCompleteRouteContext {
  params: Promise<{ id: string }>
}

const defaultDependencies: SignupBodyPhotoRouteDependencies = {
  createService: (context) =>
    createSupabaseSignupBodyPhotoDependencies(context.supabase, {
      enabled: signupBodyPhotosEnabled() && signupBodyPhotoFinalizationTargetAllowed(),
      requestId: context.requestId,
    }),
  executeIdempotent: executeSupabaseIdempotent,
  now: () => new Date(),
}

export async function handleSignupBodyPhotosGet(
  context: MobileRouteContext,
  dependencies: SignupBodyPhotoRouteDependencies = defaultDependencies,
): Promise<Response> {
  return mobileSuccess(
    await getSignupBodyPhotoState(
      dependencies.createService(context),
      context.auth,
      dependencies.now(),
    ),
    context.requestId,
  )
}

export async function handleSignupBodyPhotosPost(
  context: MobileRouteContext,
  dependencies: SignupBodyPhotoRouteDependencies = defaultDependencies,
): Promise<Response> {
  const service = dependencies.createService(context)
  // Off, the route answers as a server that has no photos, whatever the
  // request carries: nothing is read from it and no key is claimed.
  if (!service.enabled) throw signupBodyPhotosUnavailable()

  const input = signupBodyPhotoUploadInputSchema.parse(await readJsonBody(context.request))
  const requestKey = requireIdempotencyKey(context.request)
  const createResponse = async () =>
    mobileSuccess(
      await createSignupBodyPhoto(service, context.auth, input, requestKey, dependencies.now()),
      context.requestId,
      201,
    )
  // As POST /media: a repetition runs the creation again, which finds the
  // same photo by its key and hands a NEW upload ticket; and what the ledger
  // keeps of the answer is not the answer, because it carries that ticket.
  return dependencies.executeIdempotent(context, input, createResponse, {
    refreshReplay: createResponse,
    responseBodyForStorage: () => ({ temporary_capability_redacted: true }),
  })
}

export async function handleSignupBodyPhotosDelete(
  context: MobileRouteContext,
  dependencies: SignupBodyPhotoRouteDependencies = defaultDependencies,
): Promise<Response> {
  // The switch cannot prevent deleting one's photos. The database target can:
  // this delivery is confined to known staging, before any claim/photo query.
  if (!signupBodyPhotoFinalizationTargetAllowed()) throw signupBodyPhotosUnavailable()
  const service = dependencies.createService(context)
  const deleteAll = async () =>
    mobileSuccess(
      await deleteSignupBodyPhotos(service, context.auth, dependencies.now()),
      context.requestId,
    )
  // A repeated key runs the deletion AGAIN, never the stored answer: every
  // 200 of this route comes from a deletion that ran now — the storage was
  // asked to remove the object of every photo of the sign-up the account
  // ever created — even for a client that reuses its key after sending
  // another photo. Bytes that arrive AFTER it, with an upload ticket that is
  // still valid, stay until the next deletion.
  return dependencies.executeIdempotent(context, { body_photos: 'all' }, deleteAll, {
    refreshReplay: deleteAll,
  })
}

export async function handleSignupBodyPhotoConsentPost(
  context: MobileRouteContext,
  dependencies: SignupBodyPhotoRouteDependencies = defaultDependencies,
): Promise<Response> {
  const service = dependencies.createService(context)
  if (!service.enabled) throw signupBodyPhotosUnavailable()

  const input = signupBodyPhotoConsentInputSchema.parse(await readJsonBody(context.request))
  // The age is refused BEFORE the Idempotency-Key is claimed (the header is
  // only read here, so its absence is still 400): a refusal leaves no record
  // at all, not even a released key.
  requireIdempotencyKey(context.request)
  assertSignupBodyPhotoAge(input.birth_date, context.auth.patient.timezone, dependencies.now())

  // What is claimed, hashed and recorded is the acceptance WITHOUT the birth
  // date: the ledger keeps the hash of the request, and the hash of a date of
  // birth can be undone by trying every day of a century.
  const acceptance = {
    document_key: BODY_PHOTO_CONSENT_KEY,
    version: input.version,
    body_hash: input.body_hash,
  }
  return dependencies.executeIdempotent(context, acceptance, async (idempotencyKey) =>
    mobileSuccess(
      await acceptSignupBodyPhotoConsent(service, context.auth, acceptance, idempotencyKey),
      context.requestId,
    ),
  )
}

export async function handleSignupBodyPhotoCompletePost(
  context: MobileRouteContext,
  routeContext: SignupBodyPhotoCompleteRouteContext,
  dependencies: SignupBodyPhotoRouteDependencies = defaultDependencies,
): Promise<Response> {
  const service = dependencies.createService(context)
  if (!service.enabled) throw signupBodyPhotosUnavailable()

  const { id: rawId } = await routeContext.params
  const id = resourceIdSchema.parse(rawId)
  return dependencies.executeIdempotent(context, { body_photo_id: id }, async (idempotencyKey) => {
    try {
      return mobileSuccess(
        await completeSignupBodyPhoto(
          service,
          context.auth,
          id,
          idempotencyKey,
          dependencies.now(),
        ),
        context.requestId,
      )
    } catch (error) {
      // These two refusals changed the photo (it is now a failed upload), so
      // they are kept and replayed like an answer, as in POST /media/:id/complete.
      if (
        error instanceof MobileApiError &&
        ['media_upload_mismatch', 'media_upload_missing'].includes(error.code)
      ) {
        return mobileErrorResponse(error, context.requestId)
      }
      throw error
    }
  })
}
