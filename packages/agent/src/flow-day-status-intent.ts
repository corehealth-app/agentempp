/** The recognized wording's language is a hint, not a change of account locale. */
export interface FlowDayStatusIntent {
  readonly kind: 'day_status'
  readonly locale: 'pt-BR' | 'en'
}

const PT_DAY_STATUS = new Set([
  'como esta meu dia',
  'como esta meu dia ate agora',
  'como esta o meu dia',
  'como esta meu dia hoje',
  'como esta o meu dia hoje',
  'como ta meu dia',
  'como ta o meu dia',
  'como ta meu dia hoje',
  'como ta o meu dia hoje',
  'status do dia',
  'resumo do dia',
])

const EN_DAY_STATUS = new Set([
  'how is my day',
  'how is my day so far',
  'how is my day today',
  'how is my day going',
  'how is my day going today',
  "how's my day",
  "how's my day going",
  'day status',
  'daily summary',
])

/** Conservative whole-message classification, independent of tools and models. */
export function classifyFlowDayStatusIntent(text: unknown): FlowDayStatusIntent | null {
  if (typeof text !== 'string') return null
  const question = text
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/’/gu, "'")
    .replace(/\s+/gu, ' ')
    .trim()
    .replace(/[.!?]+$/u, '')
    .trim()
  if (PT_DAY_STATUS.has(question)) return { kind: 'day_status', locale: 'pt-BR' }
  if (EN_DAY_STATUS.has(question)) return { kind: 'day_status', locale: 'en' }
  return null
}
