import { createFlowAgent } from '@/lib/mobile-api/flow-agent-factory'
import {
  createSupabaseFlowChatStore,
  createSupabaseFlowDraftLookup,
  loadFlowHistory,
  sendFlowMessage,
} from '@/lib/mobile-api/flow-chat-service'
import { loadFlowPresentationContext } from '@/lib/mobile-api/flow-presentation-context'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { type FlowChatRouteDependencies, handleFlowChatGet, handleFlowChatPost } from './handler'

export const runtime = 'nodejs'
export const maxDuration = 300

const dependencies: FlowChatRouteDependencies = {
  createChatDependencies(context) {
    return {
      store: createSupabaseFlowChatStore(context.supabase),
      drafts: createSupabaseFlowDraftLookup(context.supabase),
      agent: createFlowAgent(context),
    }
  },
  loadHistory: loadFlowHistory,
  sendMessage: sendFlowMessage,
  executeIdempotent: executeSupabaseIdempotent,
  loadPresentationContext: loadFlowPresentationContext,
  now: () => new Date(),
}

export const GET = createMobileRoute((context) => handleFlowChatGet(context, dependencies))
export const POST = createMobileRoute((context) => handleFlowChatPost(context, dependencies))
