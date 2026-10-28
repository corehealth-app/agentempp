import type { MobileAuthContext } from '../auth'
import health from './health-hold-fixture.json'
import { consentAuth, uid } from './reevaluation-photo-consent-fixture'
export const signupHealthIDs = {
  owner: health.initial.user_id,
  operation: uid(5810),
  intent: uid(5811),
  epoch: uid(5812),
  receipt: uid(5813),
  requirement: uid(5814),
}
export function signupHealthAuth(): MobileAuthContext {
  const auth = structuredClone(consentAuth)
  auth.userId = signupHealthIDs.owner
  auth.patient.id = signupHealthIDs.owner
  return auth
}
export function signupHealthCommand() {
  return {
    version: 1,
    operation_key: signupHealthIDs.operation,
    intent_id: signupHealthIDs.intent,
    request_key: `osc1:${signupHealthIDs.intent}`,
    locale: 'pt-BR',
    document_actions: [
      {
        document_key: 'evaluation_4_sensitive_data_consent',
        version: 'synthetic-1',
        locale: 'pt-BR',
        content_hash: 'a'.repeat(64),
        action: 'consent',
      },
    ],
    risks: [...health.initial.receipt.items],
  }
}
export function signupHealthInput() {
  const { operation_key: _, ...body } = signupHealthCommand()
  return body
}
export function signupHealthWire() {
  const command = signupHealthCommand()
  return {
    version: 1,
    user_id: signupHealthIDs.owner,
    operation_key: command.operation_key,
    receipt: {
      id: signupHealthIDs.receipt,
      intent_id: command.intent_id,
      request_key: command.request_key,
      epoch: signupHealthIDs.epoch,
      locale: command.locale,
      requirement_set_id: signupHealthIDs.requirement,
      document_actions: command.document_actions,
      risks: command.risks,
      health_operation_key: health.initial.receipt.operation_key,
      admitted_at: health.initial.receipt.declared_at,
    },
    declaration: structuredClone(health.initial),
  }
}
