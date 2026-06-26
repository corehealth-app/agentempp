/**
 * vision-inflight-policy — política de eventos "done" por tipo de mídia.
 *
 * Audit 06-26 review HIGH 3 + MED 1: extraído como predicate puro pra ganhar
 * testes unitários do gate vision-inflight (antes só comportamento implícito
 * em buffer-listener.ts).
 *
 * Nomes reais verificados em prod via product_events:
 *   - vision.analyzed         (sucesso, Vision Sonnet 4.5)
 *   - vision.download_failed  (falha download)
 *   - stt.transcribed         (sucesso STT, 26 ocorrências em prod)
 *   - stt.failed              (falha STT, vide process-message.ts:263)
 */

export type MediaContentType = 'image' | 'audio'

const VISION_DONE_EVENTS = ['vision.analyzed', 'vision.download_failed'] as const
const STT_DONE_EVENTS = ['stt.transcribed', 'stt.failed'] as const

/**
 * Retorna os product_events que sinalizam "processamento concluído" para o
 * tipo de mídia. Lista vazia para tipos não-mídia (defensivo).
 */
export function pickMediaDoneEvents(contentType: string): readonly string[] {
  if (contentType === 'image') return VISION_DONE_EVENTS
  if (contentType === 'audio') return STT_DONE_EVENTS
  return []
}

/**
 * MED 1: quando o buffer tem MAIS DE 1 mídia (caso paciente manda foto +
 * áudio juntos), o gate exige TODOS os tipos com done event. Antes
 * `.limit(1)` pegava só a mais recente e processava só 1 dos 2 eventos.
 *
 * Recebe lista de mídias recentes + sets de eventos done emitidos no
 * intervalo. Retorna `true` se PODE flushar (todas as mídias concluíram).
 */
export type DoneEventsByType = {
  hasVisionDone: boolean
  hasSttDone: boolean
}

export function allMediaDone(
  mediaTypes: readonly MediaContentType[],
  done: DoneEventsByType,
): boolean {
  const needsVision = mediaTypes.includes('image')
  const needsStt = mediaTypes.includes('audio')
  if (needsVision && !done.hasVisionDone) return false
  if (needsStt && !done.hasSttDone) return false
  return true
}
