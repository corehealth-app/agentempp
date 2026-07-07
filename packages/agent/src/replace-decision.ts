import { detectAdditionIntent } from './addition-intent-detector.js'
import { detectCorrectionIntent } from './correction-detector.js'

export type ReplaceDecisionReason =
  | 'not_requested'
  | 'missing_target'
  | 'blocked_addition_intent'
  | 'explicit_correction'
  | 'objective_overlap'
  | 'corrections_array'
  | 'blocked_weak_evidence'

export interface ReplaceDecision {
  allowReplace: boolean
  reason: ReplaceDecisionReason
  correctionWord: string | null
  additionTrigger: string | null
  overlapRatio: number
}

export interface ReplaceItemLike {
  food_name?: string | null
  name?: string | null
  quantity_g?: number | null
}

function normalizeFoodName(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
}

function itemName(item: ReplaceItemLike): string {
  return String(item.food_name ?? item.name ?? '').trim()
}

export function mealItemOverlapRatio(
  newItems: ReplaceItemLike[],
  previousItems: ReplaceItemLike[],
): number {
  const newNames = newItems.map(itemName).map(normalizeFoodName).filter(Boolean)
  const previousNames = previousItems.map(itemName).map(normalizeFoodName).filter(Boolean)
  if (newNames.length === 0 || previousNames.length === 0) return 0
  const overlap = newNames.filter((next) =>
    previousNames.some((prev) => prev.includes(next) || next.includes(prev)),
  ).length
  return Math.round((overlap / Math.max(newNames.length, previousNames.length)) * 100) / 100
}

export function decideReplaceRequest(input: {
  requestedReplace: boolean
  recentUserMessages: string[]
  overlapRatio?: number | null
  hasObjectiveCorrectionEvidence?: boolean
  hasCorrectionsArray?: boolean
}): ReplaceDecision {
  const overlapRatio = Number(input.overlapRatio ?? 0)
  if (!input.requestedReplace) {
    return {
      allowReplace: false,
      reason: 'not_requested',
      correctionWord: null,
      additionTrigger: null,
      overlapRatio,
    }
  }

  const additionTrigger =
    input.recentUserMessages.map((m) => detectAdditionIntent(m)).find(Boolean) ?? null
  if (additionTrigger) {
    return {
      allowReplace: false,
      reason: 'blocked_addition_intent',
      correctionWord: null,
      additionTrigger,
      overlapRatio,
    }
  }

  const correctionWord = detectCorrectionIntent(input.recentUserMessages) ?? null
  if (input.hasCorrectionsArray) {
    return {
      allowReplace: true,
      reason: 'corrections_array',
      correctionWord,
      additionTrigger: null,
      overlapRatio,
    }
  }
  if (correctionWord) {
    return {
      allowReplace: true,
      reason: 'explicit_correction',
      correctionWord,
      additionTrigger: null,
      overlapRatio,
    }
  }
  if (input.hasObjectiveCorrectionEvidence || overlapRatio >= 0.5) {
    return {
      allowReplace: true,
      reason: 'objective_overlap',
      correctionWord: null,
      additionTrigger: null,
      overlapRatio,
    }
  }
  return {
    allowReplace: false,
    reason: 'blocked_weak_evidence',
    correctionWord: null,
    additionTrigger: null,
    overlapRatio,
  }
}

export function shouldInferReplaceAfterEdit(input: {
  hasPriorMealOfSameType: boolean
  hasPriorEditedPending: boolean
  recentUserMessages?: string[]
  newItems?: ReplaceItemLike[]
  editedPendingItems?: ReplaceItemLike[]
}): ReplaceDecision & { inferReplace: boolean } {
  const overlapRatio = mealItemOverlapRatio(input.newItems ?? [], input.editedPendingItems ?? [])
  if (!input.hasPriorMealOfSameType || !input.hasPriorEditedPending) {
    const decision = decideReplaceRequest({
      requestedReplace: false,
      recentUserMessages: input.recentUserMessages ?? [],
      overlapRatio,
    })
    return { ...decision, inferReplace: false, reason: 'missing_target' }
  }
  const decision = decideReplaceRequest({
    requestedReplace: true,
    recentUserMessages: input.recentUserMessages ?? [],
    overlapRatio,
  })
  return { ...decision, inferReplace: decision.allowReplace }
}
