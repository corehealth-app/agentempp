import { z } from 'zod'

export const socialUUID = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase())
const revision = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER)
const expectedRevision = revision.max(Number.MAX_SAFE_INTEGER - 1)
export const socialNickname = z.string().refine((value) => {
  const count = [...value].length
  return (
    count >= 2 &&
    count <= 32 &&
    value === value.replace(/^ +| +$/gu, '') &&
    ![...value].some((character) => {
      const point = character.codePointAt(0) ?? 0
      return point < 32 || (point >= 127 && point <= 159) || point === 64
    })
  )
}, 'A public nickname of 2–32 characters is required')
export const socialDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/u)
  .refine((value) => {
    const date = new Date(`${value}T00:00:00Z`)
    return Number.isFinite(date.valueOf()) && date.toISOString().slice(0, 10) === value
  })
export const socialProfileSchema = z
  .object({
    revision,
    opted_in: z.boolean(),
    nickname: socialNickname.nullable(),
    member_id: socialUUID.nullable(),
    moderation: z.enum(['active', 'suspended']),
  })
  .strict()
  .superRefine((value, context) => {
    if (
      (value.revision === 0 &&
        (value.opted_in ||
          value.member_id !== null ||
          value.nickname !== null ||
          value.moderation !== 'active')) ||
      (value.revision > 0 && value.member_id === null) ||
      value.opted_in !== (value.nickname !== null)
    )
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'Inconsistent social participation',
      })
  })
const operation = { operation_id: socialUUID, expected_revision: expectedRevision }
export const socialParticipationCommand = z.union([
  z
    .object({
      ...operation,
      opted_in: z.literal(true),
      nickname: socialNickname,
      consent_version: z.literal('journey-social.v1'),
    })
    .strict(),
  z
    .object({
      ...operation,
      opted_in: z.literal(false),
      nickname: z.null(),
      consent_version: z.null(),
    })
    .strict(),
])
export const socialBlockCommand = z
  .object({
    ...operation,
    expected_revision: expectedRevision.min(1),
    member_id: socialUUID,
    blocked: z.boolean(),
  })
  .strict()
export const socialReportCommand = z
  .object({
    ...operation,
    expected_revision: expectedRevision.min(1),
    member_id: socialUUID,
    reason: z.enum(['nickname', 'harassment', 'spam', 'other']),
  })
  .strict()
export const socialRankingCursor = z
  .object({
    context_hash: z.string().regex(/^[0-9a-f]{64}$/u),
    offset: z.number().int().min(1).max(2147483647),
    viewer_member_id: socialUUID,
    week_start: socialDate,
    through_date: socialDate,
  })
  .strict()
export const socialBlocksCursor = z
  .object({ revision: revision.min(1), after_member_id: socialUUID })
  .strict()
export const socialLimit = z.number().int().min(1).max(100)
export const socialRankingSchema = z
  .object({
    week_start: socialDate,
    week_end: socialDate,
    through_date: socialDate,
    basis: z.literal('closed_daily_xp'),
    entries: z
      .array(
        z
          .object({
            member_id: socialUUID,
            nickname: socialNickname,
            rank: z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),
            weekly_xp: z.number().int().min(Number.MIN_SAFE_INTEGER).max(Number.MAX_SAFE_INTEGER),
            is_you: z.boolean(),
          })
          .strict(),
      )
      .max(100),
    next_cursor: socialRankingCursor.nullable(),
  })
  .strict()
export const socialBlocksSchema = z
  .object({
    revision,
    entries: z
      .array(z.object({ member_id: socialUUID, nickname: socialNickname.nullable() }).strict())
      .max(100),
    next_cursor: socialBlocksCursor.nullable(),
  })
  .strict()
const receipt = { operation_id: socialUUID, revision: revision.min(1) }
export const socialParticipationReceipt = z.object({ ...receipt, opted_in: z.boolean() }).strict()
export const socialBlockReceipt = z
  .object({ ...receipt, member_id: socialUUID, blocked: z.boolean() })
  .strict()
export const socialReportReceipt = z
  .object({ ...receipt, report_id: socialUUID, report_status: z.literal('pending') })
  .strict()
export function socialMutationSchema<T extends z.ZodTypeAny>(receiptSchema: T) {
  return z
    .object({
      status: z.enum(['applied', 'replayed']),
      receipt: receiptSchema,
      profile: socialProfileSchema,
    })
    .strict()
}
