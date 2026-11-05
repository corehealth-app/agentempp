/** Executable server composition over the owned SQL core. This leaf installs no
 * route or capability. Shared intake must supply current Auth/admin/patient/
 * epoch observation; a client command is never performed authority. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  type BoundConversationWorkoutCommand,
  parseConversationWorkoutSource,
  pinConversationWorkoutCommand,
  workoutDigest,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import {
  createConversationWorkoutWriter,
  pinConversationWorkoutPreparation,
} from './conversation-workout-writer'

type Name =
  | 'read_conversation_workout_preparation'
  | 'admit_conversation_workout_command'
  | 'capture_conversation_workout_source'
  | 'prepare_conversation_workout'
  | 'read_conversation_workout_effect'
  | 'commit_conversation_workout'
export interface ConversationWorkoutBackendRPC {
  rpc(name: Name, args: Readonly<Record<string, unknown>>): PromiseLike<unknown>
}
export interface ConversationWorkoutBackendScope {
  /** Must freshly check current Auth/admin/owner mapping and clinical epoch. */
  checkCurrentScope(
    identity: Readonly<{ owner_id: string; command_id: string; input_hash: string; epoch: string }>,
  ): Promise<boolean>
}
function data(raw: unknown) {
  const envelope = z
    .object({ data: z.unknown(), error: z.unknown() })
    .passthrough()
    .parse(workoutSnapshot(raw))
  if (envelope.error !== null) throw new Error('Workout backend unavailable')
  return envelope.data
}
export function createConversationWorkoutBackend(
  port: ConversationWorkoutBackendRPC,
  scope: ConversationWorkoutBackendScope,
) {
  const rpc = port.rpc.bind(port),
    check = scope.checkCurrentScope.bind(scope)
  async function report(raw: BoundConversationWorkoutCommand, expectedEpoch: string) {
    const command = pinConversationWorkoutCommand(raw),
      epoch = workoutUUID.parse(expectedEpoch)
    const identity = workoutSnapshot({
      owner_id: command.ownerId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      epoch,
    })
    const args = workoutSnapshot({
      p_user_id: command.ownerId,
      p_command_id: command.commandId,
      p_input_hash: command.inputHash,
      p_expected_epoch: epoch,
    })
    let closed = false
    const unavailable = () =>
      workoutSnapshot({
        status: 'unavailable' as const,
        identity,
        reason: closed ? ('scope_changed' as const) : ('backend_unavailable' as const),
      })
    async function current() {
      if (closed) throw new Error('Closed workout scope')
      try {
        if ((await check(identity)) !== true || closed) throw new Error('Changed workout scope')
      } catch {
        closed = true
        throw new Error('Closed workout scope')
      }
    }
    async function call(name: Name, body: Readonly<Record<string, unknown>>) {
      await current()
      try {
        const value = await rpc(name, body)
        await current()
        return data(value)
      } catch (error) {
        await current()
        throw error
      }
    }
    try {
      const rawStored = await call('read_conversation_workout_preparation', args)
      const stored = z
        .object({
          action: z.string(),
          source: z.unknown().optional(),
          preparation: z.unknown().optional(),
        })
        .strict()
        .parse(rawStored)
      if (!['absent', 'available'].includes(stored.action)) return unavailable()
      let rawSource = stored.source,
        rawPreparation = stored.preparation
      if (!rawSource || !rawPreparation) {
        const admitted = z
          .object({
            action: z.enum(['admitted', 'replay']),
            command: z
              .object({
                owner_id: workoutUUID,
                command_id: workoutUUID,
                input_hash: workoutHash,
                epoch: workoutUUID,
              })
              .passthrough(),
          })
          .strict()
          .parse(
            await call('admit_conversation_workout_command', {
              p_user_id: identity.owner_id,
              p_expected_epoch: epoch,
              p_input: command.command,
            }),
          )
        if (
          !isDeepStrictEqual(
            {
              owner_id: admitted.command.owner_id,
              command_id: admitted.command.command_id,
              input_hash: admitted.command.input_hash,
              epoch: admitted.command.epoch,
            },
            identity,
          )
        )
          throw new Error('Changed admitted workout')
        rawSource = await call('capture_conversation_workout_source', args)
      }
      const source = parseConversationWorkoutSource(command, rawSource)
      if (source.epoch !== epoch) throw new Error('Changed workout epoch')
      if (!rawPreparation)
        rawPreparation = await call('prepare_conversation_workout', {
          ...args,
          p_source_hash: source.sourceHash,
          p_report: resolveConversationWorkoutReport(source),
        })
      const preparation = z
        .object({
          action: z.enum(['prepared', 'replay']).optional(),
          prepared_hash: workoutHash,
          prepared: z.unknown(),
        })
        .strict()
        .parse(rawPreparation)
      const decision = resolveConversationWorkoutReport(source)
      const prepared =
        decision.status === 'ready'
          ? pinConversationWorkoutPreparation(source, preparation.prepared)
          : decision
      if (
        !isDeepStrictEqual(preparation.prepared, prepared) ||
        preparation.prepared_hash !== workoutDigest(prepared)
      )
        throw new Error('Changed workout preparation')
      if (decision.status !== 'ready') return workoutSnapshot(decision)
      // The writer owns each physical effect RPC's before/after guard. Passing
      // the same sticky observer avoids a redundant outer writer observation.
      const writer = createConversationWorkoutWriter(
        { rpc },
        {
          checkCurrentScope: async () => {
            await current()
            return true
          },
        },
      )
      const result = await writer.commit(source, prepared)
      if (closed) return unavailable()
      return result
    } catch {
      return unavailable()
    }
  }
  return Object.freeze({ report })
}
/** No raw table writer and no default scope: the integration must supply the
 * full fresh observation before this service can perform any SDK operation. */
export function createSupabaseConversationWorkoutBackend(
  client: ServiceClient,
  scope: ConversationWorkoutBackendScope,
) {
  const rpc = client.rpc.bind(client) as unknown as ConversationWorkoutBackendRPC['rpc']
  return createConversationWorkoutBackend({ rpc }, scope)
}
