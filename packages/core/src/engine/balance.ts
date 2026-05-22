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

/**
 * Déficit REAL do dia = quanto ficou abaixo da MANUTENÇÃO (não da meta). É o que
 * realmente emagrece e o que o bloco 7700 credita. = déficit programado − netBalance.
 * Positivo = déficit (abaixo da manutenção); negativo = superávit real.
 *
 * A meta já é (manutenção − déficit programado); por isso o "saldo vs meta"
 * (netBalance) SOZINHO subestima o déficit real pelos N kcal embutidos na meta.
 * Decisão Roberto 2026-05-22: comunicar SEMPRE este número, não o saldo vs meta.
 * Ex: programado 500, netBalance −397 → déficit real 897 (NÃO 397).
 */
export function realDailyDeficit(designDeficit: number, net: number): number {
  return designDeficit - net
}
