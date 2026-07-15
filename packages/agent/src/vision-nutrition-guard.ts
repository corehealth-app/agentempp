interface NutritionLabelRegistrationGuardInput {
  toolName: string
  nutritionLabelDetected: boolean
  detectedLabelCount?: number
  trustedLabelCount: number
  matchedLabelCount?: number
}

export function shouldBlockUntrustedNutritionLabelRegistration(
  input: NutritionLabelRegistrationGuardInput,
): boolean {
  const hasUnresolvedLabel =
    input.detectedLabelCount != null && input.detectedLabelCount > input.trustedLabelCount
  return (
    input.toolName === 'registra_refeicao' &&
    input.nutritionLabelDetected &&
    (input.trustedLabelCount === 0 || hasUnresolvedLabel || input.matchedLabelCount === 0)
  )
}
