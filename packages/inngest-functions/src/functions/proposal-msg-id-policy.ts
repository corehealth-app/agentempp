/**
 * proposal-msg-id-policy — política de set/preserve do proposal_msg_id em
 * pending_registrations.
 *
 * Audit 06-26 review HIGH 2: extraído como predicate puro pra ganhar teste
 * unitário (Opção B em process-message.ts:730 não era testável diretamente).
 *
 * Regra: o primeiro envio interactive da pending SETA proposal_msg_id.
 * Re-envios (cron suppression-reentry / retry / fallback) NÃO sobrescrevem —
 * paciente preserva o msg_id ORIGINAL p/ replies/quote-by-id e telemetria
 * separa os 2 eventos (interactive_set vs interactive_resent).
 *
 * NOTA: o tap não consulta proposal_msg_id pra identificar a pending — usa
 * pendingId codificado no buttonId via BUTTON_ID_PATTERN. Preserve é defesa
 * pra auditoria / replies do paciente que respondem o card original.
 */
export type ProposalMsgIdEvent = 'pending.interactive_set' | 'pending.interactive_resent'

export type ProposalMsgIdPolicyInput = {
  /** Resultado do UPDATE com .is('proposal_msg_id', null) — true se 1 row foi setada (slot estava vazio). */
  rowWasSet: boolean
  /** ID novo que foi tentado set. */
  newProviderMessageId: string
}

export type ProposalMsgIdPolicyOutput = {
  event: ProposalMsgIdEvent
  /** Propriedades do product_event a emitir. */
  properties: {
    providerMessageId: string
    /** Mesma chave `wasSet` exposta no evento pra inspeção rápida. */
    wasSet: boolean
  }
}

/**
 * Classifica um envio interactive de pending como "set" (1º) ou "resent"
 * (re-envio que foi suprimido). Pure — sem I/O.
 */
export function classifyProposalMsgIdWrite(
  input: ProposalMsgIdPolicyInput,
): ProposalMsgIdPolicyOutput {
  return {
    event: input.rowWasSet ? 'pending.interactive_set' : 'pending.interactive_resent',
    properties: {
      providerMessageId: input.newProviderMessageId,
      wasSet: input.rowWasSet,
    },
  }
}
