import type { ServiceClient } from '@mpp/db'
import {
  type LegacyDocumentCommand,
  type LegacyDocumentRepository,
  legacyDocumentError,
  parseLegacyDocumentCommand,
} from './legacy-onboarding-documents'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

/** No clinical preflight: original receipts must survive reset and new publication. */
export function createSupabaseLegacyDocumentRepository(
  client: ServiceClient,
): LegacyDocumentRepository {
  const rpc = client.rpc.bind(client) as unknown as (
    name: string,
    args: Record<string, unknown>,
  ) => PromiseLike<unknown>
  return Object.freeze({
    async accept(owner: string, raw: Readonly<LegacyDocumentCommand>) {
      const userId = uuid.parse(owner).toLowerCase()
      const command = parseLegacyDocumentCommand(raw)
      let response: unknown
      try {
        response = await rpc('accept_mobile_clinical_legacy_documents', {
          p_user_id: userId,
          p_command: command,
        })
      } catch {
        throw legacyDocumentError()
      }
      if (
        !response ||
        typeof response !== 'object' ||
        Array.isArray(response) ||
        !Object.hasOwn(response, 'data') ||
        !Object.hasOwn(response, 'error')
      )
        throw legacyDocumentError()
      const packet = response as { data: unknown; error: unknown }
      if (packet.error !== null) {
        const code =
          packet.error && typeof packet.error === 'object' && 'code' in packet.error
            ? packet.error.code
            : null
        throw legacyDocumentError(
          code === '40001'
            ? 'changed'
            : code === '55P03'
              ? 'busy'
              : code === '23514'
                ? 'documents_changed'
                : code === '22023'
                  ? 'input'
                  : 'unavailable',
        )
      }
      return structuredClone(packet.data)
    },
  })
}
