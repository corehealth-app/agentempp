import type { TrustedVisionNutritionLabel } from '@mpp/agent'

interface NutritionValues {
  kcal: number | null
  protein_g: number | null
  carbs_g: number | null
  fat_g: number | null
}

interface NutritionLabelInput {
  productName: string | null
  confidence: number
  servingSizeG: number | null
  perServing: NutritionValues
  per100g: NutritionValues
}

type ResolutionReason = 'low_confidence' | 'per_100g' | 'derived_from_serving' | 'incomplete_macros'

function isComplete(values: NutritionValues): values is TrustedVisionNutritionLabel['per100g'] {
  return Object.values(values).every(
    (value) => typeof value === 'number' && Number.isFinite(value) && value >= 0,
  )
}

function scalePer100(value: number, servingSizeG: number): number {
  return Math.round((value / servingSizeG) * 100 * 100) / 100
}

export function resolveTrustedNutritionLabel(
  input: NutritionLabelInput,
  confidenceThreshold: number,
): { trusted: TrustedVisionNutritionLabel | null; reason: ResolutionReason } {
  if (input.confidence < confidenceThreshold) {
    return { trusted: null, reason: 'low_confidence' }
  }
  if (
    input.servingSizeG != null &&
    Number.isFinite(input.servingSizeG) &&
    input.servingSizeG > 0 &&
    isComplete(input.perServing)
  ) {
    return {
      trusted: {
        productName: input.productName,
        servingSizeG: input.servingSizeG,
        per100g: {
          kcal: scalePer100(input.perServing.kcal, input.servingSizeG),
          protein_g: scalePer100(input.perServing.protein_g, input.servingSizeG),
          carbs_g: scalePer100(input.perServing.carbs_g, input.servingSizeG),
          fat_g: scalePer100(input.perServing.fat_g, input.servingSizeG),
        },
      },
      reason: 'derived_from_serving',
    }
  }
  if (isComplete(input.per100g)) {
    return {
      trusted: {
        productName: input.productName,
        servingSizeG: input.servingSizeG,
        per100g: input.per100g,
      },
      reason: 'per_100g',
    }
  }
  return { trusted: null, reason: 'incomplete_macros' }
}
