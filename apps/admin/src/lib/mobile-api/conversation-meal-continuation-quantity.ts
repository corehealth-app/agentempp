/** Explicit quantity conversion only. This result is neither preparation nor
 * registration proof and supplies no semantic, source, Auth or write authority. */
import {
  type ConversationMealReplyBody,
  parseConversationMealQuestion,
  parseConversationMealReplyBody,
  validateConversationMealReplyQuestion,
} from './conversation-meal-continuation-input'
import { freezeConversationWriter } from './conversation-meal-writer-contracts'
import { type MobileQuantityDisplay, mobileQuantityDisplay } from './mobile-quantity-display'

type QuantityUnit = Extract<ConversationMealReplyBody['answer'], { kind: 'quantity' }>['unit']
export interface ConversationMealQuantityAnswerFacts {
  readonly food_index: number
  readonly food_name: string
  readonly amount: number
  readonly unit: QuantityUnit
  readonly quantity_g: number
  readonly quantity_basis: 'stated' | 'portion_reference'
  readonly quantity_display: Readonly<MobileQuantityDisplay> | null
}

export class ConversationMealContinuationQuantityError extends Error {
  readonly code = 'invalid_quantity'
  constructor() {
    super('Meal clarification quantity is unavailable')
    this.name = 'ConversationMealContinuationQuantityError'
  }
}
function unavailable(): never {
  throw new ConversationMealContinuationQuantityError()
}

/** Numeric historical consistency only. No question/key, source, owner, hash,
 * preparation or registration authority is constructed by this conversion. */
export function convertConversationMealQuantity(
  rawName: unknown,
  rawAmount: unknown,
  rawUnit: unknown,
): Readonly<
  Pick<
    ConversationMealQuantityAnswerFacts,
    'amount' | 'unit' | 'quantity_g' | 'quantity_basis' | 'quantity_display'
  >
> {
  if (
    typeof rawName !== 'string' ||
    rawName.length === 0 ||
    rawName.length > 160 ||
    rawName.trim().length === 0 ||
    typeof rawAmount !== 'number' ||
    !Number.isFinite(rawAmount) ||
    rawAmount <= 0 ||
    rawAmount > 9999 ||
    typeof rawUnit !== 'string' ||
    !['g', 'kg', 'mL', 'L', 'unit', 'scoop', 'caneca'].includes(rawUnit)
  )
    unavailable()
  for (let i = 0; i < rawName.length; i++) {
    const code = rawName.charCodeAt(i)
    if ((code < 32 && ![9, 10, 13].includes(code)) || code === 127) unavailable()
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = rawName.charCodeAt(++i)
      if (!(next >= 0xdc00 && next <= 0xdfff)) unavailable()
    } else if (code >= 0xdc00 && code <= 0xdfff) unavailable()
  }
  const name = rawName,
    amount = rawAmount,
    unit = rawUnit as QuantityUnit
  let quantity_g: number
  let quantity_basis: 'stated' | 'portion_reference'
  let quantity_display: MobileQuantityDisplay | null = null
  if (unit === 'g' || unit === 'kg') {
    // Explicit masses do not acquire a reference or six-decimal rounding.
    quantity_g = unit === 'g' ? amount : amount * 1000
    quantity_basis = 'stated'
  } else {
    // Derive approved whole-name metadata, never a client factor or an inferred
    // historical question. The typed-answer entry point validates its question first.
    const reference = mobileQuantityDisplay(name)
    if (!reference) unavailable()
    let factor: number
    if (unit === 'mL' || unit === 'L') {
      if (reference.unit !== 'mL') unavailable()
      factor = unit === 'L' ? 1000 * reference.grams_per_unit : reference.grams_per_unit
    } else if (unit === 'caneca') {
      if (reference.unit !== 'mL' || reference.reference_id !== 'fao-infoods-v2-whole-milk-tb')
        unavailable()
      factor = 200 * reference.grams_per_unit
    } else {
      if (unit !== reference.unit) unavailable()
      factor = reference.grams_per_unit
    }
    // Match the existing approved reference conversion's operation order.
    quantity_g = Math.round(amount * factor * 1e6) / 1e6
    quantity_basis = 'portion_reference'
    quantity_display = reference
  }
  if (!Number.isFinite(quantity_g) || quantity_g <= 0 || quantity_g > 9999) unavailable()
  return freezeConversationWriter({
    amount,
    unit,
    quantity_g,
    quantity_basis,
    quantity_display,
  })
}

export function resolveConversationMealQuantityAnswer(
  rawInput: unknown,
  rawQuestion: unknown,
): ConversationMealQuantityAnswerFacts {
  // Capture detached closed copies once; never revisit caller-owned raw data.
  const input = parseConversationMealReplyBody(rawInput)
  const question = parseConversationMealQuestion(rawQuestion)
  validateConversationMealReplyQuestion(input, question)
  if (input.answer.kind !== 'quantity' || question.kind !== 'quantity') unavailable()
  return freezeConversationWriter({
    food_index: input.answer.food_index,
    food_name: question.food_name,
    ...convertConversationMealQuantity(question.food_name, input.answer.amount, input.answer.unit),
  })
}
