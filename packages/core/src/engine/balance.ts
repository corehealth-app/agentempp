/**
 * Dois balanços distintos (ver docs/CALCULO-MPP.md §2):
 *  - COMIDA: consumido − meta (linha 🎯 Restam/Excedente do card; SEM exercício)
 *  - NET:    consumido − meta − exercício (déficit do dia; alimenta o bloco)
 *
 * Regra MPP (Roberto 2026-05-21): exercício NÃO entra no "Restam" (não libera
 * comer mais); ele acelera o bloco via netBalance.
 */
export function eatingBalance(caloriesConsumed: number, caloriesTarget: number): number {
  return caloriesConsumed - caloriesTarget
}

export function netBalance(
  caloriesConsumed: number,
  caloriesTarget: number,
  exerciseCalories: number,
): number {
  return caloriesConsumed - caloriesTarget - exerciseCalories
}
