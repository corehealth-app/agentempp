/** Inert adapter for one already-read parent/child continuation snapshot.
 * It does not capture again, authenticate, admit, interpret, calculate or perform domain writes. */
import type { ServiceClient } from '@mpp/db'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  type ConversationMealContinuationReadIdentity,
  parseConversationMealContinuationRead,
} from './conversation-meal-continuation-read-contracts'
import {
  type ConversationMealInterpretation,
  parseConversationMealInterpretation,
} from './conversation-meal-interpretation-contracts'
import {
  type CapturedConversationMealSource,
  type ConversationMealNutritionRpc,
  createConversationMealStoredSourcePorts,
} from './conversation-meal-source'
import { MobileApiError } from './http'

export interface ConversationMealContinuationSources {
  readonly command: BoundConversationMealCommand
  readonly originalSource: CapturedConversationMealSource
  readonly resolutionSource: CapturedConversationMealSource
  readonly interpretation: ConversationMealInterpretation
}
export interface ConversationMealContinuationSourceFactory {
  /** Pure construction from complete private SQL data; no read itself is issued.
   * Historical bundles stay historical and do not grant fresh execution. */
  fromRead(
    identity: ConversationMealContinuationReadIdentity,
    rawRead: unknown,
  ): ConversationMealContinuationSources
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_continuation_source_unavailable',
    'Linked meal sources are unavailable',
  )
}
export function createSupabaseConversationMealContinuationSourceFactory(
  db: ServiceClient,
): ConversationMealContinuationSourceFactory {
  // The generated SDK does not yet name this separately versioned SQL RPC.
  // Pin exactly its real signature; no broad untyped client or live lookup fallback.
  const rpc = db.rpc.bind(db) as ConversationMealNutritionRpc
  return Object.freeze({
    fromRead(
      identity: ConversationMealContinuationReadIdentity,
      rawRead: unknown,
    ): ConversationMealContinuationSources {
      try {
        const read = parseConversationMealContinuationRead(rawRead, identity)
        if (read.action !== 'available' || read.reply === null) unavailable()
        const parent = read.parent,
          child = read.reply
        const command = bindConversationCommand(
          parent.binding.owner_id,
          `cmsg1:${parent.binding.command_id}`,
          parent.source.context.source_input,
        )
        const interpretation = parseConversationMealInterpretation(parent.semantic.result, {
          ownerId: parent.binding.owner_id,
          commandId: parent.binding.command_id,
          inputHash: parent.binding.input_hash,
          sourceHash: parent.source.source_hash,
          attemptId: parent.semantic.attempt_id,
        })
        const originalSource = createConversationMealStoredSourcePorts(
          rpc,
          command,
          {
            action: 'replay',
            source_hash: parent.source.source_hash,
            captured_at: parent.source.captured_at,
            context: parent.source.context,
          },
          { kind: 'original' },
        )
        const resolutionSource = createConversationMealStoredSourcePorts(
          rpc,
          command,
          {
            action: 'replay',
            source_hash: child.source.context.authority.source_hash,
            captured_at: child.source.captured_at,
            context: child.source.context.authority.context,
          },
          { kind: 'continuation', replyId: child.binding.command_id },
        )
        return Object.freeze({ command, originalSource, resolutionSource, interpretation })
      } catch {
        return unavailable()
      }
    },
  })
}
