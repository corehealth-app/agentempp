import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import { MobileApiError } from './http'
import {
  socialBlockCommand,
  socialBlockReceipt,
  socialBlocksCursor,
  socialBlocksSchema,
  socialLimit,
  socialMutationSchema,
  socialParticipationCommand,
  socialParticipationReceipt,
  socialProfileSchema,
  socialRankingCursor,
  socialRankingSchema,
  socialReportCommand,
  socialReportReceipt,
  socialUUID,
} from './journey-social-contracts'

export interface JourneySocialRPCPort {
  rpc(
    name: 'journey_social_patient_authenticated',
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'journey_social_unavailable',
    'Social progress is unavailable. Reconcile the same operation before retrying.',
  )
}
function detached<T>(value: T): T {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) detached(child)
    Object.freeze(value)
  }
  return value
}
function output<T>(schema: z.ZodType<T>, raw: unknown): T {
  try {
    return detached(schema.parse(raw))
  } catch {
    return unavailable()
  }
}
/** Auth must already be verified. The only physical port is the live-session
 * SQL gateway; every call gets fresh pre/post admission and no automatic retry. */
export function createJourneySocialService(
  port: JourneySocialRPCPort,
  identity: { owner: string; auth: string; login: string },
  authorize: () => Promise<void>,
) {
  const fixed = detached(
    z.object({ owner: socialUUID, auth: socialUUID, login: socialUUID }).strict().parse(identity),
  )
  const rpc = port.rpc.bind(port)
  function publicIdentity(id: string | null) {
    if (id !== null && (id === fixed.owner || id === fixed.auth)) return unavailable()
  }
  function profile(raw: unknown) {
    const value = output(socialProfileSchema, raw)
    publicIdentity(value.member_id)
    return value
  }
  async function call(action: string, input: unknown) {
    const args = detached({
      p_user_id: fixed.owner,
      p_auth_user_id: fixed.auth,
      p_auth_session_id: fixed.login,
      p_action: action,
      p_input: input,
    })
    await authorize()
    let result: Awaited<ReturnType<JourneySocialRPCPort['rpc']>>
    try {
      result = await rpc('journey_social_patient_authenticated', args)
    } catch {
      return unavailable()
    }
    if (result.error !== null) {
      const parsed = z.object({ code: z.string() }).passthrough().safeParse(result.error)
      const code = parsed.success ? parsed.data.code : ''
      const statuses: Record<string, number> = {
        PT401: 401,
        PT409: 409,
        PT404: 404,
        '42501': 403,
        '22023': 422,
      }
      const status = statuses[code]
      if (!status) return unavailable()
      throw new MobileApiError(
        status,
        status === 409 ? 'journey_social_changed' : `journey_social_${status}`,
        'The original social request is unavailable. Refresh its current state.',
      )
    }
    await authorize()
    return result.data
  }
  async function mutate<
    C extends { operation_id: string; expected_revision: number },
    R extends { operation_id: string; revision: number },
  >(
    action: string,
    command: C,
    schema: z.ZodType<{
      status: 'applied' | 'replayed'
      receipt: R
      profile: z.infer<typeof socialProfileSchema>
    }>,
    matches: (receipt: R) => boolean,
  ) {
    const result = output(schema, await call(action, command))
    profile(result.profile)
    if (
      result.receipt.operation_id !== command.operation_id ||
      result.receipt.revision !== command.expected_revision + 1 ||
      result.profile.revision < result.receipt.revision ||
      !matches(result.receipt) ||
      (result.status === 'applied' && result.profile.revision !== result.receipt.revision)
    )
      return unavailable()
    return result
  }
  return Object.freeze({
    async profile() {
      return profile(await call('profile.read', {}))
    },
    async participate(raw: unknown) {
      const command = detached(socialParticipationCommand.parse(raw))
      const result = await mutate(
        'profile.update',
        command,
        socialMutationSchema(socialParticipationReceipt),
        (receipt) => receipt.opted_in === command.opted_in,
      )
      if (
        result.status === 'applied' &&
        (result.profile.opted_in !== command.opted_in ||
          result.profile.nickname !== command.nickname)
      )
        return unavailable()
      return result
    },
    async block(raw: unknown) {
      const command = detached(socialBlockCommand.parse(raw))
      publicIdentity(command.member_id)
      return mutate(
        'block.update',
        command,
        socialMutationSchema(socialBlockReceipt),
        (receipt) => receipt.member_id === command.member_id && receipt.blocked === command.blocked,
      )
    },
    async report(raw: unknown) {
      const command = detached(socialReportCommand.parse(raw))
      publicIdentity(command.member_id)
      return mutate(
        'report.create',
        command,
        socialMutationSchema(socialReportReceipt),
        (receipt) => {
          publicIdentity(receipt.report_id)
          return true
        },
      )
    },
    async ranking(rawCursor?: unknown, rawLimit: unknown = 50) {
      const cursor =
          rawCursor === undefined ? null : detached(socialRankingCursor.parse(rawCursor)),
        limit = socialLimit.parse(rawLimit)
      const page = output(socialRankingSchema, await call('ranking.read', { limit, cursor }))
      const start = Date.parse(`${page.week_start}T00:00:00Z`),
        end = Date.parse(`${page.week_end}T00:00:00Z`),
        through = Date.parse(`${page.through_date}T00:00:00Z`)
      const offset = cursor?.offset ?? 0
      if (
        new Date(start).getUTCDay() !== 1 ||
        end - start !== 6 * 86400000 ||
        through < start ||
        through > end ||
        page.entries.length > limit
      )
        return unavailable()
      const ids = new Set<string>()
      let yours = 0
      for (const [index, row] of page.entries.entries()) {
        publicIdentity(row.member_id)
        if (ids.has(row.member_id) || row.rank > offset + index + 1) return unavailable()
        ids.add(row.member_id)
        if (row.is_you) yours++
        const previous = page.entries[index - 1]
        if (
          previous &&
          (row.weekly_xp > previous.weekly_xp ||
            (row.weekly_xp === previous.weekly_xp &&
              (row.rank !== previous.rank || row.member_id <= previous.member_id)) ||
            (row.weekly_xp < previous.weekly_xp && row.rank !== offset + index + 1))
        )
          return unavailable()
      }
      if (yours > 1) return unavailable()
      if (
        cursor &&
        (cursor.week_start !== page.week_start || cursor.through_date !== page.through_date)
      )
        return unavailable()
      const next = page.next_cursor
      if (next) {
        publicIdentity(next.viewer_member_id)
        if (
          next.offset !== offset + page.entries.length ||
          page.entries.length !== limit ||
          next.week_start !== page.week_start ||
          next.through_date !== page.through_date ||
          (cursor && !isDeepStrictEqual({ ...cursor, offset: next.offset }, next))
        )
          return unavailable()
      }
      return page
    },
    async blocks(rawCursor?: unknown, rawLimit: unknown = 50) {
      const cursor = rawCursor === undefined ? null : detached(socialBlocksCursor.parse(rawCursor)),
        limit = socialLimit.parse(rawLimit)
      const page = output(
        socialBlocksSchema,
        await call('blocks.read', {
          limit,
          after_member_id: cursor?.after_member_id ?? null,
          expected_revision: cursor?.revision ?? null,
        }),
      )
      if (page.entries.length > limit || (cursor && cursor.revision !== page.revision))
        return unavailable()
      let previous = cursor?.after_member_id
      for (const row of page.entries) {
        publicIdentity(row.member_id)
        if (previous && row.member_id <= previous) return unavailable()
        previous = row.member_id
      }
      if (
        page.next_cursor &&
        (page.entries.length !== limit ||
          page.next_cursor.revision !== page.revision ||
          page.next_cursor.after_member_id !== previous)
      )
        return unavailable()
      return page
    },
  })
}
