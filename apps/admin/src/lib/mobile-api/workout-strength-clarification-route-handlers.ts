import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { createMobileRouteWithContext, type MobileRouteRuntime } from './route'
import { workoutRegistrationEnabled } from './workout-registration-switch'
import {
  workoutStrengthAnswerSchema,
  workoutStrengthUUIDSchema,
} from './workout-strength-clarification-contracts'
import {
  answerWorkoutStrengthClarification,
  loadWorkoutStrengthClarification,
} from './workout-strength-clarification-service'

interface WorkoutRouteContext {
  params: Promise<{ id: string }>
}
function operationKey(request: Request): string {
  const key = request.headers.get('Idempotency-Key')
  if (!key) throw new MobileApiError(400, 'missing_idempotency_key', 'Idempotency-Key is required')
  const parsed = workoutStrengthUUIDSchema.safeParse(key)
  if (!parsed.success)
    throw new MobileApiError(400, 'invalid_idempotency_key', 'Idempotency-Key must be a UUID')
  return `wsa1:${parsed.data}`
}

export function createWorkoutStrengthClarificationRoutes(
  runtime?: MobileRouteRuntime,
  enabled = workoutRegistrationEnabled,
) {
  return {
    GET: createMobileRouteWithContext<WorkoutRouteContext>(async (context, route) => {
      const id = workoutStrengthUUIDSchema.parse((await route.params).id)
      return mobileSuccess(
        await loadWorkoutStrengthClarification(
          context.supabase,
          context.auth.userId,
          id,
          enabled(),
        ),
        context.requestId,
      )
    }, runtime),
    POST: createMobileRouteWithContext<WorkoutRouteContext>(async (context, route) => {
      const id = workoutStrengthUUIDSchema.parse((await route.params).id)
      const key = operationKey(context.request)
      const body = workoutStrengthAnswerSchema.parse(await readJsonBody(context.request, 2048))
      // SQL owns idempotency and CURRENT-authority checks. Never serve a cached
      // HTTP success, prepare a new tuple, retry or follow this write with GET.
      return mobileSuccess(
        await answerWorkoutStrengthClarification(
          context.supabase,
          context.auth.userId,
          id,
          body,
          key,
          enabled(),
        ),
        context.requestId,
      )
    }, runtime),
  }
}
