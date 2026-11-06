/** Private observational history, never admission, retry bodies or answer leases. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  type BoundConversationIntake,
  bindConversationIntake,
  type ConversationIntakeSelection,
  conversationIntakeBindingSchema,
  parseConversationIntakeBinding,
  parseConversationIntakeSelection,
} from './conversation-intake-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  type ConversationMealThreadPage,
  parseConversationMealThreadPage,
} from './conversation-meal-thread-page-store'
import {
  type BoundConversationWorkoutCommand,
  bindConversationWorkoutCommand,
  workoutClock,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import { MobileApiError } from './http'

const uuidPattern = '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}',
  clock = z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/u)
    .pipe(workoutClock),
  eventId = z
    .string()
    .regex(
      new RegExp(
        `^(?:(?:intake|workout|command)/${uuidPattern}|(?:reply|reply-result|fulfillment|edit)/${uuidPattern}/${uuidPattern})$`,
        'u',
      ),
    )
export const conversationJournalV3AnchorSchema = z.object({ at: clock, id: eventId }).strict()
export const conversationJournalV3QuerySchema = z
  .object({
    ownerId: workoutUUID,
    epoch: workoutUUID,
    limit: z.number().int().min(1).max(25),
    cursor: conversationJournalV3AnchorSchema.nullable(),
  })
  .strict()
export type ConversationJournalV3Anchor = Readonly<
  z.infer<typeof conversationJournalV3AnchorSchema>
>
export type ConversationJournalV3Query = Readonly<z.infer<typeof conversationJournalV3QuerySchema>>
const cursorSchema = conversationJournalV3AnchorSchema
  .extend({ v: z.literal(3), owner_id: workoutUUID, epoch: workoutUUID })
  .strict()
const workoutBindingSchema = z
  .object({
    owner_id: workoutUUID,
    command_id: workoutUUID,
    input_hash: workoutHash,
    epoch: workoutUUID,
    admitted_at: clock,
  })
  .strict()
const intakeSchema = z
  .object({
    action: z.literal('available'),
    intake: conversationIntakeBindingSchema,
    source_input: z.unknown(),
    source_hash: workoutHash.nullable(),
    claimed: z.boolean(),
    selection: z.unknown().nullable(),
  })
  .strict()
const workoutSchema = z
  .object({ binding: workoutBindingSchema, source_input: z.unknown() })
  .strict()
const itemSchema = z.discriminatedUnion('kind', [
  z
    .object({ kind: z.literal('intake'), event_id: eventId, at: clock, intake_id: workoutUUID })
    .strict(),
  z
    .object({ kind: z.literal('workout'), event_id: eventId, at: clock, command_id: workoutUUID })
    .strict(),
  z
    .object({
      kind: z.literal('meal'),
      event_id: eventId,
      at: clock,
      intake_id: workoutUUID.nullable(),
    })
    .strict(),
])
export type ConversationJournalV3Item = Readonly<z.infer<typeof itemSchema>>
export interface ConversationJournalV3Intake {
  readonly bound: BoundConversationIntake
  readonly binding: z.infer<typeof conversationIntakeBindingSchema>
  readonly sourceHash: string | null
  readonly claimed: boolean
  readonly selection: ConversationIntakeSelection | null
}
export interface ConversationJournalV3Workout {
  readonly bound: BoundConversationWorkoutCommand
  readonly binding: z.infer<typeof workoutBindingSchema>
}
export interface ConversationJournalV3Page {
  readonly action: 'available'
  readonly schema: 'conversation.journal-page-private.v3'
  readonly ownerId: string
  readonly epoch: string
  readonly observedAt: string
  readonly intakes: readonly ConversationJournalV3Intake[]
  readonly workouts: readonly ConversationJournalV3Workout[]
  readonly mealPage: ConversationMealThreadPage
  readonly items: readonly ConversationJournalV3Item[]
  readonly hasMore: boolean
  readonly nextCursor: ConversationJournalV3Anchor | null
}
export type ConversationJournalV3Outcome =
  | ConversationJournalV3Page
  | Readonly<{ action: 'absent' | 'stale_epoch' | 'cursor_conflict' | 'event_conflict' }>
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_journal_unavailable',
    'Original conversation history is unavailable',
  )
}
function check(value: unknown): asserts value {
  if (!value) unavailable()
}
function invalidCursor(): never {
  throw new MobileApiError(
    422,
    'conversation_journal_invalid_cursor',
    'A canonical history cursor is required',
  )
}
export function encodeConversationJournalV3Cursor(
  owner: string,
  epoch: string,
  anchor: ConversationJournalV3Anchor,
): string {
  const value = cursorSchema.parse({ v: 3, owner_id: owner, epoch, ...anchor })
  return Buffer.from(
    JSON.stringify({
      v: 3,
      owner_id: value.owner_id,
      epoch: value.epoch,
      at: value.at,
      id: value.id,
    }),
    'utf8',
  ).toString('base64url')
}
export function decodeConversationJournalV3Cursor(
  raw: string,
  owner: string,
  epoch: string,
): ConversationJournalV3Anchor {
  let value: z.infer<typeof cursorSchema>
  try {
    if (!/^[A-Za-z0-9_-]{1,1024}$/u.test(raw)) return invalidCursor()
    const bytes = Buffer.from(raw, 'base64url')
    if (bytes.toString('base64url') !== raw) return invalidCursor()
    value = cursorSchema.parse(JSON.parse(bytes.toString('utf8')))
    if (encodeConversationJournalV3Cursor(value.owner_id, value.epoch, value) !== raw)
      return invalidCursor()
  } catch {
    return invalidCursor()
  }
  if (value.owner_id !== owner || value.epoch !== epoch)
    throw new MobileApiError(
      409,
      'conversation_journal_changed',
      'The original history account or epoch has changed',
    )
  return workoutSnapshot({ at: value.at, id: value.id })
}
export function parseConversationJournalV3Page(
  raw: unknown,
  expected: ConversationJournalV3Query,
): ConversationJournalV3Outcome {
  try {
    const query = conversationJournalV3QuerySchema.parse(workoutSnapshot(expected)),
      copy = workoutSnapshot(raw),
      refused = z
        .object({ action: z.enum(['absent', 'stale_epoch', 'cursor_conflict', 'event_conflict']) })
        .strict()
        .safeParse(copy)
    if (refused.success) return workoutSnapshot(refused.data)
    check(Buffer.byteLength(JSON.stringify(copy), 'utf8') <= 2097152)
    const value = z
      .object({
        action: z.literal('available'),
        schema: z.literal('conversation.journal-page-private.v3'),
        owner_id: workoutUUID,
        epoch: workoutUUID,
        observed_at: clock,
        intakes: z.array(intakeSchema).max(25),
        workouts: z.array(workoutSchema).max(25),
        meal_page: z.unknown(),
        items: z.array(itemSchema).max(25),
        has_more: z.boolean(),
        next_cursor: conversationJournalV3AnchorSchema.nullable(),
      })
      .strict()
      .parse(copy)
    check(
      value.owner_id === query.ownerId &&
        value.epoch === query.epoch &&
        value.items.length <= query.limit,
    )
    const at = conversationJournalInstant,
      observed = at(value.observed_at),
      intakes: ConversationJournalV3Intake[] = value.intakes.map((row) => {
        const bound = bindConversationIntake(
            query.ownerId,
            `cintake1:${row.intake.intake_id}`,
            row.source_input,
          ),
          binding = parseConversationIntakeBinding(bound, row.intake),
          selection =
            row.selection === null
              ? null
              : parseConversationIntakeSelection(bound, binding, row.selection)
        check(binding.epoch === query.epoch && at(binding.admitted_at) <= observed)
        check((!row.claimed || row.source_hash !== null) && (!selection || row.claimed))
        if (selection)
          check(selection.source_hash === row.source_hash && at(selection.selected_at) <= observed)
        return { bound, binding, sourceHash: row.source_hash, claimed: row.claimed, selection }
      }),
      workouts: ConversationJournalV3Workout[] = value.workouts.map((row) => {
        const bound = bindConversationWorkoutCommand(
            query.ownerId,
            `cmsg1:${row.binding.command_id}`,
            row.source_input,
          ),
          b = row.binding
        check(
          b.owner_id === query.ownerId &&
            b.input_hash === bound.inputHash &&
            b.epoch === query.epoch &&
            at(b.admitted_at) <= observed,
        )
        return { bound, binding: b }
      }),
      mealPage = parseConversationMealThreadPage(value.meal_page, {
        ownerId: query.ownerId,
        epoch: query.epoch,
        limit: 25,
        cursor: null,
      })
    check(
      mealPage.action === 'available' &&
        !mealPage.has_more &&
        mealPage.next_cursor === null &&
        at(mealPage.observed_at) === observed,
    )
    const intakeMap = new Map(intakes.map((i) => [i.bound.intakeId, i])),
      workoutMap = new Map(workouts.map((w) => [w.bound.commandId, w])),
      meals = new Map(mealPage.items.map((i) => [i.event_id, i])),
      requiredIntakes = new Set<string>(),
      requiredWorkouts = new Set<string>(),
      requiredMeals = new Set<string>(),
      seen = new Set<string>()
    check(intakeMap.size === intakes.length && workoutMap.size === workouts.length)
    function selectedIntake(id: string) {
      const i = intakeMap.get(id)
      check(i)
      requiredIntakes.add(id)
      return i
    }
    let previous = query.cursor
    for (const item of value.items) {
      check(!seen.has(item.event_id) && at(item.at) <= observed)
      seen.add(item.event_id)
      if (previous)
        check(
          at(item.at) < at(previous.at) ||
            (at(item.at) === at(previous.at) && item.event_id < previous.id),
        )
      previous = { at: item.at, id: item.event_id }
      if (item.kind === 'intake') {
        const i = selectedIntake(item.intake_id)
        check(
          item.event_id === `intake/${item.intake_id}` && at(item.at) === at(i.binding.admitted_at),
        )
        const child = i.selection?.command
        if (child?.kind === 'meal.report') {
          const report = meals.get(`command/${child.command_id}`),
            thread = mealPage.threads.find((t) => t.thread_id === child.command_id)
          check(
            report?.kind === 'report' &&
              thread &&
              isDeepStrictEqual(thread.parent_binding, {
                owner_id: child.owner_id,
                command_id: child.command_id,
                input_hash: child.input_hash,
                epoch: child.epoch,
                admitted_at: child.admitted_at,
                command_protocol: 'conversation.command.v1',
                kind: 'meal.report',
              }) &&
              isDeepStrictEqual(thread.original_command, child.input),
          )
          requiredMeals.add(report.event_id)
        } else if (child?.kind === 'workout.report') {
          const w = workoutMap.get(child.command_id)
          check(
            w &&
              isDeepStrictEqual(w.bound.command, child.input) &&
              isDeepStrictEqual(w.binding, {
                owner_id: child.owner_id,
                command_id: child.command_id,
                input_hash: child.input_hash,
                epoch: child.epoch,
                admitted_at: child.admitted_at,
              }),
          )
          requiredWorkouts.add(child.command_id)
        }
      } else if (item.kind === 'workout') {
        const w = workoutMap.get(item.command_id)
        check(
          w &&
            item.event_id === `workout/${item.command_id}` &&
            at(item.at) === at(w.binding.admitted_at),
        )
        check(!intakes.some((i) => i.selection?.command?.command_id === item.command_id))
        requiredWorkouts.add(item.command_id)
      } else {
        const meal = meals.get(item.event_id)
        check(meal && at(meal.at) === at(item.at))
        requiredMeals.add(item.event_id)
        if (item.intake_id !== null) {
          const i = selectedIntake(item.intake_id),
            child = i.selection?.command
          check(
            child?.kind === 'meal.report' &&
              child.command_id === meal.thread_id &&
              meal.kind !== 'report',
          )
        } else check(!intakes.some((i) => i.selection?.command?.command_id === meal.thread_id))
      }
    }
    check(
      requiredIntakes.size === intakes.length &&
        requiredWorkouts.size === workouts.length &&
        requiredMeals.size === mealPage.items.length,
    )
    check([...meals.keys()].every((id) => requiredMeals.has(id)))
    const last = value.items.at(-1)
    check(
      value.has_more
        ? last &&
            value.items.length === query.limit &&
            isDeepStrictEqual(value.next_cursor, { at: last.at, id: last.event_id })
        : value.next_cursor === null,
    )
    return workoutSnapshot({
      action: 'available',
      schema: value.schema,
      ownerId: value.owner_id,
      epoch: value.epoch,
      observedAt: value.observed_at,
      intakes,
      workouts,
      mealPage,
      items: value.items,
      hasMore: value.has_more,
      nextCursor: value.next_cursor,
    })
  } catch {
    return unavailable()
  }
}
