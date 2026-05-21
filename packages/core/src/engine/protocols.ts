/**
 * Regras determinísticas de GANHO DE MASSA e MANUTENÇÃO (sub-projeto C).
 *
 * Hoje nenhum paciente usa esses protocolos (todos em recomposição), então
 * estas funções ficam "prontas na gaveta" — dormentes até serem ligadas no
 * fluxo de reavaliação quando um paciente entrar em ganho/manutenção.
 *
 * Princípio MPP: o CÓDIGO calcula os NÚMEROS e checa os LIMITES; o JULGAMENTO
 * subjetivo (aderência, fome, energia) fica com a LLM, recebendo estes números.
 *
 * Valores extraídos do método original (Notion "Regras do Agente - 27-12-2025"):
 *   - Velocidade de ganho seguro: +0,25% a +0,5% do peso/semana.
 *   - Teto de gordura no ganho: +3 p.p. de BF (homens) / +4 p.p. (mulheres) → pausar.
 *   - Teto de IMC no ganho: +1,5 → revisão obrigatória da fase.
 *   - Manutenção: −150 kcal/dia por treino de musculação a menos; máx ±300/ciclo;
 *     uma variável por ciclo.
 */

export const GAIN_VELOCITY_MIN_PCT_WEEK = 0.25
export const GAIN_VELOCITY_MAX_PCT_WEEK = 0.5
export const GAIN_BF_CEILING_PP = { masculino: 3, feminino: 4 } as const
export const GAIN_IMC_CEILING = 1.5
export const MAINTENANCE_KCAL_PER_MISSING_TRAINING = 150
export const MAINTENANCE_MAX_ADJUST_PER_CYCLE = 300

// ---------------------------------------------------------------------------
// Ganho de massa — segurança (teto de gordura/IMC no ciclo)
// ---------------------------------------------------------------------------
export interface GainSafetyInput {
  sex: 'masculino' | 'feminino'
  bfStart: number
  bfNow: number
  imcStart: number
  imcNow: number
}
export interface GainSafetyResult {
  bfDelta: number
  imcDelta: number
  bfCeilingExceeded: boolean
  imcCeilingExceeded: boolean
  withinLimits: boolean
  /** ação determinística sugerida (a LLM comunica/confirma) */
  action: 'continuar' | 'pausar_ganho' | 'revisar_fase'
}
export function evaluateGainSafety(i: GainSafetyInput): GainSafetyResult {
  const bfDelta = i.bfNow - i.bfStart
  const imcDelta = i.imcNow - i.imcStart
  const bfCeilingExceeded = bfDelta > GAIN_BF_CEILING_PP[i.sex]
  const imcCeilingExceeded = imcDelta > GAIN_IMC_CEILING
  // IMC estourado = revisão obrigatória da fase (mais grave); senão BF = pausar.
  const action: GainSafetyResult['action'] = imcCeilingExceeded
    ? 'revisar_fase'
    : bfCeilingExceeded
      ? 'pausar_ganho'
      : 'continuar'
  return {
    bfDelta: Math.round(bfDelta * 10) / 10,
    imcDelta: Math.round(imcDelta * 10) / 10,
    bfCeilingExceeded,
    imcCeilingExceeded,
    withinLimits: !bfCeilingExceeded && !imcCeilingExceeded,
    action,
  }
}

// ---------------------------------------------------------------------------
// Ganho de massa — velocidade de ganho de peso
// ---------------------------------------------------------------------------
export interface GainVelocityResult {
  weeklyPctChange: number
  minSafeKgWeek: number
  maxSafeKgWeek: number
  status: 'lento' | 'ideal' | 'rapido'
}
/** Avalia a velocidade de ganho (peso) num intervalo de `days` dias. */
export function evaluateGainVelocity(
  weightStart: number,
  weightNow: number,
  days: number,
): GainVelocityResult {
  const weeks = days / 7
  const weeklyPctChange =
    weightStart > 0 && weeks > 0
      ? ((weightNow - weightStart) / weightStart) * 100 / weeks
      : 0
  const status: GainVelocityResult['status'] =
    weeklyPctChange < GAIN_VELOCITY_MIN_PCT_WEEK
      ? 'lento'
      : weeklyPctChange > GAIN_VELOCITY_MAX_PCT_WEEK
        ? 'rapido'
        : 'ideal'
  return {
    weeklyPctChange: Math.round(weeklyPctChange * 100) / 100,
    minSafeKgWeek: Math.round(weightStart * (GAIN_VELOCITY_MIN_PCT_WEEK / 100) * 1000) / 1000,
    maxSafeKgWeek: Math.round(weightStart * (GAIN_VELOCITY_MAX_PCT_WEEK / 100) * 1000) / 1000,
    status,
  }
}

// ---------------------------------------------------------------------------
// Manutenção — ajuste calórico por treino a menos (reavaliação quinzenal)
// ---------------------------------------------------------------------------
export interface MaintenanceAdjustmentResult {
  /** kcal/dia a somar à meta (negativo = reduzir); já com cap de ±300/ciclo */
  adjustmentKcal: number
  missingTrainings: number
  reason: string
}
export function computeMaintenanceAdjustment(
  trainingFreqPrev: number,
  trainingFreqNow: number,
): MaintenanceAdjustmentResult {
  const missing = Math.max(0, trainingFreqPrev - trainingFreqNow)
  const raw = -MAINTENANCE_KCAL_PER_MISSING_TRAINING * missing
  // `|| 0` normaliza -0 (quando missing=0) para +0.
  const adjustmentKcal = Math.max(-MAINTENANCE_MAX_ADJUST_PER_CYCLE, raw) || 0
  return {
    adjustmentKcal,
    missingTrainings: missing,
    reason:
      missing > 0
        ? `${missing} treino(s) a menos/semana → ${adjustmentKcal} kcal/dia (−150/treino, cap −300/ciclo)`
        : 'frequência de treino mantida → sem ajuste por treino',
  }
}
