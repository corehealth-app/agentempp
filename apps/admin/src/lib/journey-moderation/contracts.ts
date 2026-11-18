import { z } from 'zod'
import {
  socialNickname,
  socialProfileSchema,
  socialUUID,
} from '../mobile-api/journey-social-contracts'

const revision = z.number().int().min(1).max(Number.MAX_SAFE_INTEGER)
const operation = {
  operation_id: socialUUID,
  expected_revision: revision.max(Number.MAX_SAFE_INTEGER - 1),
}
const moderation = z.enum(['active', 'suspended'])
export const moderateProfileCommand = z
  .object({ ...operation, member_id: socialUUID, action: z.enum(['suspend', 'restore']) })
  .strict()
export const resolveReportCommand = z
  .object({ ...operation, report_id: socialUUID, status: z.enum(['resolved', 'dismissed']) })
  .strict()
export const recoverModerationCommand = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('profile'), command: moderateProfileCommand }).strict(),
  z.object({ kind: z.literal('report'), command: resolveReportCommand }).strict(),
])
export const moderationReceipt = z
  .object({
    operation_id: socialUUID,
    member_id: socialUUID,
    revision,
    previous_moderation: moderation,
    moderation,
  })
  .strict()
export const reportReceipt = z
  .object({
    operation_id: socialUUID,
    report_id: socialUUID,
    revision,
    report_status: z.enum(['resolved', 'dismissed']),
  })
  .strict()
export const moderatedProfile = z
  .object({
    status: z.enum(['applied', 'replayed']),
    receipt: moderationReceipt,
    profile: socialProfileSchema,
  })
  .strict()
export const resolvedReport = z
  .object({ status: z.enum(['applied', 'replayed']), receipt: reportReceipt })
  .strict()
const timestamp = z
  .string()
  .datetime({ offset: true })
  .regex(/T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/u)
export const moderationCursor = z.object({ created_at: timestamp, report_id: socialUUID }).strict()
export const moderationQueueCommand = z
  .object({ limit: z.number().int().min(1).max(100), cursor: moderationCursor.nullable() })
  .strict()
export const moderationQueue = z
  .object({
    entries: z
      .array(
        z
          .object({
            report_id: socialUUID,
            reason: z.enum(['nickname', 'harassment', 'spam', 'other']),
            status: z.literal('pending'),
            revision,
            created_at: timestamp,
            member_id: socialUUID,
            nickname: socialNickname.nullable(),
            moderation,
            profile_revision: revision,
          })
          .strict(),
      )
      .max(100),
    next_cursor: moderationCursor.nullable(),
  })
  .strict()
export const recoveredModeration = z
  .object({
    status: z.enum(['applied', 'fenced']),
    kind: z.enum(['profile', 'report']),
    operation_id: socialUUID,
    expected_revision: revision.max(Number.MAX_SAFE_INTEGER - 1),
    receipt: z.union([moderationReceipt, reportReceipt]).nullable(),
  })
  .strict()

export type ModerationQueue = z.infer<typeof moderationQueue>
export type ModerateProfileCommand = z.infer<typeof moderateProfileCommand>
export type ResolveReportCommand = z.infer<typeof resolveReportCommand>
export type RecoverModerationCommand = z.infer<typeof recoverModerationCommand>
