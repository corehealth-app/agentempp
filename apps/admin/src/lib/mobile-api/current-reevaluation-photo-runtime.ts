import { GeminiVision } from '@mpp/providers/vision'
import type { CurrentClinicalRuntimeTarget } from './current-clinical-runtime-switch'
import { createCurrentVisionConfigLoader } from './current-vision-runtime-config'
import { createReevaluationBodyAnalyzer } from './gemini-reevaluation-photo-analysis'
import { createReevaluationPhotoConsentRoutes } from './reevaluation-photo-consent-http'
import { createSupabaseReevaluationPhotoLifecycleOperations } from './reevaluation-photo-lifecycle'
import { createReevaluationPhotoLifecycleRoutes } from './reevaluation-photo-lifecycle-http'

const loadVisionConfig = createCurrentVisionConfigLoader()
export function createCurrentReevaluationPhotoConsentRuntimeRoutes() {
  return createReevaluationPhotoConsentRoutes({ enabled: true })
}
export function createCurrentReevaluationPhotoRuntimeRoutes(target: CurrentClinicalRuntimeTarget) {
  const storageOrigin = target.storageOrigin
  return createReevaluationPhotoLifecycleRoutes({
    enabled: true,
    createOperations(client) {
      return createSupabaseReevaluationPhotoLifecycleOperations(client, {
        storageOrigin,
        async analyze(bytes, mimeType, budget) {
          // Reached only after the recurring SQL provider authorization. GET,
          // discard and construction never load configuration or create a provider.
          const apiKey = process.env.OPENROUTER_API_KEY
          if (!apiKey) throw new Error('Photo provider unavailable')
          const config = await loadVisionConfig(client, storageOrigin)
          const vision = new GeminiVision({
            apiKey,
            heliconeApiKey: process.env.HELICONE_API_KEY,
            model: config.model,
            nutritionLabelModel: config.nutrition_label_model,
            prompts: config.prompts,
          })
          return createReevaluationBodyAnalyzer(vision)(bytes, mimeType, budget)
        },
      })
    },
  })
}
