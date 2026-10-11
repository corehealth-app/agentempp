/**
 * Body photos of the sign-up (docs/mobile/api-v1.md, "Fotos do corpo no
 * cadastro").
 *
 * WHAT EXISTS HERE: the switch, the consent of its own, the minimum age, the
 * reading of the state, and one photo per pose — created, uploaded,
 * completed, replaced and deleted. NO AI READING: nothing in this file asks
 * for one, and a stored photo stays "uploaded". There is no estimate.
 *
 * THE CONSENT. The photos are offered before the notices of the sign-up are
 * accepted, so their acceptance is asked for on the spot and recorded at once:
 * a row of `legal_documents` with the key below, accepted through the generic
 * functions of the legal documents. The text itself is data, not code.
 * Without the acceptance of the version in force the server neither hands an
 * upload ticket nor completes an upload.
 *
 * THE MINIMUM AGE is checked on the DECLARED birth date, which is sent in the
 * body of the acceptance, compared and dropped: the function that records the
 * acceptance does not receive it, so it cannot reach the database.
 *
 * WHERE THE POSE IS KEPT. The media catalogue has no column for it, and no
 * migration is made: the photo's private context holds one of three fixed
 * sentences, and the pose is read back from it by exact equality. The client
 * has no read access to that column and no answer of these routes carries it.
 * A photo of the sign-up IS a body photo whose context is one of the three.
 *
 * ORDER OF A CREATION, fixed: (1) the Idempotency-Key is looked up first — a
 * photo already created with it is handed back with a new upload ticket,
 * nothing is deleted and nothing counts in the limit; (2) the checks: consent
 * of the version in force, sign-up not completed, limit; (3) the photo is
 * created; (4) nothing is deleted here. The earlier photo of a pose is only
 * deleted when the new one COMPLETES its upload, so a new upload that fails
 * leaves the earlier photo whole.
 *
 * DELETING removes the stored objects and marks the catalogue rows as
 * deleted, emptying what a reading may have left. The rows are not removed:
 * the limit counts them. It never depends on the switch.
 *
 * AN UPLOAD TICKET IS VALID FOR TWO HOURS AND CANNOT BE REVOKED, so bytes may
 * arrive at the path of a photo that was already deleted, replaced or refused.
 * That is why deleting asks the storage to remove the object of EVERY photo of
 * the sign-up the account ever created, the ones already marked as deleted
 * included, each time it is called — with no time window: the person may only
 * come back, and the app only delete again, the next day. What it cannot
 * reach are bytes that arrive after the LAST deletion. ("Every" is one page
 * of the catalogue, the photos not deleted first: see the adapter.)
 */
import { createHash } from 'node:crypto'
import type { MobileAuthContext } from './auth'
import type { SignupBodyPhotoUploadInput } from './contracts'
import { MobileApiError } from './http'
import {
  completeMediaUpload,
  createMediaAsset,
  type MediaAssetRecord,
  type MediaAssetStatus,
  type MediaServiceDependencies,
} from './media-service'

/** The row of `legal_documents` that holds the consent of the body photos. */
export const BODY_PHOTO_CONSENT_KEY = 'body_photo_estimate_consent'

/**
 * Minimum age for the photo path, by the declared birth date. Decisão do
 * orquestrador, anunciada ao dono em 2026-10-10/11, que pode riscar qualquer
 * uma (D3). It is not an approval of the owner nor of the physician.
 */
export const SIGNUP_BODY_PHOTO_MINIMUM_AGE = 18

/**
 * Photos an account may create in 24 hours, counting the deleted ones and the
 * ones never uploaded. A number of the plan (three poses, three times), which
 * waits for the owner's confirmation: it is not a decision of his.
 */
export const SIGNUP_BODY_PHOTO_DAILY_LIMIT = 9
const LIMIT_WINDOW_HOURS = 24

/** The day an account without a usable time zone is counted on (the default of `users.timezone`). */
const DEFAULT_TIME_ZONE = 'America/Sao_Paulo'

export const SIGNUP_BODY_PHOTO_KIND = 'body_checkin_photo'

export const SIGNUP_BODY_PHOTO_POSES = ['front', 'side', 'back'] as const
export type SignupBodyPhotoPose = (typeof SIGNUP_BODY_PHOTO_POSES)[number]

/** What the photo's private context holds for each pose. Never shown, never answered. */
export const SIGNUP_BODY_PHOTO_POSE_CONTEXT: Record<SignupBodyPhotoPose, string> = {
  front: 'Foto de frente.',
  side: 'Foto de lado.',
  back: 'Foto de costas.',
}

/** The pose a context sentence stands for, by exact equality; null for anything else. */
export function signupBodyPhotoPoseOf(contextText: string | null): SignupBodyPhotoPose | null {
  return (
    SIGNUP_BODY_PHOTO_POSES.find((pose) => SIGNUP_BODY_PHOTO_POSE_CONTEXT[pose] === contextText) ??
    null
  )
}

export type SignupBodyPhotoUnavailableReason = 'disabled' | 'consent_text_missing'

/**
 * How a photo is told to the app. `uploaded` is a photo the server holds and
 * that nobody was asked to read — the only stored state these routes produce.
 * `reading`, `read` and `reading_failed` tell a row the reading program
 * touched; whether a finished reading brought a number is not looked at here.
 */
export type SignupBodyPhotoStatus =
  | 'pending_upload'
  | 'uploaded'
  | 'reading'
  | 'read'
  | 'reading_failed'
  | 'upload_failed'
  | 'deleted'

export interface SignupBodyPhotoConsentDocument {
  documentKey: typeof BODY_PHOTO_CONSENT_KEY
  version: string
  locale: 'pt-BR' | 'en-US'
  body: string
  /** SHA-256 of the stored text, computed by the database. */
  bodyHash: string
}

export interface SignupBodyPhotoConsentRepository {
  /** The text in force for the account's language; null when there is none. */
  currentDocument(userId: string): Promise<SignupBodyPhotoConsentDocument | null>
  /** When the account accepted this version; null when it did not. */
  acceptedAt(userId: string, version: string): Promise<string | null>
  accept(input: {
    userId: string
    version: string
    bodyHash: string
    idempotencyKey: string
  }): Promise<{ version: string; acceptedAt: string }>
}

/** A photo of the sign-up as the catalogue holds it, without what a reading left. */
export interface SignupBodyPhotoRow {
  id: string
  bucketId: string
  objectPath: string
  pose: SignupBodyPhotoPose
  status: MediaAssetStatus
  failureStage: 'upload' | 'processing' | null
  createdAt: string
  uploadedAt: string | null
}

export interface SignupBodyPhotoCatalogue {
  /** Every photo of the sign-up of the account that is not deleted. */
  listOpen(userId: string): Promise<SignupBodyPhotoRow[]>
  /** Every photo of the sign-up the account ever created, the deleted ones included. */
  listEvery(userId: string): Promise<SignupBodyPhotoRow[]>
  /** How many photos of the sign-up the account created since an instant, deleted ones included. */
  countCreatedSince(userId: string, since: string): Promise<number>
  /** Marks the photos as deleted and empties what a reading left, in one write. Returns how many. */
  markDeleted(userId: string, photoIds: string[], deletedAt: string): Promise<number>
  /** Removes stored objects in one storage call. */
  removeObjects(bucketId: string, objectPaths: string[]): Promise<void>
  /** Whether the account already completed the sign-up. */
  onboardingCompleted(userId: string): Promise<boolean>
}

export interface SignupBodyPhotoDependencies {
  /** The switch, as resolved from the environment (off unless switched on). */
  enabled: boolean
  consent: SignupBodyPhotoConsentRepository
  catalogue: SignupBodyPhotoCatalogue
  /** The generic media catalogue and storage: creating and completing an upload are theirs. */
  media: MediaServiceDependencies
}

export interface SignupBodyPhotoConsentDto {
  document_key: typeof BODY_PHOTO_CONSENT_KEY
  version: string
  locale: 'pt-BR' | 'en-US'
  body: string
  body_hash: string
  accepted_at: string | null
}

export interface SignupBodyPhotoPoseDto {
  pose: SignupBodyPhotoPose
  photo: { id: string; status: SignupBodyPhotoStatus; created_at: string } | null
}

export interface SignupBodyPhotoState {
  available: boolean
  unavailable_reason: SignupBodyPhotoUnavailableReason | null
  consent: SignupBodyPhotoConsentDto | null
  minimum_age: number
  poses: SignupBodyPhotoPoseDto[]
  estimate: null
  remaining_uploads: number
}

export interface SignupBodyPhotoAcceptanceDto {
  document_key: typeof BODY_PHOTO_CONSENT_KEY
  version: string
  accepted_at: string
}

export interface SignupBodyPhotoDto {
  id: string
  pose: SignupBodyPhotoPose
  status: SignupBodyPhotoStatus
  created_at: string
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex')
}

function publicStatus(
  status: MediaAssetStatus,
  failureStage: 'upload' | 'processing' | null,
): SignupBodyPhotoStatus {
  if (status === 'processing') return 'reading'
  if (status === 'processed') return 'read'
  if (status === 'failed') return failureStage === 'processing' ? 'reading_failed' : 'upload_failed'
  return status
}

/** A photo the server holds: its upload was completed and it was not deleted. */
function isStored(status: MediaAssetStatus, failureStage: 'upload' | 'processing' | null): boolean {
  return (
    status === 'uploaded' ||
    status === 'processing' ||
    status === 'processed' ||
    (status === 'failed' && failureStage === 'processing')
  )
}

function instant(value: string | null): number {
  const parsed = value ? Date.parse(value) : Number.NaN
  return Number.isNaN(parsed) ? 0 : parsed
}

/** Whether one stored photo came before another: by the time its upload was completed, then by id. */
function storedBefore(
  left: { id: string; uploadedAt: string | null },
  right: { id: string; uploadedAt: string | null },
): boolean {
  const [leftAt, rightAt] = [instant(left.uploadedAt), instant(right.uploadedAt)]
  return leftAt < rightAt || (leftAt === rightAt && left.id < right.id)
}

function emptyPoses(): SignupBodyPhotoPoseDto[] {
  return SIGNUP_BODY_PHOTO_POSES.map((pose) => ({ pose, photo: null }))
}

function unavailableState(reason: SignupBodyPhotoUnavailableReason): SignupBodyPhotoState {
  return {
    available: false,
    unavailable_reason: reason,
    consent: null,
    minimum_age: SIGNUP_BODY_PHOTO_MINIMUM_AGE,
    poses: emptyPoses(),
    estimate: null,
    remaining_uploads: 0,
  }
}

export function signupBodyPhotosUnavailable(): MobileApiError {
  return new MobileApiError(404, 'body_photos_unavailable', 'Body photos are not available')
}

function onboardingAlreadyCompleted(): MobileApiError {
  return new MobileApiError(409, 'onboarding_already_completed', 'Onboarding is already completed')
}

function limitWindowStart(now: Date): string {
  return new Date(now.getTime() - LIMIT_WINDOW_HOURS * 60 * 60 * 1000).toISOString()
}

export async function getSignupBodyPhotoState(
  dependencies: SignupBodyPhotoDependencies,
  auth: MobileAuthContext,
  now = new Date(),
): Promise<SignupBodyPhotoState> {
  if (!dependencies.enabled) return unavailableState('disabled')

  const document = await dependencies.consent.currentDocument(auth.userId)
  if (!document) return unavailableState('consent_text_missing')
  const [acceptedAt, open, createdInWindow] = await Promise.all([
    dependencies.consent.acceptedAt(auth.userId, document.version),
    dependencies.catalogue.listOpen(auth.userId),
    dependencies.catalogue.countCreatedSince(auth.userId, limitWindowStart(now)),
  ])

  return {
    available: true,
    unavailable_reason: null,
    consent: {
      document_key: document.documentKey,
      version: document.version,
      locale: document.locale,
      body: document.body,
      body_hash: document.bodyHash,
      accepted_at: acceptedAt,
    },
    minimum_age: SIGNUP_BODY_PHOTO_MINIMUM_AGE,
    // Only a photo whose upload was completed is in its pose; when two are
    // stored for one pose (two completions at once), the newest.
    poses: SIGNUP_BODY_PHOTO_POSES.map((pose) => {
      const newest = open
        .filter((row) => row.pose === pose && isStored(row.status, row.failureStage))
        .reduce<SignupBodyPhotoRow | null>(
          (latest, row) => (latest === null || storedBefore(latest, row) ? row : latest),
          null,
        )
      return {
        pose,
        photo: newest && {
          id: newest.id,
          status: publicStatus(newest.status, newest.failureStage),
          created_at: newest.createdAt,
        },
      }
    }),
    estimate: null,
    remaining_uploads: Math.max(0, SIGNUP_BODY_PHOTO_DAILY_LIMIT - createdInWindow),
  }
}

/** Today's calendar date (YYYY-MM-DD) in a time zone; null when the zone is not one. */
function calendarDateIn(timeZone: string, now: Date): string | null {
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(now)
    const part = (type: string) => parts.find((entry) => entry.type === type)?.value
    const [year, month, day] = [part('year'), part('month'), part('day')]
    return year && month && day ? `${year}-${month}-${day}` : null
  } catch {
    return null
  }
}

/**
 * Whole years between a birth date and a day, both YYYY-MM-DD. A year is
 * complete on the day of the same month and number; when the year has no such
 * day (29 February), on the first day after it (1 March).
 */
export function wholeYearsOn(birthDate: string, day: string): number {
  const [birthYear = 0, birthMonth = 0, birthDay = 0] = birthDate.split('-').map(Number)
  const [year = 0, month = 0, dayOfMonth = 0] = day.split('-').map(Number)
  const beforeBirthday = month < birthMonth || (month === birthMonth && dayOfMonth < birthDay)
  return year - birthYear - (beforeBirthday ? 1 : 0)
}

/**
 * Refuses the photo path to whoever DECLARES less than the minimum age, on
 * today's date in the account's time zone. Reads and writes nothing: call it
 * before anything is claimed or recorded, so a refusal leaves no trace.
 */
export function assertSignupBodyPhotoAge(
  birthDate: string,
  accountTimeZone: string | null,
  now: Date,
): void {
  const today =
    (accountTimeZone ? calendarDateIn(accountTimeZone, now) : null) ??
    calendarDateIn(DEFAULT_TIME_ZONE, now) ??
    now.toISOString().slice(0, 10)
  if (wholeYearsOn(birthDate, today) < SIGNUP_BODY_PHOTO_MINIMUM_AGE) {
    throw new MobileApiError(
      403,
      'body_photo_age_not_allowed',
      'Body photos are only for people of the minimum age',
      { minimum_age: SIGNUP_BODY_PHOTO_MINIMUM_AGE },
    )
  }
}

/**
 * Records the acceptance of the text the person read. It takes the version
 * and the mark and nothing else: the birth date stays with the caller.
 */
export async function acceptSignupBodyPhotoConsent(
  dependencies: SignupBodyPhotoDependencies,
  auth: MobileAuthContext,
  acceptance: { version: string; body_hash: string },
  idempotencyKey: string,
): Promise<SignupBodyPhotoAcceptanceDto> {
  if (!dependencies.enabled) throw signupBodyPhotosUnavailable()

  const accepted = await dependencies.consent.accept({
    userId: auth.userId,
    version: acceptance.version,
    bodyHash: acceptance.body_hash,
    idempotencyKey,
  })
  return {
    document_key: BODY_PHOTO_CONSENT_KEY,
    version: accepted.version,
    accepted_at: accepted.acceptedAt,
  }
}

/**
 * The two conditions under which the server takes a body photo of the
 * sign-up: the account accepted the consent text in force, and it has not
 * completed the sign-up.
 */
async function assertSignupOpenWithConsent(
  dependencies: SignupBodyPhotoDependencies,
  userId: string,
): Promise<void> {
  const document = await dependencies.consent.currentDocument(userId)
  if (!document) throw signupBodyPhotosUnavailable()
  if ((await dependencies.consent.acceptedAt(userId, document.version)) === null) {
    throw new MobileApiError(
      403,
      'body_photo_consent_required',
      'Accept the body photo consent first',
    )
  }
  if (await dependencies.catalogue.onboardingCompleted(userId)) throw onboardingAlreadyCompleted()
}

/** Whether a photo already created with a key is the one this request asks for. */
function isSameCreation(existing: MediaAssetRecord, input: SignupBodyPhotoUploadInput): boolean {
  return (
    existing.kind === SIGNUP_BODY_PHOTO_KIND &&
    signupBodyPhotoPoseOf(existing.context_text) === input.pose &&
    existing.mime_type === input.mime_type &&
    existing.declared_size_bytes === input.size_bytes
  )
}

export async function createSignupBodyPhoto(
  dependencies: SignupBodyPhotoDependencies,
  auth: MobileAuthContext,
  input: SignupBodyPhotoUploadInput,
  requestKey: string,
  now = new Date(),
): Promise<{
  photo: SignupBodyPhotoDto
  upload: Awaited<ReturnType<typeof createMediaAsset>>['upload']
  replayed: boolean
}> {
  if (!dependencies.enabled) throw signupBodyPhotosUnavailable()
  const userId = auth.userId

  // (1) The key first. A repetition must find the photo the first call
  // created, whatever changed since: a check made before this lookup would
  // refuse (or, worse, a cleanup would delete) the very photo being repeated.
  const existing = await dependencies.media.repository.findByRequestHash(userId, sha256(requestKey))
  if (existing) {
    if (!isSameCreation(existing, input)) {
      throw new MobileApiError(
        409,
        'idempotency_key_conflict',
        'Idempotency-Key was already used for another request',
      )
    }
  } else {
    // (2) The checks of a new photo.
    await assertSignupOpenWithConsent(dependencies, userId)
    const createdInWindow = await dependencies.catalogue.countCreatedSince(
      userId,
      limitWindowStart(now),
    )
    if (createdInWindow >= SIGNUP_BODY_PHOTO_DAILY_LIMIT) {
      throw new MobileApiError(
        429,
        'body_photo_limit_reached',
        'Too many body photos were created; try again later',
        { limit: SIGNUP_BODY_PHOTO_DAILY_LIMIT, window_hours: LIMIT_WINDOW_HOURS },
      )
    }
  }

  // (3) The photo is created — or, on a repetition, found again by the media
  // service, which hands a new ticket while the upload is still pending.
  // (4) Nothing is deleted here: see `completeSignupBodyPhoto`.
  const result = await createMediaAsset(
    dependencies.media,
    userId,
    {
      kind: SIGNUP_BODY_PHOTO_KIND,
      mime_type: input.mime_type,
      size_bytes: input.size_bytes,
      context_text: SIGNUP_BODY_PHOTO_POSE_CONTEXT[input.pose],
    },
    requestKey,
    now,
  )
  return {
    photo: {
      id: result.asset.id,
      pose: input.pose,
      status: publicStatus(result.asset.status, result.asset.failure_stage),
      created_at: result.asset.created_at,
    },
    upload: result.upload,
    replayed: result.replayed,
  }
}

export async function completeSignupBodyPhoto(
  dependencies: SignupBodyPhotoDependencies,
  auth: MobileAuthContext,
  photoId: string,
  now = new Date(),
): Promise<{ photo: SignupBodyPhotoDto }> {
  if (!dependencies.enabled) throw signupBodyPhotosUnavailable()
  const userId = auth.userId

  // Owner and kind first: the photo of another account, another kind of media
  // and a body photo that is not of the sign-up are all "not found".
  const asset = await dependencies.media.repository.findOwned(userId, photoId)
  const pose =
    asset?.kind === SIGNUP_BODY_PHOTO_KIND ? signupBodyPhotoPoseOf(asset.context_text) : null
  if (!asset || !pose) {
    throw new MobileApiError(404, 'body_photo_not_found', 'Body photo not found')
  }

  let stored = {
    id: asset.id,
    status: asset.status,
    failureStage: asset.failure_stage,
    createdAt: asset.created_at,
    uploadedAt: asset.uploaded_at,
  }
  if (asset.status === 'pending_upload') {
    await assertSignupOpenWithConsent(dependencies, userId)
    // The stored size and type are checked against the declaration. A refusal
    // (422) marks THIS photo as a failed upload and goes no further: the
    // earlier photo of the pose is not looked at.
    const completed = await completeMediaUpload(dependencies.media, userId, photoId, now)
    stored = {
      id: completed.id,
      status: completed.status,
      failureStage: completed.failure_stage,
      createdAt: completed.created_at,
      uploadedAt: completed.uploaded_at,
    }
  } else if (!isStored(asset.status, asset.failure_stage)) {
    // Deleted, or refused at upload. The ticket handed for it is valid for
    // two hours and cannot be revoked: whatever arrived with it is removed.
    await dependencies.catalogue.removeObjects(asset.bucket_id, [asset.object_path])
    throw new MobileApiError(409, 'media_upload_not_pending', 'Media upload is not pending')
  }

  // The photo is stored. Only now do the earlier photos of the same pose go —
  // also when this is a repeated completion, so a replacement that stopped
  // half-way is finished. A photo stored AFTER this one is never touched.
  const earlier = (await dependencies.catalogue.listOpen(userId)).filter(
    (row) =>
      row.id !== stored.id &&
      row.pose === pose &&
      isStored(row.status, row.failureStage) &&
      storedBefore(row, stored),
  )
  if (earlier.length > 0) {
    for (const bucketId of new Set(earlier.map((row) => row.bucketId))) {
      await dependencies.catalogue.removeObjects(
        bucketId,
        earlier.filter((row) => row.bucketId === bucketId).map((row) => row.objectPath),
      )
    }
    await dependencies.catalogue.markDeleted(
      userId,
      earlier.map((row) => row.id),
      now.toISOString(),
    )
  }

  return {
    photo: {
      id: stored.id,
      pose,
      status: publicStatus(stored.status, stored.failureStage),
      created_at: stored.createdAt,
    },
  }
}

/**
 * Deletes every photo of the sign-up of the account. It works with the switch
 * in any position and for an account that already completed the sign-up.
 *
 * `deleted` counts the rows marked by THIS call. The storage is asked to
 * remove the object of every photo of the sign-up the account ever created,
 * whatever its row says: see "AN UPLOAD TICKET" at the top of this file.
 */
export async function deleteSignupBodyPhotos(
  dependencies: SignupBodyPhotoDependencies,
  auth: MobileAuthContext,
  now = new Date(),
): Promise<{ deleted: number }> {
  // One read, of every row: the ones already deleted too, because bytes sent
  // with an old ticket may be stored at their paths.
  const every = await dependencies.catalogue.listEvery(auth.userId)
  if (every.length === 0) return { deleted: 0 }

  // The objects first, the catalogue after: a failure in between leaves rows
  // that still say a photo exists, never a stored photo with no row.
  for (const bucketId of new Set(every.map((row) => row.bucketId))) {
    await dependencies.catalogue.removeObjects(
      bucketId,
      every.filter((row) => row.bucketId === bucketId).map((row) => row.objectPath),
    )
  }
  // What is marked now: the rows not yet deleted. A photo refused at upload
  // cannot become "deleted" (the catalogue forbids that change): its bytes,
  // if any arrived later, were removed above, and its row stays what it is.
  const deletable = every.filter(
    (row) =>
      row.status !== 'deleted' && !(row.status === 'failed' && row.failureStage === 'upload'),
  )
  if (deletable.length === 0) return { deleted: 0 }
  return {
    deleted: await dependencies.catalogue.markDeleted(
      auth.userId,
      deletable.map((row) => row.id),
      now.toISOString(),
    ),
  }
}
