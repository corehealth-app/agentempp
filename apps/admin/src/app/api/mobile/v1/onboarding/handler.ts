import type { ServiceClient } from '@mpp/db'
import { readClinicalRepresentation } from '@/lib/mobile-api/clinical-representation'
import { saveOnboarding } from '@/lib/mobile-api/commands'
import {
  type OnboardingCompletionInput,
  onboardingCompletionInputSchema,
  onboardingInputSchema,
} from '@/lib/mobile-api/contracts'
import {
  type CurrentClinicalAdmission,
  createCurrentClinicalAdmission,
  createSupabaseLegacyClinicalAdmissionSource,
} from '@/lib/mobile-api/current-clinical-admission'
import {
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
} from '@/lib/mobile-api/current-clinical-state'
import { prepareEvaluationAccess } from '@/lib/mobile-api/evaluation-access'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import {
  executeSupabaseIdempotent,
  hashMobileRequest,
  requireIdempotencyKey,
} from '@/lib/mobile-api/idempotency'
import { assertOnboardingObjectiveEligible } from '@/lib/mobile-api/onboarding-eligibility-guard'
import {
  completeOnboarding,
  getOnboardingState,
  MAX_PUBLIC_ONBOARDING_STATE_BYTES,
  type OnboardingRepository,
} from '@/lib/mobile-api/onboarding-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import {
  readSignupBodyPhotoCleanupScope,
  signupCleanupGenerationSchema,
  signupCleanupScopeSchema,
} from '@/lib/mobile-api/signup-body-photo-cleanup-scope'
import {
  type PreparedSignupPhotoConfirmation,
  prepareSignupPhotoConfirmation,
} from '@/lib/mobile-api/signup-body-photo-confirmation'
import { signupBodyPhotosUnavailable } from '@/lib/mobile-api/signup-body-photo-service'
import { loadSignupPhotoSnapshot } from '@/lib/mobile-api/signup-body-photo-snapshot'
import { signupBodyPhotosEnabled } from '@/lib/mobile-api/signup-body-photo-switch'
import {
  captureSignupCompletionSources,
  defaultSignupCompletionComposition,
  type SignupCompletionComposition,
} from '@/lib/mobile-api/signup-completion-composition'
import { snapshotSignupCompletionEpoch } from '@/lib/mobile-api/signup-completion-intent'
import { classifySignupCompletionTransport } from '@/lib/mobile-api/signup-completion-transport'
import {
  type SignupStrengthRequestIdentity,
  snapshotSignupStrengthRequest,
} from '@/lib/mobile-api/signup-strength-authority'
import { createSupabaseCurrentClinicalStateSource } from '@/lib/mobile-api/supabase-current-clinical-state'
import {
  createSupabaseOnboardingRepository,
  type SupabaseOnboardingOptions,
} from '@/lib/mobile-api/supabase-onboarding'
import {
  finalizeSignupBodyPhotosAfterOnboarding,
  signupBodyPhotoFinalizationTargetAllowed,
} from '@/lib/mobile-api/supabase-signup-body-photo-finalization'

export interface OnboardingRouteDependencies {
  createOnboardingRepository(
    client: ServiceClient,
    options?: SupabaseOnboardingOptions,
  ): OnboardingRepository
  executeIdempotent: typeof executeSupabaseIdempotent
  /** Missing in a legacy-only test repository means unavailable, never fallback. */
  signupCompletion?: SignupCompletionComposition
  /** Dormant until the current-clinical SQL transport and all consumers are integrated. */
  currentClinical?: CurrentClinicalStateSource
  clinicalAdmission?: CurrentClinicalAdmission
  saveLegacyOnboarding: typeof saveOnboarding
  readSignupBodyPhotoCleanupScope?: typeof readSignupBodyPhotoCleanupScope
  finalizeSignupBodyPhotos(
    context: MobileRouteContext,
    input: OnboardingCompletionInput,
    generation: string,
  ): Promise<void>
}

const defaultDependencies: OnboardingRouteDependencies = {
  createOnboardingRepository: createSupabaseOnboardingRepository,
  executeIdempotent: executeSupabaseIdempotent,
  saveLegacyOnboarding: saveOnboarding,
  readSignupBodyPhotoCleanupScope,
  finalizeSignupBodyPhotos: finalizeSignupBodyPhotosAfterOnboarding,
  signupCompletion: defaultSignupCompletionComposition,
}

/** Request-scoped building block for the complete current signup factory.
 * Defaults above remain unchanged until the atomic runtime selects it. */
export function createSupabaseCurrentOnboardingDependencies(
  client: ServiceClient,
  signupCompletion: SignupCompletionComposition = defaultSignupCompletionComposition,
) {
  return Object.freeze({
    ...defaultDependencies,
    signupCompletion,
    currentClinical: createSupabaseCurrentClinicalStateSource(client),
    clinicalAdmission: createCurrentClinicalAdmission(
      createSupabaseLegacyClinicalAdmissionSource(client),
    ),
  })
}

function onboardingLocale(locale: string | null): 'pt-BR' | 'en-US' {
  if (locale === null || locale === 'pt-BR') return 'pt-BR'
  if (locale === 'en-US') return locale
  throw new MobileApiError(
    409,
    'onboarding_locale_unsupported',
    'Onboarding is not available for this locale',
  )
}

/**
 * What the idempotency record keeps of a completion: the response without
 * `protocol_welcome`. That text carries the person's name and is never read
 * back, because a replay rebuilds the whole response (`refreshReplay`).
 */
function completionBodyForStorage(body: unknown): unknown {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return body
  const envelope = body as Record<string, unknown>
  const data = envelope.data
  if (!data || typeof data !== 'object' || Array.isArray(data)) return body
  const {
    protocol_welcome: _welcome,
    body_photo_cleanup: _scope,
    ...stored
  } = data as Record<string, unknown>
  return { ...envelope, data: stored }
}

async function withCleanupScope<T extends object>(
  context: MobileRouteContext,
  dependencies: OnboardingRouteDependencies,
  data: T,
  generation: string | null,
) {
  if (
    !signupBodyPhotoFinalizationTargetAllowed() ||
    !dependencies.readSignupBodyPhotoCleanupScope ||
    generation === null ||
    !signupCleanupGenerationSchema.safeParse(generation).success
  )
    return data
  let scope = { generation, state: 'unknown' as 'unknown' | 'pending' | 'not_required' }
  try {
    const parsed = signupCleanupScopeSchema.safeParse(
      await dependencies.readSignupBodyPhotoCleanupScope(
        context.supabase,
        context.auth.userId,
        generation,
      ),
    )
    if (parsed.success && parsed.data.generation === generation) scope = parsed.data
  } catch {
    /* Official completion and base GET remain valid. */
  }
  return { ...data, body_photo_cleanup: scope }
}

/** The same pure query checks precede any current-source admission. */
export function readOnboardingGetQuery(url: string) {
  const search = new URL(url).searchParams
  const schemas = search.getAll('onboarding_profile_schema')
  if (schemas.length > 1 || (schemas.length === 1 && schemas[0] !== 'habitual_water_optional_v1'))
    throw new MobileApiError(
      400,
      'invalid_onboarding_profile_schema',
      'Invalid onboarding profile schema',
    )
  const queries = search.getAll('body_photo_cleanup_generation')
  if (
    queries.length > 1 ||
    (queries.length === 1 && !signupCleanupGenerationSchema.safeParse(queries[0]).success)
  )
    throw new MobileApiError(
      400,
      'invalid_body_photo_cleanup_generation',
      'Invalid cleanup generation',
    )
  return {
    acceptsUnknownWater: schemas[0] === 'habitual_water_optional_v1',
    cleanupGeneration: queries[0],
  }
}
export async function handleOnboardingGet(
  context: MobileRouteContext,
  dependencies: OnboardingRouteDependencies = defaultDependencies,
): Promise<Response> {
  const query = readOnboardingGetQuery(context.request.url)
  const repository = dependencies.createOnboardingRepository(context.supabase)
  const data = await getOnboardingState(
    repository,
    context.auth.userId,
    onboardingLocale(context.auth.patient.locale),
    {
      acceptsUnknownWater: query.acceptsUnknownWater,
      acceptsNullObjective:
        dependencies.currentClinical !== undefined &&
        readClinicalRepresentation(context.request.url).compatible &&
        dependencies.signupCompletion?.enabled() === true,
      acceptsLegacyReconsent:
        dependencies.currentClinical !== undefined &&
        readClinicalRepresentation(context.request.url).compatible &&
        dependencies.signupCompletion?.enabled() === true,
    },
  )
  const generation = query.cleanupGeneration ?? data.completion.completed_at
  const enriched = await withCleanupScope(context, dependencies, data, generation)
  const advertised =
    dependencies.signupCompletion?.enabled() === true
      ? { ...enriched, signup_completion: { protocol: 'osc1' as const } }
      : enriched
  const fits = (value: unknown) =>
    new TextEncoder().encode(JSON.stringify(value)).byteLength <= MAX_PUBLIC_ONBOARDING_STATE_BYTES
  // Capability cannot erase an existing cleanup scope which still fits alone.
  return mobileSuccess(
    fits(advertised) ? advertised : fits(enriched) ? enriched : data,
    context.requestId,
  )
}

export async function handleOnboardingPost(
  rawContext: MobileRouteContext,
  dependencies: OnboardingRouteDependencies = defaultDependencies,
): Promise<Response> {
  const context: MobileRouteContext = { ...rawContext, auth: structuredClone(rawContext.auth) }
  const transport = classifySignupCompletionTransport(
    await readJsonBody(context.request),
    context.request.headers.get('idempotency-key'),
  )
  const body = transport.body
  const isCompletion = typeof body === 'object' && body !== null && 'document_actions' in body

  if (!isCompletion) {
    // Current native drafts stay on device. This old app path wrote ordinary
    // answers and called the shared profile calculator before consent/n10 and
    // outside structured routine confirmation. Retire only this HTTP entry;
    // the shared legacy tool is not changed or invoked.
    onboardingInputSchema.parse(body)
    throw new MobileApiError(
      409,
      'onboarding_client_update_required',
      'Update the app to complete signup or review your routine',
    )
  }

  const input = onboardingCompletionInputSchema.parse(body)
  // This new representation needs a genuine positive intent/keyed receipt,
  // including the source used by a later no-phase health FULL. An unmarked
  // legacy request must not create a new no-plan account without that anchor.
  if (input.objective === null && transport.mode !== 'versioned') {
    throw new MobileApiError(
      409,
      'onboarding_client_update_required',
      'Update the app to complete signup without an objective',
    )
  }
  // A first completion asking for an objective the rule does not allow is
  // refused here (422, or 500 when the profile or the calc config cannot be
  // read), before anything is read for the grant or recorded. An account that
  // already has a completion time — a re-acceptance of documents, a replay —
  // is not checked and goes on as before. The submission reaches the SQL
  // function whole either way.
  //
  // It runs BEFORE the Idempotency-Key is claimed, on purpose. A claim that is
  // released stays in the ledger as 'failed', with the hash of the refused
  // request, and the ledger compares the hash before it looks at the state
  // (20260720130537_mobile_api_idempotency.sql): the same key sent again with
  // the objective corrected would be answered 409 idempotency_key_conflict,
  // and the published app keeps its key after a refusal. So the header is only
  // read here (without it the answer is still 400, before anything is read),
  // and a refusal leaves no record in the HTTP idempotency ledger. The optional
  // positive intent is verified before preparation, without binding the key/hash.
  const requestKey = requireIdempotencyKey(context.request)
  const sources =
    transport.mode === 'versioned'
      ? captureSignupCompletionSources(dependencies.signupCompletion, context.supabase)
      : undefined
  if (input.body_photo_confirmation && !signupBodyPhotoFinalizationTargetAllowed()) {
    throw signupBodyPhotosUnavailable()
  }
  let identity: SignupStrengthRequestIdentity | undefined
  if (sources && transport.mode === 'versioned') {
    const userId = context.auth.userId
    const requestHash = hashMobileRequest(input)
    const verification = Object.freeze({ userId, intentId: transport.intentId, requestKey })
    const expectedEpoch = snapshotSignupCompletionEpoch(
      await sources.intents.verify(verification),
      verification,
    )
    identity = Object.freeze({ userId, requestKey, requestHash, expectedEpoch })
  }
  sources?.requireEnabled()
  const prepare = async () => {
    const prepared = await prepareSignupPhotoConfirmation(context, input, {
      targetAllowed: signupBodyPhotoFinalizationTargetAllowed(),
      photosEnabled: signupBodyPhotosEnabled(),
      loadSnapshot: async (owner, includeOpenPhotos) => {
        try {
          return await loadSignupPhotoSnapshot(context.supabase, owner, includeOpenPhotos)
        } catch (error) {
          if (
            error instanceof MobileApiError &&
            error.status === 500 &&
            error.code === 'data_access_failed'
          )
            throw new MobileApiError(
              500,
              'data_access_failed',
              'Onboarding completion lookup failed',
            )
          throw error
        }
      },
    })
    const clinical = dependencies.currentClinical
      ? await captureCurrentClinicalState(dependencies.currentClinical, {
          userId: context.auth.userId,
          mode: 'signup',
          body: prepared.effectiveSubmission,
          ...(prepared.snapshot ? { expectedGeneration: prepared.snapshot.generation_token } : {}),
          ...(identity ? { expectedEpoch: identity.expectedEpoch } : {}),
        })
      : undefined
    await assertOnboardingObjectiveEligible(
      context,
      prepared.effectiveSubmission,
      prepared.snapshot?.generation_token,
      clinical,
    )
    return prepared
  }
  const prepared = await prepare()
  sources?.requireEnabled()
  // A refusal above leaves the key unbound, so the corrected payload can reuse it.
  const authority =
    sources && identity
      ? snapshotSignupStrengthRequest(await sources.admission.bind(identity), identity)
      : undefined
  // Bind may have persisted an admission while ON. Never erase it after a flip,
  // but do not begin another HTTP claim once the operation is unavailable.
  sources?.requireEnabled()
  const createResponse = async (current: PreparedSignupPhotoConfirmation) => {
    sources?.requireEnabled()
    const repository = dependencies.createOnboardingRepository(context.supabase, {
      signupPhotoConfirmation: current,
      ...(authority ? { signupStrengthRequest: authority } : {}),
    })
    // Evaluation access is off unless the test environment switched it on
    // (see the module header); off, it reads nothing and the returned function
    // does nothing. It is asked before the completion is recorded because
    // only a first completion is eligible. Neither call can throw.
    const grantEvaluationAccess = await prepareEvaluationAccess(context)
    // No await between this guard and the concrete repository's keyed dispatch.
    sources?.requireEnabled()
    const data = await completeOnboarding(repository, context.auth.userId, input)
    // Success is official now: finish grant/finalization even if the switch flips.
    await grantEvaluationAccess()
    // Completion is already accepted. A photo failure cannot undo it or
    // release its idempotency claim. The default hook has its own budget.
    try {
      await dependencies.finalizeSignupBodyPhotos(context, input, data.completed_at)
    } catch {
      console.warn('[mobile-signup-body-photos] finalization_hook_failed')
    }
    return mobileSuccess(
      await withCleanupScope(context, dependencies, data, data.completed_at),
      context.requestId,
    )
  }
  return dependencies.executeIdempotent(
    context,
    input,
    async (idempotencyKey) => {
      if (authority && idempotencyKey !== authority.requestKey)
        throw new Error('Invalid signup request authority')
      return createResponse(prepared)
    },
    {
      ...(authority
        ? {
            beforeReplay: async () => {
              sources?.requireEnabled()
              await authority.verifyReplay()
              sources?.requireEnabled()
            },
          }
        : {}),
      refreshReplay: async () => {
        sources?.requireEnabled()
        return createResponse(prepared.mode === 'legacy' ? prepared : await prepare())
      },
      responseBodyForStorage: completionBodyForStorage,
    },
  )
}
