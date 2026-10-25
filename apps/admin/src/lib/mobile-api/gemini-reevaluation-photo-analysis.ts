import type { GeminiVision } from '@mpp/providers/vision'
import type { PhotoProviderBudget } from './reevaluation-photo-processing'

/** Inject an already configured provider. Do not hint the requested pose. */
export function createReevaluationBodyAnalyzer(vision: Pick<GeminiVision, 'analyzeImage'>) {
  return async (
    bytes: Uint8Array,
    mimeType: string,
    budget: PhotoProviderBudget,
  ): Promise<unknown> =>
    vision.analyzeImage(
      `data:${mimeType};base64,${Buffer.from(bytes).toString('base64')}`,
      { hint: 'body' },
      { signal: budget.signal, timeout: budget.timeoutMs, maxRetries: 0 },
    )
}
