import { mealDraftInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMealDraft, DEFAULT_MEAL_CONFIDENCE_THRESHOLD } from '@/lib/mobile-api/meal-draft-service'
import { createOpenRouterMealTextExtractor } from '@/lib/mobile-api/meal-text-extractor'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'

export const runtime = 'nodejs'
export const maxDuration = 300

export const POST = createMobileRoute(async (context) => {
  const input = mealDraftInputSchema.parse(await readJsonBody(context.request))
  const apiKey = process.env.OPENROUTER_API_KEY ?? ''
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(
      await createMealDraft(
        {
          media: createSupabaseMediaDependencies(context.supabase).repository,
          extractor: apiKey.trim() ? createOpenRouterMealTextExtractor(apiKey) : null,
          confidenceThreshold: async () => {
            const { data } = await context.supabase
              .from('global_config')
              .select('value')
              .eq('key', 'vision.meal.confidence_threshold')
              .maybeSingle()
            const value = Number((data as { value?: unknown } | null)?.value)
            return Number.isFinite(value) && value > 0 && value <= 1
              ? value
              : DEFAULT_MEAL_CONFIDENCE_THRESHOLD
          },
        },
        context.auth.userId,
        input,
      ),
      context.requestId,
      201,
    ),
  )
})
