export const MAX_PHYSICAL_KCAL_PER_GRAM = 9.5
export const KCAL_ROUNDING_TOLERANCE = 5

/**
 * Gordura pura fornece cerca de 9 kcal/g. O pequeno excedente e a tolerância
 * absoluta acomodam arredondamento de rótulos sem aceitar totais de refeição
 * atribuídos por engano a uma porção pequena.
 */
export function hasImpossibleKcalDensity(kcal: number, quantityG: number): boolean {
  if (!Number.isFinite(kcal) || !Number.isFinite(quantityG) || kcal < 0 || quantityG <= 0) {
    return true
  }
  return kcal > quantityG * MAX_PHYSICAL_KCAL_PER_GRAM + KCAL_ROUNDING_TOLERANCE
}
