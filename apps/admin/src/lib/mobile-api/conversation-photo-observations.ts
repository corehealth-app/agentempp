/** Extract observations from the classified ordinary-purpose envelope without
 * rewriting its immutable stored bytes or granting consumption/performance. */
import { parseConversationImageResult } from '@mpp/providers/vision/conversation-image-result'
import { z } from 'zod'

export function conversationPhotoDomainAllowed(
  kind: string,
  processed: unknown,
  domain: 'meal.report' | 'workout.report',
): boolean {
  if (kind !== 'conversation_photo')
    return (
      domain === 'meal.report' ? ['meal_photo', 'audio_note'] : ['gym_photo', 'audio_note']
    ).includes(kind)
  try {
    const value = parseConversationImageResult(processed)
    return (
      value.status === 'ready' &&
      (domain === 'meal.report'
        ? value.classification === 'meal' ||
          (value.classification === 'nutrition_label' &&
            value.analysis.type === 'nutrition_label' &&
            typeof value.analysis.product_name === 'string' &&
            value.analysis.product_name.trim().length > 0 &&
            value.analysis.product_name.length <= 240)
        : value.classification === 'equipment')
    )
  } catch {
    return false
  }
}

export function conversationMealMediaAnalysis(media: {
  kind: string
  processing_result: unknown
}): Record<string, unknown> {
  if (media.kind !== 'conversation_photo')
    return z.record(z.unknown()).parse(media.processing_result)
  const value = parseConversationImageResult(media.processing_result)
  if (value.status !== 'ready' || value.classification === 'equipment')
    throw new Error('Ordinary photo is not a meal observation')
  const analysis = value.analysis
  if (analysis.type === 'meal') return { ...analysis }
  if (analysis.type !== 'nutrition_label')
    throw new Error('Ordinary photo is not a meal observation')
  const name = z
    .string()
    .min(1)
    .max(240)
    .refine((v) => v.trim().length > 0)
    .parse(analysis.product_name)
  // A printed serving never supplies the consumed quantity. Zero is the existing
  // missing-portion observation sentinel, not a saved food or nutrition value.
  return {
    type: 'meal',
    items: [{ name, quantity_g_estimate: 0, confidence: analysis.confidence }],
    nutrition_label_visible: true,
    nutrition_label: { ...analysis },
  }
}
