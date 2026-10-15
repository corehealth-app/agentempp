import { registrationProposalInputSchema, resourceIdSchema } from './contracts'
import { mobileSuccess, readJsonBody, readOptionalJsonBody } from './http'
import { executeSupabaseIdempotent, requireIdempotencyKey } from './idempotency'
import {
  cancelRegistration,
  confirmRegistration,
  editRegistration,
  proposeRegistration,
} from './registration-service'
import type { MobileRouteContext } from './route'
import {
  workoutRegistrationCreateSchema,
  workoutRegistrationEditSchema,
  workoutRegistrationSelectionSchema,
} from './workout-registration-contracts'
import {
  admitWorkoutProposal,
  cancelVersionedWorkoutRegistration,
  confirmVersionedWorkoutRegistration,
  editVersionedWorkoutRegistration,
  loadVersionedWorkoutRegistration,
  requireWorkoutRequestKey,
} from './workout-registration-service'

export interface RegistrationRouteDependencies {
  proposeRegistration: typeof proposeRegistration
  editRegistration: typeof editRegistration
  confirmRegistration: typeof confirmRegistration
  cancelRegistration: typeof cancelRegistration
  admitWorkoutProposal: typeof admitWorkoutProposal
  editVersionedWorkoutRegistration: typeof editVersionedWorkoutRegistration
  confirmVersionedWorkoutRegistration: typeof confirmVersionedWorkoutRegistration
  cancelVersionedWorkoutRegistration: typeof cancelVersionedWorkoutRegistration
  loadVersionedWorkoutRegistration: typeof loadVersionedWorkoutRegistration
  executeIdempotent: typeof executeSupabaseIdempotent
}
const defaults: RegistrationRouteDependencies = {
  proposeRegistration,
  editRegistration,
  confirmRegistration,
  cancelRegistration,
  admitWorkoutProposal,
  editVersionedWorkoutRegistration,
  confirmVersionedWorkoutRegistration,
  cancelVersionedWorkoutRegistration,
  loadVersionedWorkoutRegistration,
  executeIdempotent: executeSupabaseIdempotent,
}

function hasProtocol(body: unknown): boolean {
  return body !== null && typeof body === 'object' && Object.hasOwn(body, 'workout_protocol')
}

export async function handleRegistrationPropose(
  context: MobileRouteContext,
  deps: RegistrationRouteDependencies = defaults,
): Promise<Response> {
  const body = await readJsonBody(context.request)
  if (hasProtocol(body)) {
    const validated = workoutRegistrationCreateSchema.parse(body)
    const { workout_protocol: _protocol, ...input } = validated
    const key = requireWorkoutRequestKey(requireIdempotencyKey(context.request))
    // Durable admission precedes the claim/cache, including cached HTTP replay.
    const intent = await deps.admitWorkoutProposal(context.supabase, context.auth, input, key)
    const execute = async () => mobileSuccess(await intent.execute(), context.requestId, 201)
    return deps.executeIdempotent(context, validated, execute, { refreshReplay: execute })
  }
  const input = registrationProposalInputSchema.parse(body)
  requireIdempotencyKey(context.request)
  return deps.executeIdempotent(context, input, async (key) =>
    mobileSuccess(
      await deps.proposeRegistration(context.supabase, context.auth, input, key),
      context.requestId,
      201,
    ),
  )
}

export async function handleRegistrationPatch(
  context: MobileRouteContext,
  rawID: string,
  deps: RegistrationRouteDependencies = defaults,
): Promise<Response> {
  const id = resourceIdSchema.parse(rawID)
  const body = await readJsonBody(context.request)
  if (hasProtocol(body)) {
    const validated = workoutRegistrationEditSchema.parse(body)
    const { workout_protocol: _protocol, expected_revision: expected, ...input } = validated
    const key = requireWorkoutRequestKey(requireIdempotencyKey(context.request))
    const execute = async (attemptKey: string) =>
      mobileSuccess(
        await deps.editVersionedWorkoutRegistration(
          context.supabase,
          context.auth,
          id,
          input,
          attemptKey,
          expected,
        ),
        context.requestId,
      )
    return deps.executeIdempotent(context, { registration_id: id, input: validated }, execute, {
      refreshReplay: () => execute(key),
    })
  }
  const input = registrationProposalInputSchema.parse(body)
  requireIdempotencyKey(context.request)
  return deps.executeIdempotent(context, { registration_id: id, input }, async (key) =>
    mobileSuccess(
      await deps.editRegistration(context.supabase, context.auth, id, input, key),
      context.requestId,
    ),
  )
}

export async function handleRegistrationConfirm(
  context: MobileRouteContext,
  rawID: string,
  deps: RegistrationRouteDependencies = defaults,
): Promise<Response> {
  const id = resourceIdSchema.parse(rawID)
  const body = await readOptionalJsonBody(context.request)
  const key = requireIdempotencyKey(context.request)
  if (body !== undefined) {
    const selection = workoutRegistrationSelectionSchema.parse(body)
    requireWorkoutRequestKey(key)
    const execute = async () =>
      mobileSuccess(
        await deps.confirmVersionedWorkoutRegistration(
          context.supabase,
          context.auth,
          id,
          selection.expected_revision,
        ),
        context.requestId,
      )
    return deps.executeIdempotent(context, { registration_id: id, ...selection }, execute, {
      refreshReplay: execute,
    })
  }
  return deps.executeIdempotent(context, { registration_id: id }, async () =>
    mobileSuccess(
      await deps.confirmRegistration(context.supabase, context.auth, id),
      context.requestId,
    ),
  )
}

export async function handleRegistrationDelete(
  context: MobileRouteContext,
  rawID: string,
  deps: RegistrationRouteDependencies = defaults,
): Promise<Response> {
  const id = resourceIdSchema.parse(rawID)
  const body = await readOptionalJsonBody(context.request)
  const key = requireIdempotencyKey(context.request)
  if (body !== undefined) {
    const selection = workoutRegistrationSelectionSchema.parse(body)
    requireWorkoutRequestKey(key)
    const execute = async () =>
      mobileSuccess(
        await deps.cancelVersionedWorkoutRegistration(
          context.supabase,
          context.auth,
          id,
          selection.expected_revision,
        ),
        context.requestId,
      )
    return deps.executeIdempotent(context, { registration_id: id, ...selection }, execute, {
      refreshReplay: execute,
    })
  }
  return deps.executeIdempotent(context, { registration_id: id }, async () =>
    mobileSuccess(
      await deps.cancelRegistration(context.supabase, context.auth.userId, id),
      context.requestId,
    ),
  )
}

export async function handleRegistrationGet(
  context: MobileRouteContext,
  rawID: string,
  deps: RegistrationRouteDependencies = defaults,
): Promise<Response> {
  const id = resourceIdSchema.parse(rawID)
  return mobileSuccess(
    await deps.loadVersionedWorkoutRegistration(context.supabase, context.auth.userId, id),
    context.requestId,
  )
}
