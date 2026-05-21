/**
 * Regra de crédito do bloco 7700 — FONTE ÚNICA.
 * Fiel ao daily-closer.ts + computeProgress (ver docs/CALCULO-MPP.md §3).
 * Validado 2026-05-20: Gleidson (1967) e Raphaela (0) batem exato; crédito do
 * dia 19/05 do Roberto = 832.
 *
 * ⚠️ Esta é a única implementação da regra. daily-closer e bloco-recompute
 * devem chamá-la — NÃO replicar a lógica em outro lugar.
 */
export const KCAL_BLOCK = 7700

export type DayStatus = 'complete' | 'incomplete_no_response' | 'user_skipped'

export interface DayCreditInput {
  hasActivity: boolean
  dayStatus: DayStatus | null
  caloriesConsumed: number
  caloriesTarget: number | null
  dailyBalance: number
  designDeficit: number
}

export function creditDayToBloco(d: DayCreditInput): number {
  if (!d.hasActivity) return 0
  if (d.dayStatus === 'user_skipped') return Math.max(0, d.designDeficit - d.dailyBalance)
  if (
    d.caloriesTarget != null &&
    d.caloriesTarget > 0 &&
    d.caloriesConsumed < 0.5 * d.caloriesTarget
  ) {
    return d.dayStatus === 'complete' || d.dayStatus == null ? d.designDeficit : 0
  }
  if (d.dayStatus === 'incomplete_no_response') return Math.max(0, -d.dailyBalance)
  // Crédito = designDeficit − dailyBalance (= designDeficit + déficit observado).
  // Fiel ao computeProgress: um excedente alimentar pequeno é absorvido pelo
  // designDeficit (ex: dd 500, balance +357 → 143); o max(0) zera só quando o
  // excedente supera o designDeficit. NÃO colocar guard `if (dailyBalance>0) return 0`
  // — isso sub-creditaria dias de excedente leve e divergiria da produção.
  return Math.max(0, d.designDeficit - d.dailyBalance)
}

export function accumulateBloco(credits: number[]): {
  deficitBlock: number
  blocksCompleted: number
} {
  const total = Math.round(credits.reduce((a, b) => a + b, 0))
  return { deficitBlock: total % KCAL_BLOCK, blocksCompleted: Math.floor(total / KCAL_BLOCK) }
}
