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
  // user_skipped: paciente confirmou pulou uma refeição — dailyBalance reflete o
  // que ELE comeu nas outras (dado real). Pode ser negativo (superávit).
  if (d.dayStatus === 'user_skipped') return d.designDeficit - d.dailyBalance
  if (
    d.caloriesTarget != null &&
    d.caloriesTarget > 0 &&
    d.caloriesConsumed < 0.5 * d.caloriesTarget
  ) {
    // Defesa contra sub-registro (paciente logou < 50% da meta): valor observado
    // é fake (não comeu de verdade tão pouco). Credita só designDeficit ou 0.
    return d.dayStatus === 'complete' || d.dayStatus == null ? d.designDeficit : 0
  }
  // Incomplete_no_response: gap de refeição continuou aberto no fechamento.
  // Decisão Roberto 2026-07-01: crédito 0. Sem isso, qualquer déficit observado
  // vira imprevisível porque não sabemos se a refeição faltante existiu.
  if (d.dayStatus === 'incomplete_no_response') return 0
  // ── MODELO LÍQUIDO (Roberto 2026-05-28) ──────────────────────────────────
  // Crédito = designDeficit − dailyBalance, podendo ser NEGATIVO em dia de
  // superávit. Antes era `Math.max(0, ...)` (cofrinho só subia). Mudança de
  // método autorizada pelo Roberto: "dia ruim TIRA do cofrinho" — mais fiel à
  // fisiologia (pra perder 1kg precisa de déficit LÍQUIDO de 7700, não só somar
  // os dias bons). Exemplo: dd 500, balance +1000 → −500 no cofrinho.
  // O floor passou pro NÍVEL DO TOTAL em accumulateBloco — o cofrinho do paciente
  // nunca fica negativo (cofrinho zerou = recomeça do zero pro próximo bloco).
  return d.designDeficit - d.dailyBalance
}

export function accumulateBloco(credits: number[]): {
  deficitBlock: number
  blocksCompleted: number
} {
  // MODELO LÍQUIDO (Roberto 2026-05-28): credits podem ser negativos (superávit
  // subtrai). Clamp total em 0 — cofrinho do paciente nunca fica negativo,
  // mesmo após uma sequência de dias ruins. Se o paciente acumulou progresso
  // que cruzou bloco(s) (ex: 8000 = 1 bloco completo + 300) e depois teve um
  // dia ruim grande, o total decresce e blocksCompleted/deficitBlock recalculam
  // naturalmente (8000 → 7500 = 0 bloco + 7500 no atual).
  const total = Math.max(0, Math.round(credits.reduce((a, b) => a + b, 0)))
  return { deficitBlock: total % KCAL_BLOCK, blocksCompleted: Math.floor(total / KCAL_BLOCK) }
}
