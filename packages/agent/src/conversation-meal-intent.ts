/** A conservative intent gate BEFORE extraction. Success permits preparing
 * candidates, never recording them: ownership, quantities, nutrition, epoch,
 * open day and the atomic command writer remain independent authorities.
 * Vision/model output is intentionally not an input to this gate. */
export type ConversationMealIntentInput =
  | { channel: 'text'; text: string }
  | { channel: 'photo'; userAction: 'register_consumed_meal' | 'chat_attachment'; caption?: string }
  | {
      channel: 'audio'
      userAction: 'register_consumed_meal' | 'chat_attachment'
      caption?: string
      /** Read by the backend from an owned, processed audio asset. Never a client transcript. */
      serverProcessedTranscript: string | null
    }

export type ConversationMealIntent =
  | { decision: 'actual_report'; basis: 'first_person_report'; foodText: string }
  | { decision: 'explicit_media_registration'; basis: 'user_registration_action' }
  | {
      decision: 'clarification_required'
      reason: 'invalid_source' | 'consumption_not_established' | 'mixed_statement' | 'missing_audio'
    }
  | {
      decision: 'conversational'
      reason:
        | 'question'
        | 'not_consumed'
        | 'future_or_conditional'
        | 'habit'
        | 'third_party_or_quote'
    }

const actualPrefix =
  /^(?:(?:eu\s+)?(?:comi|bebi|tomei|almocei|jantei|lanchei|ceei)|(?:eu\s+)?acabei\s+de\s+(?:comer|beber|tomar)|i\s+(?:just\s+)?(?:ate|drank)|i\s+have\s+(?:eaten|drunk))\b\s*[:,]?\s*/iu
const hasControls = (text: string) =>
  Array.from(text).some((char) => {
    const code = char.charCodeAt(0)
    return (code < 32 && ![9, 10, 13].includes(code)) || code === 127
  })
function normalized(text: string): string {
  return text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
}
function validText(text: string, limit: number) {
  return text.length <= limit && !hasControls(text)
}
type ConversationalReason = Extract<
  ConversationMealIntent,
  { decision: 'conversational' }
>['reason']
function conflict(text: string): ConversationalReason | null {
  if (
    /[?？]/u.test(text) ||
    /\b(?:posso|poderia|quanto|quantas|quantos|como posso|can i|should i|how much|how many)\b/u.test(
      text,
    )
  )
    return 'question'
  if (/\b(?:nao|nunca|jamais|nem|not|never|didn't|haven't|don't)\b/u.test(text))
    return 'not_consumed'
  if (
    /\b(?:amanha|pretendo|planejo|comeria|beberia|tomaria|vou|irei|quero comer|quero beber|se eu|will|would|going to|if i|plan to|planned to)\b/u.test(
      text,
    )
  )
    return 'future_or_conditional'
  if (
    /\b(?:costumo|costumava|geralmente|normalmente|sempre|todos os dias|todo dia|usually|every day|everyday)\b/u.test(
      text,
    )
  )
    return 'habit'
  if (
    /["“”«»`]/u.test(text) ||
    /^['‘’]/u.test(text.trim()) ||
    /\b(?:disse|disseram|falou|relatou|said|told|wrote|ele|ela|eles|elas|meu filho|minha filha|meu marido|minha esposa|he ate|she ate|they ate)\b/u.test(
      text,
    )
  )
    return 'third_party_or_quote'
  return null
}
function textIntent(text: string): ConversationMealIntent {
  if (!validText(text, 2000))
    return { decision: 'clarification_required', reason: 'invalid_source' }
  const trimmed = text.trim()
  const prefix = trimmed.match(actualPrefix)
  const n = normalized(trimmed)
  const reason = conflict(n)
  // Empty reports and a bare reporting verb are incomplete even with '?'.
  const foodText = prefix ? trimmed.slice(prefix[0].length).trim() : ''
  if (prefix && !foodText.replace(/[?.!,:;\s]/gu, ''))
    return { decision: 'clarification_required', reason: 'consumption_not_established' }
  if (reason)
    return prefix
      ? { decision: 'clarification_required', reason: 'mixed_statement' }
      : { decision: 'conversational', reason }
  if (prefix && /\b(?:talvez|ou|maybe|perhaps|or)\b/u.test(n))
    return { decision: 'clarification_required', reason: 'mixed_statement' }
  // Only one supported consumption predicate. Additional predicates belong to
  // another clause/actor or an unsupported report, not to a nominal food list.
  // Keep them unresolved instead of extracting just the convenient first part.
  if (
    prefix &&
    /\b(?:comi|comeu|comeram|comia|comem|comer|bebi|bebeu|beberam|bebia|bebem|beber|tomei|tomou|tomaram|tomava|tomam|tomar|quero|queria|querem|gostaria|vai|vao|iria|pretendia|planejava|ate|eats|eat|drank|drinks|drink|want|wanted|planned|planning|had|did|didn't|has|have|will|would)\b/u.test(
      normalized(foodText),
    )
  )
    return { decision: 'clarification_required', reason: 'mixed_statement' }
  if (!prefix) return { decision: 'clarification_required', reason: 'consumption_not_established' }
  return { decision: 'actual_report', basis: 'first_person_report', foodText }
}
export function classifyConversationMealIntent(
  input: ConversationMealIntentInput,
): ConversationMealIntent {
  if (input.channel === 'text') return textIntent(input.text)
  if (input.caption !== undefined && !validText(input.caption, 1000))
    return { decision: 'clarification_required', reason: 'invalid_source' }
  const caption = input.caption?.trim() ? textIntent(input.caption) : null
  if (input.channel === 'photo') {
    if (caption && caption.decision !== 'clarification_required') return caption
    if (caption?.reason === 'invalid_source' || caption?.reason === 'mixed_statement')
      return caption
    return input.userAction === 'register_consumed_meal'
      ? { decision: 'explicit_media_registration', basis: 'user_registration_action' }
      : { decision: 'clarification_required', reason: 'consumption_not_established' }
  }
  if (!input.serverProcessedTranscript?.trim())
    return { decision: 'clarification_required', reason: 'missing_audio' }
  const speech = textIntent(input.serverProcessedTranscript)
  // Conflicting caption and speech cannot be selectively ignored to register.
  if (
    caption &&
    (caption.decision === 'conversational' ||
      (caption.decision === 'clarification_required' &&
        caption.reason !== 'consumption_not_established'))
  ) {
    if (speech.decision === 'actual_report')
      return { decision: 'clarification_required', reason: 'mixed_statement' }
    return caption
  }
  if (
    speech.decision !== 'clarification_required' ||
    speech.reason !== 'consumption_not_established'
  )
    return speech
  return input.userAction === 'register_consumed_meal'
    ? { decision: 'explicit_media_registration', basis: 'user_registration_action' }
    : speech
}
