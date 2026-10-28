import type { ServiceClient } from '@mpp/db'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  parseSignupHealthCommand,
  type SignupHealthCommand,
  type SignupHealthRepository,
  signupHealthError,
} from './signup-health-admission'

/** No preflight intent verification: SQL must resolve original receipts first. */
export function createSupabaseSignupHealthAdmissionRepository(
  client: ServiceClient,
): SignupHealthRepository {
  const rpc = client.rpc.bind(client) as unknown as (
    name: string,
    args: Record<string, unknown>,
  ) => PromiseLike<unknown>
  return Object.freeze({
    async admit(userId: string, input: Readonly<SignupHealthCommand>) {
      const owner = uuid.safeParse(userId)
      if (!owner.success) throw signupHealthError('input')
      const command = parseSignupHealthCommand(structuredClone(input))
      for (const action of command.document_actions) Object.freeze(action)
      Object.freeze(command.document_actions)
      Object.freeze(command.risks)
      Object.freeze(command)
      let raw: unknown
      try {
        raw = await rpc('admit_mobile_signup_health', {
          p_user_id: owner.data.toLowerCase(),
          p_command: command,
        })
      } catch {
        throw signupHealthError()
      }
      if (
        !raw ||
        typeof raw !== 'object' ||
        Array.isArray(raw) ||
        !Object.hasOwn(raw, 'data') ||
        !Object.hasOwn(raw, 'error')
      )
        throw signupHealthError()
      const packet = raw as { data: unknown; error: unknown }
      if (packet.error !== null) {
        const code =
          packet.error && typeof packet.error === 'object' && 'code' in packet.error
            ? packet.error.code
            : null
        throw signupHealthError(
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
      // The service strictly binds all receipt/legal/risk/current-state fields
      // and strips private authority before any public response.
      return structuredClone(packet.data)
    },
  })
}
