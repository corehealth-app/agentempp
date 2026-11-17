import { conversationIntakeSchema, intakeSnapshot } from './conversation-intake-contracts'
import type {
  ConversationIntakeRPCName,
  ConversationIntakeRPCPort,
} from './conversation-intake-store'
import { MobileApiError } from './http'
export interface VersionedConversationIntakeTransport {
  rpc(
    name: ConversationIntakeRPCName | 'admit_conversation_versioned_media_intake_v2',
    args: Readonly<Record<string, unknown>>,
  ): PromiseLike<unknown>
}
/** Request-bound technical policy only. The SQL dispatcher preserves original
 * admission provenance, including legacy drafts and later asset-ID reuse.
 * The caller's store still observes real Auth/owner/epoch around this ONE RPC.
 * No catalog probe, fallback, retry, public mirror or client policy selector. */
export function createVersionedConversationIntakePort(
  transport: VersionedConversationIntakeTransport,
  policy: { enabled(): boolean; beforeAdmission?(): void },
): ConversationIntakeRPCPort {
  const bound = policy.enabled() === true
  let closed = false
  function available() {
    if (closed || policy.enabled() !== true) {
      closed = true
      throw new MobileApiError(
        503,
        'conversation_intake_unavailable',
        'Conversation intake is unavailable',
      )
    }
  }
  return {
    async rpc(name, args) {
      const input = intakeSnapshot(args)
      const versioned =
        bound &&
        name === 'admit_conversation_intake' &&
        conversationIntakeSchema.parse(input.p_input).source.channel === 'media'
      if (!versioned) return transport.rpc(name, input)
      policy.beforeAdmission?.()
      available()
      const reply = await transport.rpc('admit_conversation_versioned_media_intake_v2', input)
      available()
      return reply
    },
  }
}
