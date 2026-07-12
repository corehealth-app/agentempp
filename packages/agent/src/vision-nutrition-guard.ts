interface NutritionLabelRegistrationGuardInput {
  toolName: string
  nutritionLabelDetected: boolean
  trustedLabelCount: number
}

export function shouldBlockUntrustedNutritionLabelRegistration(
  input: NutritionLabelRegistrationGuardInput,
): boolean {
  return (
    input.toolName === 'registra_refeicao' &&
    input.nutritionLabelDetected &&
    input.trustedLabelCount === 0
  )
}
