/**
 * Deriva o MealState canônico a partir de dados existentes (sem efeito
 * colateral). Função pura — testável com fixtures dos 13 bugs históricos.
 */
import type { MealState, MealStateInput, MealStateResult } from './types.js'

const SKIP_SENTINEL_PREFIX = 'pulou_'

/**
 * Computa o estado canônico de UMA refeição/proposta. Convenção: input
 * carrega o snapshot do pending + meal_logs relacionados (mesma data+
 * meal_type+user). Se há ambíguo (pending + meal_logs sem relação direta),
 * o caller deve fatiar antes de chamar.
 */
export function deriveMealState(input: MealStateInput): MealStateResult {
  const { pending, mealLogs, hasReplaceAfter, hasReclassifyAfter } = input

  const anySkip = mealLogs.some(
    (m) => m.kcal === 0 && m.food_name.toLowerCase().startsWith(SKIP_SENTINEL_PREFIX),
  )
  if (anySkip) {
    return {
      state: 'SKIPPED',
      provenance: 'skip',
      lastTransitionAt: latestMealLogTime(mealLogs),
    }
  }

  // Sem pending → caminho express OU reclassify-only OU log órfão.
  if (!pending) {
    if (mealLogs.length === 0) {
      // Sem nada — não computável. Reportamos como REGISTERED no caso degenerado
      // (caller deve filtrar antes); aqui é só guard de defesa.
      return {
        state: 'REGISTERED',
        provenance: 'express',
        lastTransitionAt: new Date(0).toISOString(),
      }
    }
    if (hasReclassifyAfter) {
      return {
        state: 'RECLASSIFIED',
        provenance: 'reclassified',
        lastTransitionAt: latestMealLogTime(mealLogs),
      }
    }
    if (hasReplaceAfter) {
      return {
        state: 'CORRECTED',
        provenance: 'replaced',
        lastTransitionAt: latestMealLogTime(mealLogs),
      }
    }
    return {
      state: 'REGISTERED',
      provenance: 'express',
      lastTransitionAt: latestMealLogTime(mealLogs),
    }
  }

  // Com pending — estado segue o pending.status, exceto quando confirmed.
  switch (pending.status) {
    case 'pending':
      return {
        state: 'PROPOSED',
        provenance: 'pending_only',
        lastTransitionAt: pending.created_at,
      }
    case 'cancelled':
      return {
        state: 'CANCELLED',
        provenance: 'pending_only',
        lastTransitionAt: pending.resolved_at ?? pending.created_at,
      }
    case 'edited':
      return {
        state: 'EDITED',
        provenance: 'pending_only',
        lastTransitionAt: pending.resolved_at ?? pending.created_at,
      }
    case 'expired':
      return {
        state: 'EXPIRED',
        provenance: 'pending_only',
        lastTransitionAt: pending.resolved_at ?? pending.created_at,
      }
    case 'confirmed': {
      if (mealLogs.length === 0) {
        // Bug latente: pending=confirmed sem meal_log (handler falhou).
        // Reportamos como PROPOSED — Caller pode detectar drift comparando
        // pending.resolved_at vs latest meal_log.
        return {
          state: 'PROPOSED',
          provenance: 'pending_only',
          lastTransitionAt: pending.resolved_at ?? pending.created_at,
        }
      }
      if (hasReclassifyAfter) {
        return {
          state: 'RECLASSIFIED',
          provenance: 'reclassified',
          lastTransitionAt: latestMealLogTime(mealLogs),
        }
      }
      if (hasReplaceAfter) {
        return {
          state: 'CORRECTED',
          provenance: 'replaced',
          lastTransitionAt: latestMealLogTime(mealLogs),
        }
      }
      return {
        state: 'CONFIRMED',
        provenance: 'pending+logs',
        lastTransitionAt: pending.resolved_at ?? latestMealLogTime(mealLogs),
      }
    }
  }
}

function latestMealLogTime(logs: MealStateInput['mealLogs']): string {
  if (logs.length === 0) return new Date(0).toISOString()
  return logs.reduce((latest, m) => (m.created_at > latest ? m.created_at : latest), logs[0]!.created_at)
}

/**
 * Helper de classificação direta sem input objeto — útil pra views SQL e
 * dashboards. Reflete a mesma régua de derive() mas só com primitivos.
 */
export function classifyByPendingStatus(
  pendingStatus: 'pending' | 'confirmed' | 'edited' | 'expired' | 'cancelled' | null,
  hasMealLogs: boolean,
  hasSkipSentinel: boolean,
): MealState {
  if (hasSkipSentinel) return 'SKIPPED'
  if (pendingStatus == null) return hasMealLogs ? 'REGISTERED' : 'PROPOSED'
  switch (pendingStatus) {
    case 'pending':
      return 'PROPOSED'
    case 'cancelled':
      return 'CANCELLED'
    case 'edited':
      return 'EDITED'
    case 'expired':
      return 'EXPIRED'
    case 'confirmed':
      return hasMealLogs ? 'CONFIRMED' : 'PROPOSED'
  }
}
