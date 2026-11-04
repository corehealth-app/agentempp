/** Dormant service-only SQL adapter. Reads recover sealed facts; no operation
 * admits, calculates, invokes a provider, recaptures clinical state or retries. */
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
} from './conversation-command-candidate-contracts'
import type { BoundConversationMealCommand } from './conversation-command-contracts'
import {
  type ConversationMealEffectReceipt,
  parseConversationMealEffectReceipt,
} from './conversation-meal-feedback-store'
import {
  bindConversationWriterCommand,
  type ConversationMealStoredSource,
  type ConversationResolvedMeal,
  conversationWriterClock,
  conversationWriterHash,
  conversationWriterUnavailable,
  freezeConversationWriter,
  parseConversationMealStoredSource,
  parseConversationResolvedMeal,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'

type Refusal<A extends string> = { readonly action: A }
export type ConversationMealPreparedRead =
  | Refusal<'absent' | 'stale_epoch'>
  | {
      readonly action: 'available'
      readonly binding: ConversationJournalBinding
      readonly source: ConversationMealStoredSource | null
      readonly resolved: {
        readonly resolvedHash: string
        readonly preparedAt: string
        readonly value: ConversationResolvedMeal
      } | null
      readonly receipt: ConversationMealEffectReceipt | null
    }
export type ConversationMealEffectRead =
  | Refusal<'absent' | 'stale_epoch'>
  | { readonly action: 'available'; readonly receipt: ConversationMealEffectReceipt }
export type ConversationMealPrepareOutcome =
  | Refusal<
      | 'absent'
      | 'stale_epoch'
      | 'resolved_conflict'
      | 'source_required'
      | 'source_conflict'
      | 'day_closed'
    >
  | { readonly action: 'prepared' | 'replay'; readonly resolvedHash: string }
export type ConversationMealCommitOutcome =
  | Refusal<
      | 'absent'
      | 'stale_epoch'
      | 'resolved_required'
      | 'resolved_conflict'
      | 'source_conflict'
      | 'day_closed'
    >
  | { readonly action: 'committed' | 'replay'; readonly receipt: ConversationMealEffectReceipt }
export interface ConversationMealWriter {
  readPrepared(command: BoundConversationMealCommand): Promise<ConversationMealPreparedRead>
  readEffect(command: BoundConversationMealCommand): Promise<ConversationMealEffectRead>
  prepare(input: {
    readonly command: BoundConversationMealCommand
    readonly source: ConversationMealStoredSource
    readonly resolved: unknown
  }): Promise<ConversationMealPrepareOutcome>
  commit(input: {
    readonly command: BoundConversationMealCommand
    readonly resolvedHash: string
  }): Promise<ConversationMealCommitOutcome>
}
class WriterFailure extends MobileApiError {
  constructor(code: string, status = 503) {
    super(status, `conversation_meal_writer_${code}`, 'Meal registration state is unavailable')
  }
}
function fail(error: unknown): never {
  if (error instanceof WriterFailure) throw error
  return conversationWriterUnavailable()
}
function data(raw: unknown): unknown {
  const envelope = z.object({ data: z.unknown(), error: z.unknown() }).parse(raw)
  if (envelope.error !== null) {
    const code =
      envelope.error && typeof envelope.error === 'object' && 'code' in envelope.error
        ? envelope.error.code
        : null
    if (code === '55P03') throw new WriterFailure('busy', 409)
    if (code === '40001') throw new WriterFailure('conflict', 409)
    return conversationWriterUnavailable()
  }
  const value = structuredClone(envelope.data)
  if (value && typeof value === 'object' && 'action' in value && value.action === 'event_conflict')
    throw new WriterFailure('event_conflict', 409)
  return value
}
const empty = <const A extends [string, ...string[]]>(values: A) =>
  z.object({ action: z.enum(values) }).strict()
const sourceRecord = z
  .object({
    source_hash: conversationWriterHash,
    captured_at: conversationWriterClock,
    context: z.unknown(),
  })
  .strict()
const resolvedRecord = z
  .object({
    resolved_hash: conversationWriterHash,
    prepared_at: conversationWriterClock,
    resolved: z.unknown(),
  })
  .strict()
const available = z
  .object({
    action: z.literal('available'),
    command: conversationJournalBindingSchema,
    source: sourceRecord.nullable(),
    resolved: resolvedRecord.nullable(),
    receipt: z.unknown().nullable(),
  })
  .strict()

export function createSupabaseConversationMealWriter(db: ServiceClient): ConversationMealWriter {
  // A single bounded SDK bridge until root integrates the generated RPC names.
  type RPC = (
    name:
      | 'read_conversation_meal_prepared'
      | 'read_conversation_meal_effect'
      | 'prepare_conversation_meal'
      | 'commit_conversation_meal',
    args: Record<string, Json>,
  ) => PromiseLike<unknown>
  const rpc = db.rpc.bind(db) as RPC
  const identity = (c: BoundConversationMealCommand) => ({
    p_user_id: c.ownerId,
    p_command_id: c.commandId,
  })
  return Object.freeze({
    async readPrepared(input: BoundConversationMealCommand): Promise<ConversationMealPreparedRead> {
      try {
        const command = bindConversationWriterCommand(input)
        const v = z
          .union([empty(['absent', 'stale_epoch']), available])
          .parse(data(await rpc('read_conversation_meal_prepared', identity(command))))
        if (v.action !== 'available')
          return freezeConversationWriter(v) as Refusal<'absent' | 'stale_epoch'>
        const b = v.command
        conversationWriterClock.parse(b.admitted_at)
        if (
          b.owner_id !== command.ownerId ||
          b.command_id !== command.commandId ||
          b.input_hash !== command.inputHash ||
          (v.resolved !== null && v.source === null) ||
          (v.receipt !== null && (v.source === null || v.resolved === null))
        )
          return conversationWriterUnavailable()
        const source =
          v.source === null
            ? null
            : parseConversationMealStoredSource(
                {
                  sourceHash: v.source.source_hash,
                  capturedAt: v.source.captured_at,
                  epoch: b.epoch,
                  context: v.source.context as ConversationMealStoredSource['context'],
                },
                command,
              )
        const resolved =
          v.resolved === null || source === null
            ? null
            : {
                resolvedHash: v.resolved.resolved_hash,
                preparedAt: v.resolved.prepared_at,
                value: parseConversationResolvedMeal(v.resolved.resolved, { command, source }),
              }
        const receipt =
          v.receipt === null ? null : parseConversationMealEffectReceipt(v.receipt, command)
        if (
          receipt &&
          (receipt.meal_type !== resolved?.value.meal_type ||
            receipt.timezone !== source?.context.owner.timezone ||
            receipt.local_date !== source?.context.day.date)
        )
          return conversationWriterUnavailable()
        return freezeConversationWriter({
          action: 'available',
          binding: b,
          source,
          resolved,
          receipt,
        })
      } catch (error) {
        return fail(error)
      }
    },
    async readEffect(input: BoundConversationMealCommand): Promise<ConversationMealEffectRead> {
      try {
        const command = bindConversationWriterCommand(input),
          v = z
            .union([
              empty(['absent', 'stale_epoch']),
              z.object({ action: z.literal('available'), receipt: z.unknown() }).strict(),
            ])
            .parse(data(await rpc('read_conversation_meal_effect', identity(command))))
        return v.action === 'available'
          ? freezeConversationWriter({
              action: 'available',
              receipt: parseConversationMealEffectReceipt(v.receipt, command),
            })
          : (freezeConversationWriter(v) as Refusal<'absent' | 'stale_epoch'>)
      } catch (error) {
        return fail(error)
      }
    },
    async prepare(input: {
      readonly command: BoundConversationMealCommand
      readonly source: ConversationMealStoredSource
      readonly resolved: unknown
    }): Promise<ConversationMealPrepareOutcome> {
      try {
        const command = bindConversationWriterCommand(input.command),
          s = input.source,
          source = parseConversationMealStoredSource(
            {
              sourceHash: s.sourceHash,
              capturedAt: s.capturedAt,
              epoch: s.epoch,
              context: s.context,
            },
            command,
          ),
          resolved = parseConversationResolvedMeal(input.resolved, { command, source })
        const v = z
          .union([
            empty([
              'absent',
              'stale_epoch',
              'resolved_conflict',
              'source_required',
              'source_conflict',
              'day_closed',
            ]),
            z
              .object({
                action: z.enum(['prepared', 'replay']),
                resolved_hash: conversationWriterHash,
              })
              .strict(),
          ])
          .parse(
            data(
              await rpc('prepare_conversation_meal', {
                ...identity(command),
                p_resolved: resolved as unknown as Json,
              }),
            ),
          )
        return 'resolved_hash' in v
          ? freezeConversationWriter({ action: v.action, resolvedHash: v.resolved_hash })
          : (freezeConversationWriter(v) as ConversationMealPrepareOutcome)
      } catch (error) {
        return fail(error)
      }
    },
    async commit(input: {
      readonly command: BoundConversationMealCommand
      readonly resolvedHash: string
    }): Promise<ConversationMealCommitOutcome> {
      try {
        const command = bindConversationWriterCommand(input.command),
          resolvedHash = z.string().parse(input.resolvedHash)
        // SQL returns its terminal winner before validating hash/fresh context.
        const v = z
          .union([
            empty([
              'absent',
              'stale_epoch',
              'resolved_required',
              'resolved_conflict',
              'source_conflict',
              'day_closed',
            ]),
            z.object({ action: z.enum(['committed', 'replay']), receipt: z.unknown() }).strict(),
          ])
          .parse(
            data(
              await rpc('commit_conversation_meal', {
                ...identity(command),
                p_resolved_hash: resolvedHash,
              }),
            ),
          )
        return 'receipt' in v
          ? freezeConversationWriter({
              action: v.action,
              receipt: parseConversationMealEffectReceipt(v.receipt, command),
            })
          : (freezeConversationWriter(v) as ConversationMealCommitOutcome)
      } catch (error) {
        return fail(error)
      }
    },
  })
}
