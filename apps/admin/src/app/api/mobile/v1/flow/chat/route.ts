import { processAuthenticatedMessage } from '@mpp/agent'
import { OpenRouterLLM } from '@mpp/providers'
import {
  createSupabaseFlowChatStore,
  createSupabaseFlowDraftLookup,
  loadFlowHistory,
  sendFlowMessage,
  summarizeFlowToolCalls,
} from '@/lib/mobile-api/flow-chat-service'
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
      agent: {
        async reply(input) {
          const apiKey = process.env.OPENROUTER_API_KEY
          if (!apiKey) throw new Error('Flow provider is not configured')
          const output = await processAuthenticatedMessage(
            {
              supabase: context.supabase,
              llm: new OpenRouterLLM({
                apiKey,
                heliconeApiKey: process.env.HELICONE_API_KEY,
                appName: 'Performe AI Flow',
              }),
            },
            input,
          )
          if (output.text.trim().length === 0) {
            console.error('[mobile-flow] empty_reply_detail', {
              completion_tokens: output.completionTokens,
              // Serialised: console.error would print nested arrays as [Array].
              tool_calls: JSON.stringify(summarizeFlowToolCalls(output.toolCalls)),
            })
          }
          return {
            text: output.text,
            metadata: {
              stage: output.stage,
              modelUsed: output.modelUsed,
              promptTokens: output.promptTokens,
              completionTokens: output.completionTokens,
              costUsd: output.costUsd,
              latencyMs: output.latencyMs,
            },
          }
        },
      },
    }
  },
  loadHistory: loadFlowHistory,
  sendMessage: sendFlowMessage,
  executeIdempotent: executeSupabaseIdempotent,
  now: () => new Date(),
}

export const GET = createMobileRoute((context) => handleFlowChatGet(context, dependencies))
export const POST = createMobileRoute((context) => handleFlowChatPost(context, dependencies))
