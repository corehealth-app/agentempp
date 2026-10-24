import { mutateConfirmedMeal } from './confirmed-meal-mutation-service'
import { loadConfirmedMealRecord } from './confirmed-meal-read'
import {
  confirmedMealDeleteInputSchema,
  confirmedMealPatchInputSchema,
  resourceIdSchema,
} from './contracts'
import { mobileSuccess, readJsonBody } from './http'
import { includesRegistrationFeedback } from './registration-feedback-history'
import { createMobileRouteWithContext, type MobileRouteRuntime } from './route'

interface MealRecordRouteContext {
  params: Promise<{ id: string }>
}

async function recordId(route: MealRecordRouteContext): Promise<string> {
  return resourceIdSchema.parse((await route.params).id).toLowerCase()
}

export function createConfirmedMealRoutes(runtime?: MobileRouteRuntime, now = () => new Date()) {
  return {
    GET: createMobileRouteWithContext<MealRecordRouteContext>(
      async (context, route) =>
        mobileSuccess(
          await loadConfirmedMealRecord(
            context.supabase,
            context.auth,
            await recordId(route),
            now(),
            includesRegistrationFeedback(context.request),
          ),
          context.requestId,
        ),
      runtime,
    ),
    PATCH: createMobileRouteWithContext<MealRecordRouteContext>(async (context, route) => {
      const id = await recordId(route)
      const body = confirmedMealPatchInputSchema.parse(await readJsonBody(context.request))
      return mutateConfirmedMeal(context, id, { method: 'PATCH', body }, now())
    }, runtime),
    DELETE: createMobileRouteWithContext<MealRecordRouteContext>(async (context, route) => {
      const id = await recordId(route)
      const body = confirmedMealDeleteInputSchema.parse(await readJsonBody(context.request))
      return mutateConfirmedMeal(context, id, { method: 'DELETE', body }, now())
    }, runtime),
  }
}
