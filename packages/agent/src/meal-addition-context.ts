import { detectAdditionIntent } from './addition-intent-detector.js'

export interface RecentMealForAddition {
  id: string
  food_name: string
  meal_type: string
  consumed_at: string
  raw_provider_message_id?: string | null
}

export interface LinkedAdditionMealType {
  mealType: string
  matchedFoodName: string
  matchedLogId: string
  trigger: string
}

const REFERENCE_STOP_WORDS = new Set([
  'adicionei',
  'adicionado',
  'adicionada',
  'adicionar',
  'acrescentei',
  'acrescentar',
  'com',
  'das',
  'dos',
  'ela',
  'ele',
  'esse',
  'essa',
  'isso',
  'mais',
  'meu',
  'minha',
  'para',
  'que',
  'usei',
])

function normalize(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function meaningfulTokens(value: string): string[] {
  return normalize(value)
    .split(/\s+/)
    .filter((token) => token.length >= 4 && !REFERENCE_STOP_WORDS.has(token))
}

/**
 * Liga um complemento ("adicionei X ao iogurte") ao registro citado. A
 * rotina de horário não deve transformar o complemento em outra refeição.
 */
export function resolveLinkedAdditionMealType(input: {
  currentText?: string | null
  recentLogs: RecentMealForAddition[]
}): LinkedAdditionMealType | null {
  const currentText = input.currentText?.trim() ?? ''
  const trigger = detectAdditionIntent(currentText)
  if (!trigger) return null

  const normalizedText = ` ${normalize(currentText)} `
  const ranked = input.recentLogs
    .map((row) => {
      const tokens = meaningfulTokens(row.food_name)
      const score = tokens.filter((token) => normalizedText.includes(` ${token} `)).length
      return { row, score, timestamp: Date.parse(row.consumed_at) || 0 }
    })
    .filter((candidate) => candidate.score > 0)
    .sort((a, b) => b.score - a.score || b.timestamp - a.timestamp)

  const best = ranked[0]
  if (!best) return null
  const tied = ranked.filter(
    (candidate) =>
      candidate.score === best.score &&
      candidate.timestamp === best.timestamp &&
      candidate.row.id !== best.row.id,
  )
  if (tied.length > 0) return null

  return {
    mealType: best.row.meal_type,
    matchedFoodName: best.row.food_name,
    matchedLogId: best.row.id,
    trigger,
  }
}
