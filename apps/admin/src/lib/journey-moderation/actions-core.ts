import { ZodError } from 'zod'
import {
  type ModerationActionResult,
  moderationAction,
  moderationActionResult,
  type OperatorContext,
  operatorContext,
  sameOperatorContext,
} from './action-contracts'
import { type createJourneyModerationService, JourneyModerationError } from './service'

export interface ModerationActionDependencies {
  load(): Promise<{
    context: OperatorContext
    service: ReturnType<typeof createJourneyModerationService>
  }>
}
export async function runJourneyModerationAction(
  raw: unknown,
  deps: ModerationActionDependencies,
): Promise<ModerationActionResult> {
  try {
    const action = moderationAction.parse(raw)
    const bound = await deps.load()
    const context = operatorContext.parse(bound.context)
    if (action.context && !sameOperatorContext(action.context, context))
      return { ok: false, code: 'unauthorized' }
    let result: ModerationActionResult
    switch (action.type) {
      case 'queue':
        result = {
          ok: true,
          context,
          type: action.type,
          value: await bound.service.queue(action.query),
        }
        break
      case 'profile':
        result = {
          ok: true,
          context,
          type: action.type,
          value: await bound.service.profile({ member_id: action.member_id }),
        }
        break
      case 'moderate':
        result = {
          ok: true,
          context,
          type: action.type,
          value: await bound.service.moderate(action.command),
        }
        break
      case 'resolveReport':
        result = {
          ok: true,
          context,
          type: action.type,
          value: await bound.service.resolveReport(action.command),
        }
        break
      case 'recover':
        if (action.pending_owner !== context.owner) return { ok: false, code: 'unauthorized' }
        result = {
          ok: true,
          context,
          type: action.type,
          value: await bound.service.recover(action.request),
        }
        break
    }
    return moderationActionResult.parse(result)
  } catch (error) {
    if (error instanceof JourneyModerationError) return { ok: false, code: error.code }
    if (error instanceof ZodError) return { ok: false, code: 'invalid' }
    return { ok: false, code: 'unavailable' }
  }
}
