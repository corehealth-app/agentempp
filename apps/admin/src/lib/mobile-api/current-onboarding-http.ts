import type { ServiceClient } from '@mpp/db'
import {
  handleOnboardingGet,
  handleOnboardingPost,
  type OnboardingRouteDependencies,
  readOnboardingGetQuery,
} from '@/app/api/mobile/v1/onboarding/handler'
import { readClinicalRepresentation } from './clinical-representation'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
  requireCurrentClinicalRepresentation,
} from './current-clinical-read-model'
import {
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  currentClinicalError,
  projectCurrentClinicalState,
  readCurrentClinicalState,
} from './current-clinical-state'
import { presentCurrentOnboardingCompletion } from './current-onboarding-presentation'
import { createCurrentSignupEligibilityRoute } from './current-signup-eligibility-http'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { MAX_PUBLIC_ONBOARDING_STATE_BYTES } from './onboarding-service'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteContext, type MobileRouteRuntime } from './route'
import type { SignupCompletionComposition } from './signup-completion-composition'
import { classifySignupCompletionTransport } from './signup-completion-transport'
import { createSignupHealthAdmissionRoutes } from './signup-health-admission-http'

type Dependencies = OnboardingRouteDependencies & {
  currentClinical: CurrentClinicalStateSource
  signupCompletion: SignupCompletionComposition
}

/** One opt-in signup boundary: GET/current presentation, original completion,
 * eligibility V2 and explicit health. Nothing is mounted or default-enabled. */
export function createCurrentOnboardingRoutes(
  options: {
    readonly enabled: boolean
    createDependencies(client: ServiceClient): Dependencies
  },
  runtime?: MobileRouteRuntime,
) {
  const enabled = options.enabled === true
  const createDependencies = options.createDependencies.bind(options)
  const fixed =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  function scope(raw: MobileRouteContext) {
    if (!enabled)
      throw new MobileApiError(404, 'current_onboarding_disabled', 'Current signup unavailable')
    const context = { ...raw, auth: structuredClone(raw.auth) }
    const owner = authenticatedReevaluationOwner(context.auth)
    const representation = readClinicalRepresentation(context.request.url)
    const supplied = createDependencies(context.supabase)
    const source = supplied.currentClinical
    const capture = source.capture.bind(source)
    const currentClinical = Object.freeze({ capture })
    const dependencies = Object.freeze({
      clinicalAdmission: supplied.clinicalAdmission
        ? Object.freeze({
            establish: supplied.clinicalAdmission.establish.bind(supplied.clinicalAdmission),
          })
        : undefined,
      createOnboardingRepository: supplied.createOnboardingRepository.bind(supplied),
      executeIdempotent: supplied.executeIdempotent.bind(supplied),
      saveLegacyOnboarding: supplied.saveLegacyOnboarding.bind(supplied),
      finalizeSignupBodyPhotos: supplied.finalizeSignupBodyPhotos.bind(supplied),
      ...(supplied.readSignupBodyPhotoCleanupScope
        ? {
            readSignupBodyPhotoCleanupScope:
              supplied.readSignupBodyPhotoCleanupScope.bind(supplied),
          }
        : {}),
      currentClinical,
      signupCompletion: Object.freeze({
        enabled: supplied.signupCompletion.enabled.bind(supplied.signupCompletion),
        createSources: supplied.signupCompletion.createSources.bind(supplied.signupCompletion),
      }),
    })
    if (dependencies.signupCompletion.enabled() !== true) throw currentClinicalError('unavailable')
    return { context, owner, representation, dependencies, source: currentClinical }
  }
  async function packet(response: Response) {
    const raw: unknown = await response.json()
    if (
      !raw ||
      typeof raw !== 'object' ||
      !('data' in raw) ||
      !raw.data ||
      typeof raw.data !== 'object' ||
      Array.isArray(raw.data)
    )
      throw currentClinicalError('invalid_response')
    return structuredClone(raw.data) as Record<string, unknown>
  }
  const GET = createMobileRoute(async (raw) => {
    const s = scope(raw)
    readOnboardingGetQuery(s.context.request.url)
    const initial = await captureCurrentClinicalState(s.source, {
      userId: s.owner,
      mode: 'profile',
    })
    requireCurrentClinicalRepresentation(
      projectCurrentClinicalState(initial),
      s.representation.compatible,
    )
    const before = s.dependencies.clinicalAdmission
      ? readCurrentClinicalState(
          await s.dependencies.clinicalAdmission.establish(initial, s.source),
          s.owner,
        )
      : initial
    requireCurrentClinicalRepresentation(
      projectCurrentClinicalState(before),
      s.representation.compatible,
    )
    const legacy = before.generation_authority?.kind === 'legacy_transition'
    const response = await handleOnboardingGet(
      s.context,
      legacy
        ? {
            ...s.dependencies,
            createOnboardingRepository: (client, options) =>
              s.dependencies.createOnboardingRepository(client, {
                ...options,
                legacyClinicalState: before,
              }),
          }
        : s.dependencies,
    )
    if (!response.ok) return response
    const data = await packet(response)
    const after = await captureCurrentClinicalState(s.source, { userId: s.owner, mode: 'profile' })
    if (
      after.observed_at < before.observed_at ||
      currentClinicalReadBinding(before) !== currentClinicalReadBinding(after)
    )
      throw currentClinicalError('changed')
    if (s.dependencies.signupCompletion.enabled() !== true)
      throw currentClinicalError('unavailable')
    requireCurrentClinicalRepresentation(
      projectCurrentClinicalState(after),
      s.representation.compatible,
    )
    if (!s.representation.compatible) return mobileSuccess(data, s.context.requestId)
    const result = {
      ...data,
      signup_completion: { protocol: 'osc1' as const },
      clinical_signup: { representation: 'current_clinical_v2' as const },
      clinical_policy: projectCurrentClinicalPublicPolicy(after),
    }
    // Required representation fields cannot be dropped to fit an old budget.
    if (
      new TextEncoder().encode(JSON.stringify(result)).byteLength >
      MAX_PUBLIC_ONBOARDING_STATE_BYTES
    )
      throw currentClinicalError('unavailable')
    return mobileSuccess(result, s.context.requestId)
  }, fixed)
  const POST = createMobileRoute(async (raw) => {
    const s = scope(raw)
    const before = await captureCurrentClinicalState(s.source, { userId: s.owner, mode: 'profile' })
    requireCurrentClinicalRepresentation(
      projectCurrentClinicalState(before),
      s.representation.compatible,
    )
    if (
      before.generation_authority?.kind === 'legacy_transition' &&
      before.generation_token?.onboarding_completed_at === null
    )
      throw new MobileApiError(
        409,
        'onboarding_reconsent_required',
        'Review the required notices without repeating signup',
      )
    if (s.representation.compatible) {
      const transport = classifySignupCompletionTransport(
        await readJsonBody(s.context.request.clone()),
        s.context.request.headers.get('idempotency-key'),
      )
      if (transport.mode !== 'versioned')
        throw new MobileApiError(
          409,
          'onboarding_client_update_required',
          'Versioned signup intent required',
        )
    }
    const response = await handleOnboardingPost(s.context, s.dependencies)
    if (!response.ok) return response
    // This runs OUTSIDE the receipt/HTTP claim. A failed fresh read cannot
    // erase an accepted completion or cache current health in historical ACKs.
    const data = await packet(response)
    const current = await captureCurrentClinicalState(s.source, {
      userId: s.owner,
      mode: 'profile',
    })
    requireCurrentClinicalRepresentation(
      projectCurrentClinicalState(current),
      s.representation.compatible,
    )
    const result = presentCurrentOnboardingCompletion(data, current)
    if (!s.representation.compatible) {
      const { clinical_policy: _policy, ...legacy } = result
      return mobileSuccess(legacy, s.context.requestId)
    }
    return mobileSuccess(result, s.context.requestId)
  }, fixed)
  return Object.freeze({
    GET,
    POST,
    ELIGIBILITY: createCurrentSignupEligibilityRoute({ enabled }, fixed),
    HEALTH: createSignupHealthAdmissionRoutes({ enabled }, fixed).POST,
  })
}
