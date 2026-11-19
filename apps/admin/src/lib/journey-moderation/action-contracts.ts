import { z } from 'zod'
import { socialProfileSchema, socialUUID } from '../mobile-api/journey-social-contracts'
import {
  moderatedProfile,
  moderateProfileCommand,
  moderationQueue,
  moderationQueueCommand,
  recoveredModeration,
  recoverModerationCommand,
  resolvedReport,
  resolveReportCommand,
} from './contracts'

export const moderationOrigin = z
  .string()
  .url()
  .refine((v) => {
    const u = new URL(v)
    return ['http:', 'https:'].includes(u.protocol) && u.origin === v
  })
const digest = z.string().regex(/^[0-9a-f]{64}$/u)
/** Opaque session/owner references. No Auth UUID or token is sent to the browser. */
export const operatorContext = z
  .object({ origin: moderationOrigin, owner: digest, login: digest })
  .strict()
export type OperatorContext = z.infer<typeof operatorContext>
export const moderationAction = z.discriminatedUnion('type', [
  z
    .object({
      type: z.literal('queue'),
      context: operatorContext.nullable(),
      query: moderationQueueCommand,
    })
    .strict(),
  z
    .object({ type: z.literal('profile'), context: operatorContext, member_id: socialUUID })
    .strict(),
  z
    .object({
      type: z.literal('moderate'),
      context: operatorContext,
      command: moderateProfileCommand,
    })
    .strict(),
  z
    .object({
      type: z.literal('resolveReport'),
      context: operatorContext,
      command: resolveReportCommand,
    })
    .strict(),
  z
    .object({
      type: z.literal('recover'),
      context: operatorContext,
      pending_owner: digest,
      request: recoverModerationCommand,
    })
    .strict(),
])
const envelope = { ok: z.literal(true), context: operatorContext }
export const moderationActionResult = z.union([
  z.object({ ...envelope, type: z.literal('queue'), value: moderationQueue }).strict(),
  z.object({ ...envelope, type: z.literal('profile'), value: socialProfileSchema }).strict(),
  z.object({ ...envelope, type: z.literal('moderate'), value: moderatedProfile }).strict(),
  z.object({ ...envelope, type: z.literal('resolveReport'), value: resolvedReport }).strict(),
  z.object({ ...envelope, type: z.literal('recover'), value: recoveredModeration }).strict(),
  z
    .object({
      ok: z.literal(false),
      code: z.enum(['unavailable', 'unauthorized', 'forbidden', 'changed', 'invalid', 'missing']),
    })
    .strict(),
])
export type ModerationActionResult = z.infer<typeof moderationActionResult>
export type ModerationAction = z.infer<typeof moderationAction>
export type ModerationActionPort = (action: ModerationAction) => Promise<unknown>

export async function deriveOperatorContext(
  identity: { actor: string; login: string },
  origin: string,
  hash: (value: string) => Promise<string>,
): Promise<OperatorContext> {
  moderationOrigin.parse(origin)
  return operatorContext.parse({
    origin,
    owner: await hash(`journey-moderation-owner.v1\0${origin}\0${identity.actor}`),
    login: await hash(
      `journey-moderation-login.v1\0${origin}\0${identity.actor}\0${identity.login}`,
    ),
  })
}
export function sameOperatorContext(a: OperatorContext, b: OperatorContext) {
  return a.origin === b.origin && a.owner === b.owner && a.login === b.login
}
