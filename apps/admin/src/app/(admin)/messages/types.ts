/**
 * Tipos compartilhados entre actions, components e pages do módulo /messages.
 * NÃO é 'use server' — pode exportar types/interfaces livremente.
 */

export type ReviewFlag =
  | 'hallucination'
  | 'great_response'
  | 'needs_review'
  | 'wrong_tool'
  | 'tone_off'
  | 'too_long'
