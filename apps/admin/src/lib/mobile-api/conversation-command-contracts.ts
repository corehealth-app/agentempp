/** Closed public input and stable identity only. No journal, HTTP cache or
 * registration side effect lives here. A future atomic writer must permanently
 * bind (authenticated owner, command ID) and compare this validated input hash. */
import { createHash } from 'node:crypto'
import { z } from 'zod'
import {
  conversationIntakeMediaOriginSchema,
  conversationIntakeMediaSourceSchema,
} from './conversation-intake-media-origin'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const hasControls = (text: string) =>
  Array.from(text).some((char) => {
    const code = char.charCodeAt(0)
    return (code < 32 && ![9, 10, 13].includes(code)) || code === 127
  })
const text = (limit: number) =>
  z
    .string()
    .min(1)
    .max(limit)
    .refine((s) => s.trim().length > 0 && !hasControls(s), 'Invalid command source')

export const conversationMealCommandSchema = z
  .object({
    command_protocol: z.literal('conversation.command.v1'),
    command_id: uuid,
    kind: z.literal('meal.report'),
    meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']).optional(),
    source: z.discriminatedUnion('channel', [
      z.object({ channel: z.literal('text'), text: text(2000) }).strict(),
      z
        .object({
          channel: z.literal('media'),
          media_asset_id: uuid,
          user_action: z.literal('register_consumed_meal'),
          caption: text(1000).optional(),
        })
        .strict(),
    ]),
  })
  .strict()
/** The public route keeps the literal v1 schema above. Only the SQL-projected
 * child may carry the internal versioned origin and original neutral action. */
export const conversationMealExecutionCommandSchema = z.union([
  conversationMealCommandSchema,
  z
    .object({
      command_protocol: z.literal('conversation.command.v1'),
      command_id: uuid,
      kind: z.literal('meal.report'),
      meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']).optional(),
      source: conversationIntakeMediaSourceSchema,
      intake_origin: conversationIntakeMediaOriginSchema,
    })
    .strict(),
])
export type ConversationMealCommand = z.infer<typeof conversationMealExecutionCommandSchema>

function canonical(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  // The closed DTO contains no arrays. Keep ordering explicit if the contract evolves.
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`
  return `{${Object.entries(value)
    .filter(([, item]) => item !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, item]) => `${JSON.stringify(key)}:${canonical(item)}`)
    .join(',')}}`
}
export interface BoundConversationMealCommand {
  readonly ownerId: string
  readonly commandId: string
  readonly inputHash: string
  readonly command: Readonly<ConversationMealCommand>
}
/** ownerId is supplied by authenticated backend context, never request JSON.
 * Exact original text is hashed, without classifier normalization or clock.
 * This function alone provides no replay protection until journal integration. */
export function bindConversationCommand(
  ownerId: string,
  idempotencyKey: string | null,
  raw: unknown,
): BoundConversationMealCommand {
  const owner = uuid.parse(ownerId)
  const command = conversationMealExecutionCommandSchema.parse(raw)
  if (idempotencyKey !== `cmsg1:${command.command_id}`)
    throw new Error('Conversation command identity mismatch')
  Object.freeze(command.source)
  if ('intake_origin' in command) Object.freeze(command.intake_origin)
  Object.freeze(command)
  return Object.freeze({
    ownerId: owner,
    commandId: command.command_id,
    inputHash: createHash('sha256').update(canonical(command)).digest('hex'),
    command,
  })
}
