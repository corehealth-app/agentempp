/**
 * MealState — enum canônico do ciclo de vida de uma refeição (audit 06-26
 * Layer 2.2 prevention plan). Hoje meal_logs + pending_registrations +
 * product_events tinham estados implícitos espalhados; este módulo deriva
 * o estado canônico SEM mexer no caminho de escrita (read-only).
 *
 * Mapeamento atual (Opção 3 do plan: wrapper lógico, ZERO migration destrutiva):
 *  - PROPOSED:    pending_registrations.status='pending'
 *  - CONFIRMED:   pending.status='confirmed' + N meal_logs gravados
 *  - REGISTERED:  meal_logs sem pending (express path)
 *  - CORRECTED:   meal_logs + houve replace=true posterior
 *  - RECLASSIFIED: meal_logs UPDATE puro de meal_type (reclassifica_refeicao)
 *  - CANCELLED:   pending.status='cancelled' (sem meal_log do mesmo pmid)
 *  - EDITED:      pending.status='edited' (paciente pediu correção)
 *  - EXPIRED:     pending.status='expired' (cron pending-cleanup)
 *  - SKIPPED:     marca_refeicao_pulada (meal_logs com kcal=0)
 */
export type MealState =
  | 'PROPOSED'
  | 'CONFIRMED'
  | 'REGISTERED'
  | 'CORRECTED'
  | 'RECLASSIFIED'
  | 'CANCELLED'
  | 'EDITED'
  | 'EXPIRED'
  | 'SKIPPED'

export type StateProvenance =
  | 'pending+logs'  // CONFIRMED via tap (tem pending + meal_logs)
  | 'pending_only'  // PROPOSED/CANCELLED/EDITED/EXPIRED — sem meal_log gravado
  | 'express'       // REGISTERED via express path — sem pending
  | 'skip'          // SKIPPED via marca_refeicao_pulada
  | 'replaced'      // CORRECTED via replace=true
  | 'reclassified'  // RECLASSIFIED via reclassifica_refeicao

export interface MealStateInput {
  pending?: {
    status: 'pending' | 'confirmed' | 'edited' | 'expired' | 'cancelled'
    resolved_at: string | null
    created_at: string
  } | null
  mealLogs: Array<{
    id: string
    kcal: number
    food_name: string
    created_at: string
    raw_provider_message_id?: string | null
  }>
  /** Eventos de replace/reclassify que aconteceram após o último meal_log. */
  hasReplaceAfter?: boolean
  hasReclassifyAfter?: boolean
}

export interface MealStateResult {
  state: MealState
  provenance: StateProvenance
  lastTransitionAt: string
}
