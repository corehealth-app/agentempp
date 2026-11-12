/** Internal lineage references only. Parsing never grants media, domain or
 * writer authority; actual SQL parent/claim/result/selection remain mandatory. */

import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import { conversationPhotoDomainAllowed } from './conversation-photo-observations'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const hash = z.string().regex(/^[0-9a-f]{64}$/u)
const clock = z.string().datetime({ offset: true })
const caption = z
  .string()
  .min(1)
  .max(1000)
  .refine(
    (value) =>
      value.trim().length > 0 &&
      !Array.from(value).some((char) => {
        const code = char.charCodeAt(0)
        return (code < 32 && ![9, 10, 13].includes(code)) || code === 127
      }),
  )
export const conversationIntakeMediaOriginSchema = z
  .object({
    schema: z.literal('conversation.intake-media-origin.v1'),
    intake_id: uuid,
    input_hash: hash,
    source_hash: hash,
    epoch: uuid,
    claim_id: uuid,
    decision_hash: hash,
  })
  .strict()
export type ConversationIntakeMediaOrigin = Readonly<
  z.infer<typeof conversationIntakeMediaOriginSchema>
>
export const conversationIntakeMediaSourceSchema = z
  .object({
    channel: z.literal('media'),
    media_asset_id: uuid,
    user_action: z.literal('report_actual_record'),
    caption: caption.optional(),
  })
  .strict()
export const conversationIntakeMediaProjectionSchema = z
  .object({
    schema: z.literal('conversation.intake-media-projection.v1'),
    origin: conversationIntakeMediaOriginSchema,
    media: z
      .object({
        asset_id: uuid,
        owner_id: uuid,
        kind: z.enum(['meal_photo', 'audio_note', 'gym_photo', 'conversation_photo']),
        processed_at: clock,
        updated_at: clock,
        processing_hash: hash,
      })
      .strict(),
    child_input_hash: hash,
  })
  .strict()
export type ConversationIntakeMediaProjection = Readonly<
  z.infer<typeof conversationIntakeMediaProjectionSchema>
>
function canonical(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`
  return `{${Object.entries(value)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, item]) => `${JSON.stringify(key)}:${canonical(item)}`)
    .join(',')}}`
}
function instant(value: string): bigint {
  clock.parse(value)
  const fraction = /\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/u.exec(value)?.[1] ?? ''
  if (fraction.length > 9) throw new Error('Invalid media clock')
  return (
    BigInt(Math.floor(Date.parse(value) / 1000)) * 1_000_000_000n + BigInt(fraction.padEnd(9, '0'))
  )
}
/** Relation checks on a backend-owned capture, never a source of permission.
 * SQL reconstructs this projection from the immutable parent selection. */
export function assertConversationIntakeMediaCapture(
  command: Readonly<{ ownerId: string; inputHash: string; command: unknown }>,
  context: Readonly<{
    schema: string
    epoch: string
    source_input: unknown
    media: unknown
    intake_projection?: unknown
  }>,
): void {
  const input = z
      .object({
        source: conversationIntakeMediaSourceSchema,
        intake_origin: conversationIntakeMediaOriginSchema,
      })
      .passthrough()
      .parse(command.command),
    projection = conversationIntakeMediaProjectionSchema.parse(context.intake_projection),
    media = z
      .object({
        asset_id: uuid,
        owner_id: uuid,
        kind: z.string(),
        processed_at: clock,
        updated_at: clock,
        context_text: z.string().nullable(),
        processing_result: z.record(z.unknown()),
      })
      .passthrough()
      .parse(context.media)
  const hash = createHash('sha256')
    .update(
      canonical({ context_text: media.context_text, processing_result: media.processing_result }),
    )
    .digest('hex')
  if (
    !['conversation.meal-source.v2', 'conversation.workout-source.v2'].includes(context.schema) ||
    !isDeepStrictEqual(context.source_input, command.command) ||
    !isDeepStrictEqual(input.intake_origin, projection.origin) ||
    projection.origin.epoch !== context.epoch ||
    projection.child_input_hash !== command.inputHash ||
    projection.media.asset_id !== input.source.media_asset_id ||
    projection.media.asset_id !== media.asset_id ||
    projection.media.owner_id !== command.ownerId ||
    media.owner_id !== command.ownerId ||
    projection.media.kind !== media.kind ||
    !conversationPhotoDomainAllowed(
      media.kind,
      media.processing_result,
      context.schema === 'conversation.meal-source.v2' ? 'meal.report' : 'workout.report',
    ) ||
    projection.media.processing_hash !== hash ||
    instant(projection.media.processed_at) !== instant(media.processed_at) ||
    instant(projection.media.updated_at) !== instant(media.updated_at)
  )
    throw new Error('Changed original intake media projection')
}
