/**
 * Agregados de período (semana/mês) — cálculo determinístico sobre snapshots.
 * Substitui a "média de cabeça" que a LLM faria (e poderia inventar). Puro,
 * sem I/O: recebe os snapshots já lidos do banco.
 *
 * Ver docs/CALCULO-MPP.md — comparações semana/mês.
 */
export interface SnapshotForAgg {
  calories_consumed: number | null
  protein_g: number | null
  daily_balance: number | null
  day_status: string | null
}

export interface PeriodSummary {
  /** dias com snapshot na janela */
  days: number
  /** média de calorias consumidas (arredondada) */
  avgConsumed: number
  /** média de proteína (1 casa) */
  avgProtein: number
  /** média do balanço net do dia (consumido−meta−exercício; negativo = déficit) */
  avgNetBalance: number
  /** dias marcados complete */
  completeDays: number
  /** completeDays / days em % (0 se sem dias) */
  adherencePct: number
}

function avg(nums: number[]): number {
  if (nums.length === 0) return 0
  return nums.reduce((a, b) => a + b, 0) / nums.length
}

export function computePeriodSummary(snapshots: SnapshotForAgg[]): PeriodSummary {
  const days = snapshots.length
  if (days === 0) {
    return { days: 0, avgConsumed: 0, avgProtein: 0, avgNetBalance: 0, completeDays: 0, adherencePct: 0 }
  }
  const completeDays = snapshots.filter((s) => s.day_status === 'complete').length
  return {
    days,
    avgConsumed: Math.round(avg(snapshots.map((s) => s.calories_consumed ?? 0))),
    avgProtein: Math.round(avg(snapshots.map((s) => Number(s.protein_g ?? 0))) * 10) / 10,
    avgNetBalance: Math.round(avg(snapshots.map((s) => s.daily_balance ?? 0))),
    completeDays,
    adherencePct: Math.round((completeDays / days) * 100),
  }
}
