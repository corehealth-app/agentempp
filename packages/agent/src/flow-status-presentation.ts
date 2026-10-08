/**
 * Flow presentation only (decisions-v1 item5): completed block progress is
 * shown for recomposition; the pending 14-day budget/DAM is not published.
 * Stored/calculated values and the shared renderer's defaults stay intact.
 */
import { type BalanceCardData, renderBalanceCard } from './balance-card.js'
import { composeStatusMessage, type StatusProgress } from './post-registration-message.js'

function flowCardData(card: BalanceCardData): BalanceCardData {
  return { ...card, last14d: null }
}

/** Also used when rebuilding this deterministic status's canonical card. */
export function renderFlowStatusCard(card: BalanceCardData): string {
  return renderBalanceCard(flowCardData(card))
}

export function composeFlowStatusMessage(card: BalanceCardData, progress: StatusProgress): string {
  return composeStatusMessage(flowCardData(card), progress, {
    includeBlockProgress: card.protocol === 'recomposicao',
  })
}

/** Add only after canonical reconstruction; it must never duplicate a card. */
export function flowStatusExplanation(protocol: string | null | undefined): string {
  return protocol === 'ganho_massa' || protocol === 'manutencao'
    ? 'O Bloco 7.700 é exibido apenas na recomposição corporal.'
    : ''
}
