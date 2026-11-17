import { conversationIntakeSchema, intakeSnapshot } from './conversation-intake-contracts'
import type {
  ConversationIntakeRPCName,
  ConversationIntakeRPCPort,
} from './conversation-intake-store'

export interface PrivateConversationIntakeTransport {
  rpc(
    name: ConversationIntakeRPCName | 'admit_conversation_private_media_intake_v2',
    args: Readonly<Record<string, unknown>>,
  ): PromiseLike<unknown>
}

/** Explicit trusted composition option, inactive in the default runtime.
 * The existing store still observes original Auth/owner/epoch before and after
 * every physical call. No fallback, retry, source rewrite or new client. */
export function createPrivateConversationIntakePort(
  transport: PrivateConversationIntakeTransport,
): ConversationIntakeRPCPort {
  return {
    rpc(name, args) {
      const input = intakeSnapshot(args)
      const privateAdmission =
        name === 'admit_conversation_intake' &&
        conversationIntakeSchema.parse(input.p_input).source.channel === 'media'
      return transport.rpc(
        privateAdmission ? 'admit_conversation_private_media_intake_v2' : name,
        input,
      )
    },
  }
}
