import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { createConversationMealJournalService } from './conversation-meal-journal-service'
import { conversationJournalUUID } from './conversation-meal-journal-store'
import { createConversationMealThreadPageService } from './conversation-meal-thread-page-service'
import { MobileApiError, mobileSuccess } from './http'
import { createMobileRoute, type MobileRouteRuntime } from './route'

export interface ConversationMealJournalRoutePorts {
  readonly version2Service?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationMealThreadPageService>, 'read'>
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationMealJournalService>, 'read'>
}
function query(request: Request) {
  const search = new URL(request.url).searchParams
  for (const key of search.keys()) {
    if (!['version', 'limit', 'cursor'].includes(key) || search.getAll(key).length !== 1)
      throw new MobileApiError(
        422,
        'conversation_journal_invalid_query',
        'A closed history query is required',
      )
  }
  const version = search.has('version') ? z.enum(['1', '2']).parse(search.get('version')) : '1'
  return {
    version,
    limit: search.has('limit')
      ? Number(
          z
            .string()
            .regex(/^(?:[1-9]|1[0-9]|2[0-5])$/u)
            .parse(search.get('limit')),
        )
      : 10,
    cursor: search.has('cursor') ? z.string().min(1).max(1024).parse(search.get('cursor')) : null,
  }
}
export function createConversationMealJournalRoutes(
  ports: ConversationMealJournalRoutePorts = {},
  runtime?: MobileRouteRuntime,
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationMealCommandsEnabled,
    service = ports.service?.bind(ports) ?? createConversationMealJournalService,
    version2Service = ports.version2Service?.bind(ports) ?? createConversationMealThreadPageService
  return Object.freeze({
    GET: createMobileRoute(async (context) => {
      if (!enabled())
        throw new MobileApiError(
          503,
          'conversation_commands_unavailable',
          'Conversation command capability is unavailable',
        )
      const owner = conversationJournalUUID.parse(
        context.request.headers.get('X-Conversation-Owner'),
      )
      if (owner !== context.auth.userId)
        throw new MobileApiError(
          409,
          'conversation_patient_changed',
          'The authenticated patient has changed',
        )
      const epoch = conversationJournalUUID.parse(
          context.request.headers.get('X-Conversation-Epoch'),
        ),
        { version, ...input } = query(context.request)
      return mobileSuccess(
        await (version === '2' ? version2Service : service)(context.supabase).read(context.auth, {
          epoch,
          ...input,
        }),
        context.requestId,
      )
    }, runtime),
  })
}
