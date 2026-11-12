import type { MealType } from './personal-meal-windows.js'

export interface MealTypeDecisionInput {
  claimed: MealType | 'outro'
  expected: MealType
  currentUserText?: string | null
  activeReminderMealTypes?: MealType[]
  trustMealType?: boolean
  replace?: boolean
}

export interface MealTypeDecision {
  mealType: MealType | 'outro'
  autoCorrected: boolean
  reason:
    | 'trusted_pending'
    | 'explicit_current_text'
    | 'active_gap_reminder'
    | 'replace_target'
    | 'already_expected'
    | 'expected_by_routine'
}

// JavaScript \b treats accented endings as non-word characters. Require the
// actual end of a Unicode word, including marks, numbers and underscores.
const EXPLICIT_PATTERNS: Array<{ mealType: MealType; regex: RegExp }> = [
  { mealType: 'cafe', regex: /\b(?:caf[eé]\s+da\s+manh[ãa]|breakfast)(?![\p{L}\p{M}\p{N}_])/giu },
  // A malformed longer breakfast name must not fall back to its short 'café' prefix.
  {
    mealType: 'cafe',
    regex: /\b(?:meu|no|do|era\s+o|foi\s+o)\s+caf[eé](?![\p{L}\p{M}\p{N}_])(?!\s+da\s+manh)/giu,
  },
  { mealType: 'almoco', regex: /\b(?:almo[çc]o|lunch)(?![\p{L}\p{M}\p{N}_])/giu },
  { mealType: 'lanche', regex: /\b(?:lanche|snack|merenda)(?![\p{L}\p{M}\p{N}_])/giu },
  { mealType: 'jantar', regex: /\b(?:jantar|janta|dinner)(?![\p{L}\p{M}\p{N}_])/giu },
  { mealType: 'ceia', regex: /\b(?:ceia|supper)(?![\p{L}\p{M}\p{N}_])/giu },
]

function isNegated(text: string, index: number): boolean {
  const before = text.slice(Math.max(0, index - 24), index)
  return /(?:n[ãa]o|not)\s+(?:foi|era|[ée]|was|is)?\s*$/iu.test(before)
}

/** Retorna a ultima mencao positiva e explicita de tipo no turno atual. */
export function detectExplicitMealType(text: string | null | undefined): MealType | null {
  if (!text?.trim()) return null
  const matches: Array<{ mealType: MealType; index: number }> = []
  for (const { mealType, regex } of EXPLICIT_PATTERNS) {
    regex.lastIndex = 0
    for (const match of text.matchAll(regex)) {
      const index = match.index ?? 0
      if (!isNegated(text, index)) matches.push({ mealType, index })
    }
  }
  matches.sort((a, b) => a.index - b.index)
  return matches.at(-1)?.mealType ?? null
}

/**
 * Precedencia: pending confirmado > texto atual > lembrete ativo > rotina.
 * `replace` fica conservador porque trocar o tipo mudaria o alvo da delecao.
 */
export function decideMealType(input: MealTypeDecisionInput): MealTypeDecision {
  if (input.trustMealType) {
    return { mealType: input.claimed, autoCorrected: false, reason: 'trusted_pending' }
  }

  const explicit = detectExplicitMealType(input.currentUserText)
  if (explicit) {
    return {
      mealType: explicit,
      autoCorrected: explicit !== input.claimed,
      reason: 'explicit_current_text',
    }
  }

  if (input.activeReminderMealTypes?.includes(input.claimed as MealType)) {
    return { mealType: input.claimed, autoCorrected: false, reason: 'active_gap_reminder' }
  }

  if (input.replace) {
    return { mealType: input.claimed, autoCorrected: false, reason: 'replace_target' }
  }

  if (input.claimed === input.expected) {
    return { mealType: input.claimed, autoCorrected: false, reason: 'already_expected' }
  }

  return { mealType: input.expected, autoCorrected: true, reason: 'expected_by_routine' }
}
