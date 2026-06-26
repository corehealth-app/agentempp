/**
 * State machine — transições legítimas do MealState (audit 06-26 Layer 2.2).
 *
 * Lookup table read-only. Quem chama assertValidTransition() pode escolher
 * logar warn (S2) ou throw (Fase 3 futura). Hoje não bloqueia nada — só
 * fornece linguagem comum pra detectar drift estrutural (ex: CANCELLED→
 * CONFIRMED foi o bug do pizza-race; CONFIRMED→PROPOSED é rollback de erro).
 */
import type { MealState } from './types.js'

export type TransitionResult =
  | { ok: true }
  | { ok: false; reason: string; severity: 'warn' | 'error' }

/**
 * Adjacência canônica das transições. Casos não listados são "inválidos
 * detectáveis" — telemetria, NÃO bloqueio.
 *
 * Notas:
 *  - [init]→PROPOSED: criação via pipeline.ts non-express
 *  - PROPOSED→CONFIRMED: tap [Sim] no botão (interactive-handler)
 *  - PROPOSED→EDITED: tap [Editar] no botão
 *  - PROPOSED→CANCELLED: cancel cego do pipeline (com Layer 1 + Layer 3
 *    de defesa)
 *  - PROPOSED→EXPIRED: cron pending-cleanup após 24h
 *  - CONFIRMED→CORRECTED: registra_refeicao(replace=true) após confirm
 *  - CONFIRMED→RECLASSIFIED: reclassifica_refeicao após confirm
 *  - CONFIRMED→PROPOSED: rollback de erro no handler do tap (raro)
 *  - REGISTERED→CORRECTED: express + replace=true
 *  - REGISTERED→RECLASSIFIED: express + reclassify
 *  - CANCELLED→PROPOSED: Layer 3 recovery (audit 06-26) reabre cancelled
 *
 * Inválidas (geram warn):
 *  - CONFIRMED→PROPOSED genuíno (sem evidência de erro): drift
 *  - CANCELLED→CONFIRMED direto: o que motivou Layer 3 (precisa passar
 *    por PROPOSED via recovery)
 *  - EXPIRED→qualquer: estado terminal
 *  - SKIPPED→qualquer: estado terminal
 */
const TRANSITIONS: Record<MealState, MealState[]> = {
  PROPOSED: ['CONFIRMED', 'EDITED', 'CANCELLED', 'EXPIRED'],
  CONFIRMED: ['CORRECTED', 'RECLASSIFIED', 'PROPOSED'], // PROPOSED só via rollback
  REGISTERED: ['CORRECTED', 'RECLASSIFIED'],
  CORRECTED: ['CORRECTED', 'RECLASSIFIED'], // pode haver N replace
  RECLASSIFIED: ['CORRECTED', 'RECLASSIFIED'], // pode mudar meal_type novamente
  CANCELLED: ['PROPOSED'], // só via Layer 3 recovery
  EDITED: [], // terminal — próximo turno cria PROPOSED novo (não é transição da MESMA refeição)
  EXPIRED: [], // terminal
  SKIPPED: [], // terminal
}

/**
 * Valida se a transição `prev → next` é legítima.
 * Retorna { ok: true } se sim; { ok: false, reason, severity } se inválida.
 *
 * Severity:
 *  - 'warn': drift detectável mas não-bloqueante (caller decide se loga ou
 *    ignora). Default pra inválidas.
 *  - 'error': transição que NÃO pode acontecer em nenhuma circunstância
 *    legítima (ex: SKIPPED→CONFIRMED). Caller pode escolher throw.
 */
export function assertValidTransition(
  prev: MealState,
  next: MealState,
): TransitionResult {
  const allowed = TRANSITIONS[prev] ?? []
  if (allowed.includes(next)) {
    return { ok: true }
  }
  const isTerminalSource =
    prev === 'EXPIRED' || prev === 'SKIPPED' || prev === 'EDITED'
  const severity: 'warn' | 'error' = isTerminalSource ? 'error' : 'warn'
  return {
    ok: false,
    reason: `Transição inválida: ${prev} → ${next}`,
    severity,
  }
}

/**
 * Lista todas as transições válidas (debug + dashboards).
 */
export function listValidTransitions(): Array<{ from: MealState; to: MealState }> {
  const out: Array<{ from: MealState; to: MealState }> = []
  for (const [from, tos] of Object.entries(TRANSITIONS) as Array<[MealState, MealState[]]>) {
    for (const to of tos) out.push({ from, to })
  }
  return out
}

/**
 * Estados terminais — não têm transição saindo (próximo turno cria refeição
 * NOVA, não é continuação da mesma).
 */
export const TERMINAL_STATES: ReadonlyArray<MealState> = ['EDITED', 'EXPIRED', 'SKIPPED']

export function isTerminal(state: MealState): boolean {
  return TERMINAL_STATES.includes(state)
}
