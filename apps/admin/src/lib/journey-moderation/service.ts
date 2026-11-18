import { z } from 'zod'
import { socialUUID } from '../mobile-api/journey-social-contracts'
import {
  type ModerateProfileCommand,
  moderatedProfile,
  moderateProfileCommand,
  moderationQueue,
  moderationQueueCommand,
  moderationReceipt,
  type ResolveReportCommand,
  recoveredModeration,
  recoverModerationCommand,
  reportReceipt,
  resolvedReport,
  resolveReportCommand,
} from './contracts'

export interface JourneyModerationRPCPort {
  rpc(
    name: 'journey_social_operator_authenticated',
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>
}
export class JourneyModerationError extends Error {
  constructor(
    readonly code: 'unavailable' | 'unauthorized' | 'forbidden' | 'changed' | 'invalid' | 'missing',
  ) {
    super(
      code === 'unavailable'
        ? 'Resultado incerto. Verifique a mesma operação antes de tentar outra ação.'
        : 'A moderação mudou ou não está disponível nesta sessão.',
    )
  }
}
function unavailable(): never {
  throw new JourneyModerationError('unavailable')
}
function freeze<T>(value: T): T {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function output<T>(schema: z.ZodType<T>, raw: unknown): T {
  const result = schema.safeParse(raw)
  return result.success ? freeze(result.data) : unavailable()
}
function micros(value: string): bigint {
  // PostgreSQL emits microseconds. Date alone would collapse distinct queue keys.
  const fraction = value.match(/\.(\d{1,6})(?:Z|[+-]\d{2}:\d{2})$/u)?.[1] ?? ''
  const milliseconds = Date.parse(value)
  if (!Number.isFinite(milliseconds)) return unavailable()
  return BigInt(milliseconds) * 1000n + BigInt(fraction.padEnd(6, '0').slice(3))
}
function compare(
  a: { created_at: string; report_id: string },
  b: { created_at: string; report_id: string },
): number {
  const x = micros(a.created_at)
  const y = micros(b.created_at)
  return x < y ? -1 : x > y ? 1 : a.report_id < b.report_id ? -1 : a.report_id > b.report_id ? 1 : 0
}

/** Fresh original-session admission before/after a single physical call. SQL
 * locks/rechecks that login inside the transaction, including receipt recovery. */
export function createJourneyModerationService(
  port: JourneyModerationRPCPort,
  identity: { actor: string; login: string },
  authorize: () => Promise<void>,
) {
  const fixed = freeze(z.object({ actor: socialUUID, login: socialUUID }).strict().parse(identity))
  const rpc = port.rpc.bind(port)
  function publicID(id: string) {
    if (id === fixed.actor || id === fixed.login) return unavailable()
  }
  async function call(action: string, input: unknown) {
    const args = freeze({
      p_actor_id: fixed.actor,
      p_auth_session_id: fixed.login,
      p_action: action,
      p_input: input,
    })
    await authorize()
    let result: Awaited<ReturnType<JourneyModerationRPCPort['rpc']>>
    try {
      result = await rpc('journey_social_operator_authenticated', args)
    } catch {
      return unavailable()
    }
    if (!result || result.error !== null) {
      const parsed = z.object({ code: z.string() }).passthrough().safeParse(result?.error)
      const codes = {
        PT401: 'unauthorized',
        PT409: 'changed',
        '42501': 'forbidden',
        '22023': 'invalid',
        PT404: 'missing',
      } as const
      const code = parsed.success ? codes[parsed.data.code as keyof typeof codes] : undefined
      if (!code) return unavailable()
      throw new JourneyModerationError(code)
    }
    await authorize()
    return result.data
  }
  function checkProfileReceipt(command: ModerateProfileCommand, raw: unknown) {
    const receipt = output(moderationReceipt, raw)
    publicID(receipt.member_id)
    if (
      receipt.operation_id !== command.operation_id ||
      receipt.member_id !== command.member_id ||
      receipt.revision !== command.expected_revision + 1 ||
      receipt.moderation !== (command.action === 'suspend' ? 'suspended' : 'active')
    )
      return unavailable()
    return receipt
  }
  function checkReportReceipt(command: ResolveReportCommand, raw: unknown) {
    const receipt = output(reportReceipt, raw)
    publicID(receipt.report_id)
    if (
      receipt.operation_id !== command.operation_id ||
      receipt.report_id !== command.report_id ||
      receipt.revision !== command.expected_revision + 1 ||
      receipt.report_status !== command.status
    )
      return unavailable()
    return receipt
  }
  return Object.freeze({
    async queue(raw: unknown) {
      const command = freeze(moderationQueueCommand.parse(raw))
      const result = output(moderationQueue, await call('queue.read', command))
      if (result.entries.length > command.limit) return unavailable()
      const seen = new Set<string>()
      let previous = command.cursor
      for (const entry of result.entries) {
        publicID(entry.member_id)
        publicID(entry.report_id)
        if (seen.has(entry.report_id) || (previous && compare(previous, entry) >= 0))
          return unavailable()
        seen.add(entry.report_id)
        previous = entry
      }
      const cursor = result.next_cursor
      if (
        cursor &&
        (result.entries.length !== command.limit || !previous || compare(cursor, previous) !== 0)
      )
        return unavailable()
      return result
    },
    async moderate(raw: unknown) {
      const command = freeze(moderateProfileCommand.parse(raw))
      publicID(command.member_id)
      const result = output(moderatedProfile, await call('profile.moderate', command))
      checkProfileReceipt(command, result.receipt)
      if (
        result.profile.member_id !== command.member_id ||
        result.profile.revision < result.receipt.revision ||
        (result.status === 'applied' &&
          (result.profile.revision !== result.receipt.revision ||
            result.profile.moderation !== result.receipt.moderation))
      )
        return unavailable()
      return result
    },
    async resolveReport(raw: unknown) {
      const command = freeze(resolveReportCommand.parse(raw))
      publicID(command.report_id)
      const result = output(resolvedReport, await call('report.resolve', command))
      checkReportReceipt(command, result.receipt)
      return result
    },
    async recover(raw: unknown) {
      const input = freeze(recoverModerationCommand.parse(raw))
      if (input.kind === 'profile') publicID(input.command.member_id)
      else publicID(input.command.report_id)
      const result = output(recoveredModeration, await call('operation.resolve', input))
      if (
        result.kind !== input.kind ||
        result.operation_id !== input.command.operation_id ||
        result.expected_revision !== input.command.expected_revision
      )
        return unavailable()
      if (result.status === 'fenced') {
        if (result.receipt !== null) return unavailable()
      } else if (input.kind === 'profile') checkProfileReceipt(input.command, result.receipt)
      else checkReportReceipt(input.command, result.receipt)
      return result
    },
  })
}
